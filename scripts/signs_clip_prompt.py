"""Build separate wordless SIGNS clips (signs_1, signs_2, ...) from a Modoc script."""

from __future__ import annotations

import json
import re
from pathlib import Path

SIGNS_CLIP_SECONDS = 4


def signs_clip_id(index: int) -> str:
    return f"signs_{index}"


def is_signs_clip_id(clip_id: str) -> bool:
    return clip_id == "signs" or bool(re.match(r"^signs_\d+$", clip_id))


def clip_sort_key(clip_id: str) -> tuple:
    if clip_id == "hook":
        return (0, 0)
    if clip_id.startswith("body_"):
        num = clip_id.split("_", 1)[-1]
        return (1, int(num) if num.isdigit() else 0)
    if clip_id.startswith("signs_"):
        num = clip_id.split("_", 1)[-1]
        return (2, int(num) if num.isdigit() else 0)
    if clip_id == "signs":
        return (2, 0)
    if clip_id == "relief":
        return (3, 0)
    if clip_id == "cta":
        return (4, 0)
    return (99, 0)


def bullet_to_visual(line: str, *, child_age: str = "6-year-old") -> str:
    """Map a script warning line to one presentation visual (no text)."""
    low = line.lower()
    if "breath" in low:
        return (
            f"a {child_age} child sitting upright with visible rapid breathing, "
            f"chest rising and falling quickly"
        )
    if "urinat" in low or "diaper" in low or "pee" in low:
        return (
            f"a dry unused diaper beside a simple wall clock, suggesting no urination "
            f"for many hours"
        )
    if "tear" in low or "dry lip" in low or "crying" in low:
        return (
            f"a close-up of a {child_age} child's face with visibly dry cracked lips "
            f"and no tears on the cheeks"
        )
    if "belly" in low or "stomach" in low or "touched" in low or "pain" in low:
        return (
            f"a {child_age} child lying on their back with both hands on their belly, "
            f"wincing slightly as a parent's hand gently touches the stomach"
        )
    if "wake" in low or "letharg" in low or "rous" in low:
        return (
            f"a {child_age} child asleep on a pillow while a parent gently taps the "
            f"shoulder and the child does not wake"
        )
    return f"a simple health-warning visual suggesting: {line[:80]}"


def extract_child_age(script: str) -> str:
    match = re.search(r"(\d+)[\s-]*year[\s-]*old", script, re.I)
    if match:
        return f"{match.group(1)}-year-old"
    return "school-age"


def _split_sign_sentences(text: str) -> list[str]:
    """Split inline sign text into short bullet lines (one clip each)."""
    text = text.strip()
    if not text:
        return []
    parts = re.split(r"(?<=[.!?])\s+", text)
    bullets: list[str] = []
    for part in parts:
        part = part.strip().rstrip(".")
        if len(part) < 4:
            continue
        bullets.append(part)
    return bullets


def _inline_signs_from_line(line: str) -> list[str]:
    """When 'watch for' and sign list share one BODY line, split after the colon."""
    match = re.search(
        r"(?:watch for|warning signs?|serious signs?).+?:\s*(.+)$",
        line,
        re.I,
    )
    if not match:
        return []
    return _split_sign_sentences(match.group(1))


def extract_warning_bullets(script: str) -> list[str]:
    """Pull warning-sign lines from BODY only (after 'watch for', until RELIEF)."""
    lines = [ln.strip() for ln in script.splitlines() if ln.strip()]
    bullets: list[str] = []
    capturing = False
    stop_phrases = (
        "at home",
        "offer small",
        "try bananas",
        "ensure plenty",
        "if no improvement",
        "these mean immediate",
        "if you see these",
        "otherwise,",
        "otherwise ",
        "visit a doctor",
        "go to the emergency",
        "ask for a flu",
        "prompt evaluation",
    )
    for line in lines:
        if line.startswith("#"):
            continue
        upper = line.upper().rstrip(":")
        if upper in ("HOOK", "BODY", "RELIEF", "CTA") or upper.endswith(":") and upper.replace(":", "") in (
            "HOOK",
            "BODY",
            "RELIEF",
            "CTA",
        ):
            capturing = False
            continue
        if re.match(r"^\*\*.*\*\*$", line):
            if re.search(r"watch for|warning sign|serious sign", line, re.I):
                capturing = True
            continue
        if re.search(r"watch for|warning sign|serious sign", line, re.I):
            capturing = True
            bullets.extend(_inline_signs_from_line(line))
            continue
        if not capturing:
            continue
        low = line.lower()
        if any(low.startswith(p) for p in stop_phrases):
            break
        if line.endswith("?"):
            continue
        bullets.append(line)
    return bullets[:8]


