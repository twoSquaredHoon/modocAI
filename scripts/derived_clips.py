"""Sync EXPLAIN and SIGNS clips into decisions, clips.json, and clip_prompts.txt."""

from __future__ import annotations

import json
import re
from pathlib import Path

from explain_clip_prompt import (
    build_explain_clips_list,
    extract_explain_bullets,
    format_explain_decision_lines,
    is_explain_clip_id,
)
from signs_clip_prompt import (
    build_signs_clips_list,
    clip_sort_key,
    extract_warning_bullets,
    format_signs_decision_lines,
    is_signs_clip_id,
)
from visual_cast import get_visual_cast, language_from_script_header


def _prompt_to_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, dict):
        parts: list[str] = []
        for key, val in value.items():
            label = str(key).replace("_", " ").strip().upper()
            parts.append(f"{label}: {_prompt_to_text(val)}")
        return "\n".join(parts)
    if isinstance(value, list):
        return "\n".join(_prompt_to_text(item) for item in value if item)
    return str(value).strip()


def _strip_derived_decision_lines(text: str) -> str:
    text = re.sub(
        r"^EXPLAIN CLIP(?: \d+)?:.*\n",
        "",
        text,
        flags=re.MULTILINE | re.IGNORECASE,
    )
    text = re.sub(
        r"^SIGNS CLIP(?: \d+)?:.*\n",
        "",
        text,
        flags=re.MULTILINE | re.IGNORECASE,
    )
    return text


def inject_derived_decisions(
    clip_decisions: str,
    *,
    explain_lines: list[str],
    signs_lines: list[str],
) -> str:
    """Insert EXPLAIN and SIGNS decision lines before RELIEF (or at end)."""
    text = _strip_derived_decision_lines(clip_decisions).rstrip()
    block = "\n".join(explain_lines + signs_lines)
    if not block:
        return text + "\n" if text else ""

    if re.search(r"^RELIEF CLIP:", text, re.MULTILINE | re.IGNORECASE):
        text = re.sub(
            r"^(RELIEF CLIP:)",
            block + r"\n\1",
            text,
            count=1,
            flags=re.MULTILINE | re.IGNORECASE,
        )
    elif re.search(r"^SIGNS CLIP 1:", text, re.MULTILINE | re.IGNORECASE):
        text = re.sub(
            r"^(SIGNS CLIP 1:)",
            block + r"\n\1",
            text,
            count=1,
            flags=re.MULTILINE | re.IGNORECASE,
        )
    else:
        text = text + "\n" + block
    return text.rstrip() + "\n"


def apply_derived_clips(
    script_raw: str,
    clip_decisions: str,
    clips: list[dict],
    *,
    language: str | None = None,
) -> tuple[str, list[dict]]:
    """
    Always attach explain_N and signs_N clips from the script.
    Returns updated clip_decisions (with EXPLAIN/SIGNS lines) and merged clips list.
    """
    lang = language or language_from_script_header(script_raw) or "en"
    cast = get_visual_cast(lang, script_raw)

    explain_bullets = extract_explain_bullets(script_raw)
    signs_bullets = extract_warning_bullets(script_raw)

    explain_lines = format_explain_decision_lines(explain_bullets, cast=cast)
    signs_lines = format_signs_decision_lines(signs_bullets, cast=cast)

    merged_decisions = inject_derived_decisions(
        clip_decisions,
        explain_lines=explain_lines,
        signs_lines=signs_lines,
    )

    other = [
        c
        for c in clips
        if not is_explain_clip_id(str(c.get("id", "")))
        and not is_signs_clip_id(str(c.get("id", "")))
    ]
    derived = build_explain_clips_list(explain_bullets, cast=cast)
    derived.extend(build_signs_clips_list(signs_bullets, cast=cast))
    merged_clips = other + derived
    merged_clips.sort(key=lambda c: clip_sort_key(str(c["id"])))

    if explain_bullets:
        print(
            f"  EXPLAIN clips: {len(explain_bullets)} "
            f"({', '.join(f'explain_{i}' for i in range(1, len(explain_bullets) + 1))})"
        )
    if signs_bullets:
        print(
            f"  SIGNS clips: {len(signs_bullets)} "
            f"({', '.join(f'signs_{i}' for i in range(1, len(signs_bullets) + 1))})"
        )

    return merged_decisions, merged_clips


def format_clip_prompts_text(clips: list[dict]) -> str:
    lines = ["# Clip prompts\n"]
    for clip in sorted(clips, key=lambda c: clip_sort_key(str(c.get("id", "")))):
        lines.append(f"## {clip['label']} ({clip['id']})\n\n")
        lines.append(_prompt_to_text(clip.get("detailed_prompt")))
        lines.append("\n\n**Veo prompt:**\n\n")
        lines.append(_prompt_to_text(clip.get("veo_prompt")))
        lines.append("\n\n")
    return "".join(lines)


def sync_derived_in_folder(
    clips_dir: Path,
    script_path: Path,
    *,
    language: str | None = None,
) -> tuple[list[str], list[str]]:
    """Refresh explain/signs in clip_decisions, clips.json, and clip_prompts.txt."""
    script_raw = script_path.read_text(encoding="utf-8")
    decisions_path = clips_dir / "clip_decisions.txt"
    clip_decisions = (
        decisions_path.read_text(encoding="utf-8") if decisions_path.is_file() else ""
    )

    clips_json = clips_dir / "clips.json"
    clips: list[dict] = []
    if clips_json.is_file():
        data = json.loads(clips_json.read_text(encoding="utf-8"))
        clips = data.get("clips", [])

    clip_decisions, clips = apply_derived_clips(
        script_raw,
        clip_decisions,
        clips,
        language=language,
    )

    clips_dir.mkdir(parents=True, exist_ok=True)
    decisions_path.write_text(clip_decisions, encoding="utf-8")
    clips_json.write_text(
        json.dumps({"clips": clips}, indent=2) + "\n", encoding="utf-8"
    )
    (clips_dir / "clip_prompts.txt").write_text(
        format_clip_prompts_text(clips), encoding="utf-8"
    )

    explain_ids = [c["id"] for c in clips if is_explain_clip_id(str(c.get("id", "")))]
    signs_ids = [c["id"] for c in clips if is_signs_clip_id(str(c.get("id", "")))]
    print(f"Synced {len(explain_ids)} explain + {len(signs_ids)} signs clip(s) in {clips_dir}")
    return explain_ids, signs_ids


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Sync EXPLAIN and SIGNS clips into project artifacts."
    )
    parser.add_argument("clips_dir", type=Path)
    parser.add_argument("script", type=Path)
    parser.add_argument("--language", choices=["en", "ko", "es"], default=None)
    args = parser.parse_args()
    explain_ids, signs_ids = sync_derived_in_folder(
        args.clips_dir, args.script, language=args.language
    )
    print("Explain:", ", ".join(explain_ids) if explain_ids else "(none)")
    print("Signs:", ", ".join(signs_ids) if signs_ids else "(none)")
