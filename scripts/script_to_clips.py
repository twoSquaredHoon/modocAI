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
from path_hints import format_script_not_found
from prompts import CLIP_DECISION_PROMPT, CLIP_DETAIL_JSON_INSTRUCTION
from signs_clip_prompt import (
    clip_sort_key,
    is_signs_clip_id,
    merge_signs_clips_into_list,
    update_signs_in_folder,
)
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


def extract_response_text(response) -> str:
    text = (response.text or "").strip()
    if text:
        return text
    candidates = getattr(response, "candidates", None) or []
    if candidates:
        content = getattr(candidates[0], "content", None)
        parts = getattr(content, "parts", None) if content else None
        if parts:
            chunks: list[str] = []
            for part in parts:
                if getattr(part, "text", None):
                    chunks.append(part.text)
            if chunks:
                return "\n".join(chunks).strip()
    return ""


def describe_response_failure(response) -> str:
    parts = ["Gemini returned empty text."]
    candidates = getattr(response, "candidates", None) or []
    if candidates:
        finish = getattr(candidates[0], "finish_reason", None)
        if finish:
            parts.append(f"finish_reason={finish}")
    feedback = getattr(response, "prompt_feedback", None)
    if feedback:
        block = getattr(feedback, "block_reason", None)
        if block:
            parts.append(f"block_reason={block}")
    return " ".join(parts)


def run_gemini_text(
    client,
    *,
    model: str,
    user: str,
    system: str | None = None,
    json_mode: bool = False,
    max_retries: int = 3,
) -> str:
    last_error = "unknown error"
    for attempt in range(1, max_retries + 1):
        config = types.GenerateContentConfig(
            temperature=0.35 if attempt == 1 else 0.5,
        )
        if system:
            config.system_instruction = system
        if json_mode:
            config.response_mime_type = "application/json"

        response = client.models.generate_content(
            model=model,
            contents=user,
            config=config,
        )
        text = extract_response_text(response)
        if text:
            return text

        last_error = describe_response_failure(response)
        if attempt < max_retries:
            print(f"  Retry {attempt + 1}/{max_retries} ({last_error})")

    raise RuntimeError(last_error)


def decide_clips(client, script: str, *, model: str) -> str:
    print("Step 1/3: Deciding what clips are needed...")
    user = f"{CLIP_DECISION_PROMPT}\n\nSCRIPT:\n---\n{script}\n---"
    return run_gemini_text(
        client,
        model=model,
        user=user,
        system="You plan visuals for short parenting videos. Stay faithful to the script.",
    )


SINGLE_CLIP_PROMPT = """
You write one AI video generation prompt for a parenting health video clip.
Output valid JSON only:
{"id": "...", "label": "...", "detailed_prompt": "...", "veo_prompt": "...", "duration_seconds": 6}

Rules for veo_prompt: one paragraph, cinematic realistic 4K, natural colors, no text on screen
(except SIGNS clip), specific ages and physical details where people appear, no vague words.
duration_seconds: 4 for hook and cta; 6 for body_1, body_2, signs, relief.
SIGNS clips (signs_1, signs_2, …): one clip per warning sign; each is a single wordless
presentation image on a clean background; no text on screen.
"""


def parse_clip_decisions(clip_decisions: str) -> list[tuple[str, str, str]]:
    """Parse HOOK CLIP: ... lines into (id, label, description)."""
    patterns: list[tuple[str, str, str]] = [
        (r"^HOOK CLIP:\s*(.+)$", "hook", "HOOK CLIP"),
        (r"^BODY CLIP 1:\s*(.+)$", "body_1", "BODY CLIP 1"),
        (r"^BODY CLIP 2:\s*(.+)$", "body_2", "BODY CLIP 2"),
        (r"^SIGNS CLIP (\d+):\s*(.+)$", "signs", "SIGNS CLIP"),
        (r"^RELIEF CLIP:\s*(.+)$", "relief", "RELIEF CLIP"),
        (r"^CTA CLIP:\s*(.+)$", "cta", "CTA CLIP"),
    ]
    found: list[tuple[str, str, str]] = []
    for line in clip_decisions.splitlines():
        line = line.strip()
        if not line:
            continue
        for pattern, clip_id, label in patterns:
            match = re.match(pattern, line, re.IGNORECASE)
            if match:
                if clip_id == "signs" and label == "SIGNS CLIP" and match.lastindex == 2:
                    n = match.group(1)
                    found.append((f"signs_{n}", f"SIGNS CLIP {n}", match.group(2).strip()))
                else:
                    found.append((clip_id, label, match.group(1).strip()))
                break
    return found


def default_duration(clip_id: str) -> int:
    if clip_id in ("hook", "cta") or is_signs_clip_id(clip_id):
        return 4
    return 6


def validate_clip_dict(clip: dict) -> dict:
    clip_id = clip.get("id")
    veo_prompt = prompt_to_text(clip.get("veo_prompt"))
    if not clip_id or not veo_prompt:
        raise RuntimeError(f"Each clip needs id and veo_prompt: {clip}")
    duration = int(clip.get("duration_seconds", default_duration(str(clip_id))))
    if duration not in (4, 6, 8):
        duration = default_duration(str(clip_id))
    return {
        "id": str(clip_id),
        "label": str(clip.get("label", clip_id)),
        "detailed_prompt": prompt_to_text(clip.get("detailed_prompt")),
        "veo_prompt": veo_prompt,
        "duration_seconds": duration,
    }