def build_one_signs_clip(
    index: int, bullet: str, *, child_age: str
) -> dict:
    visual = bullet_to_visual(bullet, child_age=child_age)
    clip_id = signs_clip_id(index)
    label = f"SIGNS CLIP {index}"

    veo = (
        "Cinematic 4K. Single wordless presentation visual for a parent health video. "
        "NO text, NO words, NO letters, NO captions anywhere. "
        "Soft warm off-white background, one centered rounded card filling most of the frame, "
        "static camera, even bright lighting, tense-but-clear mood. "
        f"The card shows only this one realistic image: {visual}. "
        "Clean minimalist slide look, not graphic, not a medical diagram. "
        f"{SIGNS_CLIP_SECONDS} seconds."
    )

    detailed = (
        f"SUBJECT: One wordless presentation card (no text).\n"
        f"SETTING: Minimal slide, soft warm off-white background.\n"
        f"ACTION: Single card showing: {visual}.\n"
        f"Script line: {bullet}\n"
        "MOOD: Tense\n"
        "CAMERA: Static shot\n"
        "LIGHTING: Bright, even\n"
        "STYLE: Cinematic realistic. 4K. No text on screen."
    )

    return {
        "id": clip_id,
        "label": label,
        "detailed_prompt": detailed,
        "veo_prompt": veo,
        "duration_seconds": SIGNS_CLIP_SECONDS,
        "script_line": bullet,
    }


def build_signs_clips_list(bullets: list[str], *, child_age: str) -> list[dict]:
    if not bullets:
        return []
    return [
        build_one_signs_clip(i, bullet, child_age=child_age)
        for i, bullet in enumerate(bullets, start=1)
    ]


def format_signs_decision_lines(bullets: list[str], *, child_age: str) -> list[str]:
    lines = []
    for i, bullet in enumerate(bullets, start=1):
        visual = bullet_to_visual(bullet, child_age=child_age)
        lines.append(f"SIGNS CLIP {i}: {visual}")
    return lines


def merge_signs_clips_into_list(script: str, clips: list[dict]) -> list[dict]:
    """Replace any single 'signs' clip with signs_1..signs_N from the script."""
    bullets = extract_warning_bullets(script)
    other = [c for c in clips if not is_signs_clip_id(str(c.get("id", "")))]
    signs_clips = build_signs_clips_list(bullets, child_age=extract_child_age(script))
    merged = other + signs_clips
    merged.sort(key=lambda c: clip_sort_key(str(c["id"])))
    return merged


def update_signs_in_folder(clips_dir: Path, script_path: Path) -> list[str]:
    """Write signs_1..signs_N into clips.json; return clip ids."""
    script = script_path.read_text(encoding="utf-8")
    bullets = extract_warning_bullets(script)
    child_age = extract_child_age(script)
    signs_clips = build_signs_clips_list(bullets, child_age=child_age)

    clips_json = clips_dir / "clips.json"
    if clips_json.is_file():
        data = json.loads(clips_json.read_text(encoding="utf-8"))
        clips = [
            c
            for c in data.get("clips", [])
            if not is_signs_clip_id(str(c.get("id", "")))
        ]
    else:
        data = {}
        clips = []

    clips.extend(signs_clips)
    clips.sort(key=lambda c: clip_sort_key(str(c["id"])))
    data["clips"] = clips
    clips_json.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    decisions_path = clips_dir / "clip_decisions.txt"
    if decisions_path.is_file():
        text = decisions_path.read_text(encoding="utf-8")
        text = re.sub(
            r"^SIGNS CLIP(?: \d+)?:.*\n", "", text, flags=re.MULTILINE | re.IGNORECASE
        )
        text = re.sub(r"^signs_\d+.*\n", "", text, flags=re.MULTILINE | re.IGNORECASE)
        insert_lines = format_signs_decision_lines(bullets, child_age=child_age)
        if "RELIEF CLIP:" in text:
            text = text.replace(
                "RELIEF CLIP:",
                "\n".join(insert_lines) + "\nRELIEF CLIP:",
                1,
            )
        else:
            text = text.rstrip() + "\n" + "\n".join(insert_lines) + "\n"
        decisions_path.write_text(text, encoding="utf-8")

    print(f"Updated {clips_json} with {len(signs_clips)} signs clip(s)")
    for clip in signs_clips:
        print(f"  {clip['id']}: {clip.get('script_line', '')[:60]}")
    return [c["id"] for c in signs_clips]


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 3:
        print("Usage: python scripts/signs_clip_prompt.py <clips_dir> <script.txt>")
        sys.exit(1)
    ids = update_signs_in_folder(Path(sys.argv[1]), Path(sys.argv[2]))
    print("Clip ids:", ", ".join(ids))
