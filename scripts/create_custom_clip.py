#!/usr/bin/env python3
"""Create a custom clip from user-selected script lines."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from derived_clips import format_clip_prompts_text
from gemini_util import get_client
from script_to_clips import (
    TEXT_MODEL,
    VEO_MODEL,
    clip_is_done,
    generate_all_clips,
    load_script,
    merge_clip_into_clips_json,
    prompt_to_text,
    run_gemini_text,
    validate_clip_dict,
)
from signs_clip_prompt import clip_sort_key
from visual_cast import get_visual_cast, language_from_script_header

CUSTOM_ID_RE = re.compile(r"^custom_(\d+)$")


def next_custom_clip_id(clips: list[dict]) -> tuple[str, int]:
    nums = [
        int(m.group(1))
        for c in clips
        if (m := CUSTOM_ID_RE.match(str(c.get("id", ""))))
    ]
    n = max(nums, default=0) + 1
    return f"custom_{n}", n


def load_lines(path: Path) -> list[str]:
    lines = [
        ln.strip()
        for ln in path.read_text(encoding="utf-8").splitlines()
        if ln.strip()
    ]
    if not lines:
        raise ValueError(f"No script lines in {path}")
    return lines


def append_custom_decision(decisions_path: Path, *, number: int, description: str) -> None:
    line = f"CUSTOM CLIP {number}: {description.strip()}\n"
    existing = (
        decisions_path.read_text(encoding="utf-8") if decisions_path.is_file() else ""
    )
    existing = existing.rstrip()
    if re.search(r"^RELIEF CLIP:", existing, re.MULTILINE | re.IGNORECASE):
        existing = re.sub(
            r"^(RELIEF CLIP:)",
            line + r"\1",
            existing,
            count=1,
            flags=re.MULTILINE | re.IGNORECASE,
        )
    else:
        existing = (existing + "\n\n" + line).strip() if existing else line.strip()
    decisions_path.write_text(existing + "\n", encoding="utf-8")


def generate_custom_clip(
    client,
    *,
    model: str,
    cast_bible: str,
    full_script: str,
    selected_lines: list[str],
    clip_id: str,
    clip_number: int,
) -> tuple[dict, str]:
    selected_block = "\n".join(selected_lines)
    user = f"""
You create ONE custom video clip for a parenting health short.

{cast_bible}

FULL SCRIPT (context):
---
{full_script}
---

SELECTED LINES (this clip must visualize ONLY what these lines say):
---
{selected_block}
---

Output valid JSON only:
{{
  "description": "one sentence — what the viewer should see",
  "detailed_prompt": "SUBJECT / SETTING / ACTION / MOOD / CAMERA / LIGHTING / STYLE",
  "veo_prompt": "single paragraph for Veo, cinematic 4K, no on-screen text, exact child age from cast",
  "duration_seconds": 4 or 6
}}

Rules:
- id will be "{clip_id}" / label "CUSTOM CLIP {clip_number}"
- Medically accurate to the selected lines only; do not invent facts
- Match cast bible age and appearance exactly
- duration_seconds: 4 for a single short beat; 6 for a richer scene
"""
    raw = run_gemini_text(
        client,
        model=model,
        user=user,
        system=(
            "You write precise AI video prompts for parenting videos. "
            "Output valid JSON only."
        ),
        json_mode=True,
        max_retries=3,
    )
    data = json.loads(raw.strip().removeprefix("```json").removesuffix("```").strip())
    clip = validate_clip_dict(
        {
            "id": clip_id,
            "label": f"CUSTOM CLIP {clip_number}",
            "detailed_prompt": data.get("detailed_prompt"),
            "veo_prompt": data.get("veo_prompt"),
            "duration_seconds": data.get("duration_seconds", 6),
            "script_line": selected_block,
        }
    )
    clip["script_line"] = selected_block
    return clip, str(data.get("description", selected_block[:120]))


def refresh_prompts_file(out_dir: Path) -> None:
    clips_path = out_dir / "clips.json"
    data = json.loads(clips_path.read_text(encoding="utf-8"))
    clips = sorted(data.get("clips", []), key=lambda c: clip_sort_key(str(c.get("id", ""))))
    (out_dir / "clip_prompts.txt").write_text(
        format_clip_prompts_text(clips), encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a custom clip from selected script lines."
    )
    parser.add_argument(
        "project_dir",
        type=Path,
        help="Project folder (contains script.txt; writes clips.json)",
    )
    parser.add_argument(
        "--lines-file",
        type=Path,
        required=True,
        help="UTF-8 file with one selected script line per line",
    )
    parser.add_argument(
        "--language",
        default=None,
        choices=["en", "ko", "es"],
        help="Cast language (default: from script header)",
    )
    parser.add_argument(
        "--text-model",
        default=TEXT_MODEL,
        help=f"Gemini model (default: {TEXT_MODEL})",
    )
    parser.add_argument(
        "--veo-model",
        default=VEO_MODEL,
        help=f"Veo model (default: {VEO_MODEL})",
    )
    parser.add_argument(
        "--generate-video",
        action="store_true",
        help="Also generate the Veo video (paid)",
    )
    parser.add_argument(
        "--poll-seconds",
        type=int,
        default=15,
    )
    args = parser.parse_args()

    out_dir = args.project_dir.expanduser().resolve()
    script_path = out_dir / "script.txt"
    if not script_path.is_file():
        print(f"Missing script.txt in {out_dir}", file=sys.stderr)
        sys.exit(1)

    selected_lines = load_lines(args.lines_file)
    script_raw = script_path.read_text(encoding="utf-8")
    full_script = load_script(script_path)
    lang = args.language or language_from_script_header(script_raw) or "en"
    cast_bible = get_visual_cast(lang, script_raw)

    clips_path = out_dir / "clips.json"
    existing: list[dict] = []
    if clips_path.is_file():
        data = json.loads(clips_path.read_text(encoding="utf-8"))
        existing = data.get("clips", [])

    clip_id, clip_number = next_custom_clip_id(existing)
    print(f"Creating {clip_id} from {len(selected_lines)} script line(s)...")

    client = get_client()
    clip, description = generate_custom_clip(
        client,
        model=args.text_model,
        cast_bible=cast_bible,
        full_script=full_script,
        selected_lines=selected_lines,
        clip_id=clip_id,
        clip_number=clip_number,
    )

    merge_clip_into_clips_json(out_dir, clip)
    append_custom_decision(
        out_dir / "clip_decisions.txt",
        number=clip_number,
        description=description,
    )
    refresh_prompts_file(out_dir)

    print(f"  Saved prompt → {clips_path}")
    print(f"  script_line: {clip['script_line'][:80]}...")

    if args.generate_video:
        generate_all_clips(
            client,
            [clip],
            veo_model=args.veo_model,
            out_dir=out_dir,
            poll_seconds=args.poll_seconds,
        )
    else:
        print("  Prompt only (no Veo). Generate video from Modoc Studio Clips tab.")

    print(f"Done. Clip id: {clip_id}")


if __name__ == "__main__":
    main()
