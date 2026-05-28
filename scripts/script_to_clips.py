#!/usr/bin/env python3
"""Turn a video script into clip prompts and generate Veo video clips."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

from google.genai import types

from gemini_util import PROJECT_ROOT, get_client
from prompts import CLIP_DECISION_PROMPT, CLIP_DETAIL_JSON_INSTRUCTION
from veo_util import generate_video

TEXT_MODEL = "gemini-2.5-flash"
VEO_MODEL = "veo-3.1-fast-generate-preview"
OUTPUT_BASE = PROJECT_ROOT / "output" / "clips"


def prompt_to_text(value) -> str:
    """Coerce Gemini output (str or nested dict) into plain text."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, dict):
        parts: list[str] = []
        for key, val in value.items():
            label = str(key).replace("_", " ").strip().upper()
            parts.append(f"{label}: {prompt_to_text(val)}")
        return "\n".join(parts)
    if isinstance(value, list):
        return "\n".join(prompt_to_text(item) for item in value if item)
    return str(value).strip()


def load_script(path: Path) -> str:
    lines: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        lines.append(line)
    text = "\n".join(lines).strip()
    if not text:
        raise ValueError(f"No script content in {path}")
    return text


def run_gemini_text(client, *, model: str, user: str, system: str | None = None) -> str:
    config = types.GenerateContentConfig(temperature=0.4)
    if system:
        config.system_instruction = system
    response = client.models.generate_content(
        model=model,
        contents=user,
        config=config,
    )
    text = (response.text or "").strip()
    if not text:
        raise RuntimeError("Gemini returned empty text.")
    return text


def decide_clips(client, script: str, *, model: str) -> str:
    print("Step 1/3: Deciding what clips are needed...")
    user = f"{CLIP_DECISION_PROMPT}\n\nSCRIPT:\n---\n{script}\n---"
    return run_gemini_text(
        client,
        model=model,
        user=user,
        system="You plan visuals for short parenting videos. Stay faithful to the script.",
    )


def build_veo_prompts(client, clip_decisions: str, *, model: str) -> list[dict]:
    print("Step 2/3: Writing detailed video prompts...")
    user = (
        f"{CLIP_DETAIL_JSON_INSTRUCTION}\n\n"
        f"CLIP DESCRIPTIONS:\n---\n{clip_decisions}\n---"
    )
    raw = run_gemini_text(
        client,
        model=model,
        user=user,
        system="You write precise AI video prompts. Output valid JSON only.",
    )
    raw = raw.strip()
    if raw.startswith("```"):
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Could not parse clip JSON: {exc}\n\n{raw[:500]}") from exc

    clips = data.get("clips")
    if not isinstance(clips, list) or not clips:
        raise RuntimeError("JSON must contain a non-empty 'clips' array.")

    validated: list[dict] = []
    for clip in clips:
        clip_id = clip.get("id")
        veo_prompt = prompt_to_text(clip.get("veo_prompt"))
        if not clip_id or not veo_prompt:
            raise RuntimeError(f"Each clip needs id and veo_prompt: {clip}")
        duration = int(clip.get("duration_seconds", 6))
        if duration not in (4, 6, 8):
            duration = 6
        validated.append(
            {
                "id": str(clip_id),
                "label": str(clip.get("label", clip_id)),
                "detailed_prompt": prompt_to_text(clip.get("detailed_prompt")),
                "veo_prompt": veo_prompt,
                "duration_seconds": duration,
            }
        )
    print(f"  Planned {len(validated)} clips: {', '.join(c['id'] for c in validated)}")
    return validated


def load_clips_from_dir(out_dir: Path) -> list[dict]:
    clips_path = out_dir / "clips.json"
    if not clips_path.is_file():
        raise FileNotFoundError(f"No clips.json in {out_dir}")
    data = json.loads(clips_path.read_text(encoding="utf-8"))
    clips = data.get("clips")
    if not isinstance(clips, list) or not clips:
        raise ValueError(f"Invalid clips.json in {out_dir}")
    return clips


def clip_is_done(video_path: Path, *, min_bytes: int = 1000) -> bool:
    return video_path.is_file() and video_path.stat().st_size >= min_bytes


def save_prompt_artifacts(
    out_dir: Path,
    *,
    script: str,
    clip_decisions: str,
    clips: list[dict],
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "script.txt").write_text(script + "\n", encoding="utf-8")
    (out_dir / "clip_decisions.txt").write_text(clip_decisions + "\n", encoding="utf-8")

    lines = ["# Clip prompts\n"]
    for clip in clips:
        lines.append(f"## {clip['label']} ({clip['id']})\n\n")
        lines.append(prompt_to_text(clip.get("detailed_prompt")))
        lines.append("\n\n**Veo prompt:**\n\n")
        lines.append(prompt_to_text(clip.get("veo_prompt")))
        lines.append("\n\n")
    (out_dir / "clip_prompts.txt").write_text("".join(lines), encoding="utf-8")
    (out_dir / "clips.json").write_text(
        json.dumps({"clips": clips}, indent=2) + "\n", encoding="utf-8"
    )