def parse_clips_json(raw: str) -> list[dict]:
    raw = raw.strip()
    if raw.startswith("```"):
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)
    data = json.loads(raw)
    clips = data.get("clips")
    if not isinstance(clips, list) or not clips:
        raise RuntimeError("JSON must contain a non-empty 'clips' array.")
    return [validate_clip_dict(clip) for clip in clips]


def build_veo_prompts_one_by_one(
    client, parsed: list[tuple[str, str, str]], *, model: str
) -> list[dict]:
    print("  Using per-clip prompt generation (fallback)...")
    validated: list[dict] = []
    for clip_id, label, description in parsed:
        user = (
            f"{SINGLE_CLIP_PROMPT}\n\n"
            f'id="{clip_id}" label="{label}"\n'
            f"Clip description: {description}"
        )
        raw = run_gemini_text(
            client,
            model=model,
            user=user,
            system="Output JSON only.",
            json_mode=True,
            max_retries=2,
        )
        validated.append(validate_clip_dict(json.loads(raw)))
    return validated


def build_veo_prompts(client, clip_decisions: str, *, model: str) -> list[dict]:
    print("Step 2/3: Writing detailed video prompts...")
    user = (
        f"{CLIP_DETAIL_JSON_INSTRUCTION}\n\n"
        f"CLIP DESCRIPTIONS:\n---\n{clip_decisions}\n---"
    )
    try:
        raw = run_gemini_text(
            client,
            model=model,
            user=user,
            system="You write precise AI video prompts. Output valid JSON only.",
            json_mode=True,
            max_retries=3,
        )
        validated = parse_clips_json(raw)
    except (RuntimeError, json.JSONDecodeError) as exc:
        print(f"  Batch JSON failed ({exc}); trying per-clip fallback...")
        parsed = parse_clip_decisions(clip_decisions)
        if not parsed:
            raise RuntimeError(
                "Could not parse clip decisions and batch JSON failed."
            ) from exc
        validated = build_veo_prompts_one_by_one(client, parsed, model=model)

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


def merge_clip_into_clips_json(out_dir: Path, new_clip: dict) -> None:
    """Add or replace one clip entry in out_dir/clips.json."""
    path = out_dir / "clips.json"
    if path.is_file():
        data = json.loads(path.read_text(encoding="utf-8"))
        clips = [c for c in data.get("clips", []) if c.get("id") != new_clip["id"]]
    else:
        data = {}
        clips = []
    clips.append(new_clip)
    clips.sort(key=lambda c: clip_sort_key(str(c.get("id", ""))))
    data["clips"] = clips
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


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

    clips = sorted(clips, key=lambda c: clip_sort_key(str(c.get("id", ""))))

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
    parser.add_argument(
        "--only",
        metavar="CLIP_ID",
        help="Generate one clip id, or 'signs' for all signs_1, signs_2, …. Requires --resume.",
    )
    parser.add_argument(
        "--prompts-dir",
        type=Path,
        metavar="DIR",
        help="Read prompts from this folder's clips.json (with --only / --resume)",
    )
    args = parser.parse_args()

    if args.only and not args.resume:
        parser.error("--only requires --resume DIR")
    if not args.resume and not args.script:
        parser.error("Provide a script path or --resume DIR")

    try:
        client = get_client()

        clips: list[dict]

        if args.resume:
            out_dir = args.resume.expanduser().resolve()
            if not out_dir.is_dir():
                raise FileNotFoundError(f"Resume folder not found: {out_dir}")
            prompts_dir = (
                args.prompts_dir.expanduser().resolve()
                if args.prompts_dir
                else out_dir
            )
            clips = load_clips_from_dir(prompts_dir)
            if args.prompts_dir:
                print(f"Using prompts from {prompts_dir}")
            print(f"Resuming in {out_dir}")
            if args.only:
                if args.only == "signs":
                    clips = [
                        c for c in clips if is_signs_clip_id(str(c.get("id", "")))
                    ]
                    print(f"  Generating all signs clips: {', '.join(c['id'] for c in clips)}")
                else:
                    clips = [c for c in clips if c["id"] == args.only]
                    print(f"  Generating only: {args.only}")
                if not clips:
                    raise ValueError(
                        f"No clip matching '{args.only}' in {prompts_dir}/clips.json"
                    )
            else:
                print(f"  Clips: {', '.join(c['id'] for c in clips)}")
        else:
            script_path = args.script.expanduser().resolve()
            if not script_path.is_file():
                raise FileNotFoundError(format_script_not_found(script_path))

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
                out_dir.mkdir(parents=True, exist_ok=True)
                clip_decisions = decide_clips(client, script, model=args.text_model)
                (out_dir / "clip_decisions.txt").write_text(
                    clip_decisions + "\n", encoding="utf-8"
                )
                try:
                    clips = build_veo_prompts(
                        client, clip_decisions, model=args.text_model
                    )
                    clips = merge_signs_clips_into_list(script, clips)
                    save_prompt_artifacts(
                        out_dir,
                        script=script,
                        clip_decisions=clip_decisions,
                        clips=clips,
                    )
                    print(f"\nPrompts saved under {out_dir}")
                except Exception:
                    print(
                        f"\nStep 2 failed. Clip decisions saved at:\n  {out_dir / 'clip_decisions.txt'}",
                        file=sys.stderr,
                    )
                    raise

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
        if args.only and args.only != "signs" and len(clips) == 1:
            merge_clip_into_clips_json(out_dir, clips[0])
            print(f"  Updated {out_dir / 'clips.json'} with '{args.only}'")
    except Exception as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"\nDone. {len(saved)} clips in {out_dir / 'videos'}")


if __name__ == "__main__":
    main()