def generate_all_clips(
    client,
    clips: list[dict],
    *,
    veo_model: str,
    out_dir: Path,
    poll_seconds: int,
    max_attempts: int = 2,
) -> list[Path]:
    videos_dir = out_dir / "videos"
    videos_dir.mkdir(parents=True, exist_ok=True)

    pending = [
        c for c in clips if not clip_is_done(videos_dir / f"{c['id']}.mp4")
    ]
    done_count = len(clips) - len(pending)

    if done_count:
        print(f"  Skipping {done_count} clip(s) already on disk.")
    if not pending:
        print("  All clips already generated.")
        return [videos_dir / f"{c['id']}.mp4" for c in clips]

    print(
        f"Step 3/3: Generating {len(pending)} video(s) "
        f"with {veo_model} (paid)..."
    )
    saved: list[Path] = []

    for i, clip in enumerate(clips, start=1):
        clip_id = clip["id"]
        out_path = videos_dir / f"{clip_id}.mp4"
        if clip_is_done(out_path):
            print(f"\n  [{i}/{len(clips)}] {clip_id} — already done, skipping")
            saved.append(out_path)
            continue

        print(f"\n  [{i}/{len(clips)}] {clip_id} ({clip['duration_seconds']}s)")
        print(f"    {clip['veo_prompt'][:120]}...")
        try:
            generate_video(
                client,
                model=veo_model,
                prompt=clip["veo_prompt"],
                output_path=out_path,
                duration_seconds=clip["duration_seconds"],
                poll_seconds=poll_seconds,
                max_attempts=max_attempts,
            )
            print(f"    saved → {out_path}")
            saved.append(out_path)
        except Exception as exc:
            print(f"    FAILED: {exc}", file=sys.stderr)
            print(
                f"\nResume from here:\n"
                f"  ./script-to-clips.sh --resume {out_dir}",
                file=sys.stderr,
            )
            raise

    return saved


def find_latest_run_for_script(script_path: Path) -> Path | None:
    slug = script_path.stem[:50]
    if not OUTPUT_BASE.is_dir():
        return None
    candidates = sorted(
        (p for p in OUTPUT_BASE.iterdir() if p.is_dir() and p.name.startswith(slug)),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for folder in candidates:
        if (folder / "clips.json").is_file():
            return folder
    return None


def output_dir_for_script(script_path: Path) -> Path:
    slug = script_path.stem
    if len(slug) > 50:
        slug = slug[:50]
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    return OUTPUT_BASE / f"{slug}-{stamp}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate clip prompts and Veo videos from a script file."
    )
    parser.add_argument(
        "script",
        type=Path,
        nargs="?",
        help="Path to script .txt (optional if using --resume)",
    )
    parser.add_argument(
        "--resume",
        type=Path,
        metavar="DIR",
        help="Resume video generation in an existing output/clips/... folder",
    )
    parser.add_argument(
        "--text-model",
        default=TEXT_MODEL,
        help=f"Gemini model for prompts (default: {TEXT_MODEL})",
    )
    parser.add_argument(
        "--veo-model",
        default=VEO_MODEL,
        help=f"Veo model for video (default: {VEO_MODEL})",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Output folder (default: output/clips/<script-name>-<timestamp>)",
    )
    parser.add_argument(
        "--prompts-only",
        action="store_true",
        help="Only write clip decisions and prompts; do not call Veo (no charge).",
    )
    parser.add_argument(
        "--poll-seconds",
        type=int,
        default=15,
        help="Seconds between Veo status checks (default: 15)",
    )
    parser.add_argument(
        "--max-attempts",
        type=int,
        default=2,
        help="Retries per clip when Veo returns no video (default: 2)",
    )
    args = parser.parse_args()

    if not args.resume and not args.script:
        parser.error("Provide a script path or --resume DIR")

    try:
        client = get_client()

        clips: list[dict]

        if args.resume:
            out_dir = args.resume.expanduser().resolve()
            if not out_dir.is_dir():
                raise FileNotFoundError(f"Resume folder not found: {out_dir}")
            clips = load_clips_from_dir(out_dir)
            print(f"Resuming in {out_dir}")
            print(f"  Clips: {', '.join(c['id'] for c in clips)}")
        else:
            script_path = args.script.expanduser().resolve()
            if not script_path.is_file():
                raise FileNotFoundError(f"Script not found: {script_path}")

            clips = []
            if args.output_dir:
                out_dir = args.output_dir.expanduser().resolve()
            elif not args.prompts_only:
                latest = find_latest_run_for_script(script_path)
                if latest:
                    loaded = load_clips_from_dir(latest)
                    pending = [
                        c
                        for c in loaded
                        if not clip_is_done(latest / "videos" / f"{c['id']}.mp4")
                    ]
                    if pending:
                        out_dir = latest
                        clips = loaded
                        print(f"Continuing incomplete run: {out_dir}")

            if not clips:
                out_dir = (
                    args.output_dir.expanduser().resolve()
                    if args.output_dir
                    else output_dir_for_script(script_path)
                )
                script = load_script(script_path)
                clip_decisions = decide_clips(client, script, model=args.text_model)
                clips = build_veo_prompts(client, clip_decisions, model=args.text_model)
                save_prompt_artifacts(
                    out_dir, script=script, clip_decisions=clip_decisions, clips=clips
                )
                print(f"\nPrompts saved under {out_dir}")

        if args.prompts_only:
            print("Skipped video generation (--prompts-only).")
            return

        saved = generate_all_clips(
            client,
            clips,
            veo_model=args.veo_model,
            out_dir=out_dir,
            poll_seconds=args.poll_seconds,
            max_attempts=args.max_attempts,
        )
    except Exception as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"\nDone. {len(saved)} clips in {out_dir / 'videos'}")


if __name__ == "__main__":
    main()
