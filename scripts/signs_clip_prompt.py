"""Build separate wordless SIGNS clips (signs_1, signs_2, ...) from a Modoc script."""

from __future__ import annotations

import json
import re
from pathlib import Path

from visual_cast import VisualCast, get_visual_cast, language_from_script_header

SIGNS_CLIP_SECONDS = 4

SIGNS_INTRO_RE = re.compile(
    r"(?:watch for|warning signs?|serious signs?|danger signs?|"
    r"위험\s*신호|위험신호|이런\s*위험|"
    r"señales?\s+de\s+alarma|signos?\s+de\s+alarma|"
    r"다만.*(?:신호|병원|위험))",
    re.I,
)


def _is_signs_intro(line: str) -> bool:
    return bool(SIGNS_INTRO_RE.search(line))


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
    if clip_id.startswith("explain_"):
        num = clip_id.split("_", 1)[-1]
        return (2, int(num) if num.isdigit() else 0)
    if clip_id.startswith("signs_"):
        num = clip_id.split("_", 1)[-1]
        return (3, int(num) if num.isdigit() else 0)
    if clip_id == "signs":
        return (3, 0)
    if clip_id == "relief":
        return (4, 0)
    if clip_id == "cta":
        return (5, 0)
    return (99, 0)


def bullet_to_visual(line: str, *, child_description: str, cast: VisualCast) -> str:
    """Map a script warning line to one presentation visual (no text)."""
    low = line.lower()
    infant = cast.age.is_infant

    if "breath" in low:
        if infant:
            return (
                f"{child_description} lying in a crib on their back with visible rapid "
                f"belly breathing, chest rising and falling quickly"
            )
        return (
            f"{child_description} sitting upright with visible rapid breathing, "
            f"chest rising and falling quickly"
        )
    if "urinat" in low or "diaper" in low or "pee" in low:
        return (
            f"a dry unused diaper beside a simple wall clock, suggesting no urination "
            f"for many hours"
            + (
                f" ({child_description} nearby on changing table)"
                if infant
                else f" (same child from cast if shown nearby: {child_description})"
            )
        )
    if "tear" in low or "dry lip" in low or "crying" in low:
        if infant:
            return (
                f"close-up of {child_description} in parent's arms with visibly dry "
                f"cracked lips and no tears on the cheeks while fussing weakly"
            )
        return (
            f"close-up of {child_description} with visibly dry cracked lips "
            f"and no tears on the cheeks"
        )
    if "belly" in low or "stomach" in low or "touched" in low or "pain" in low:
        if infant:
            return (
                f"{child_description} lying on a changing table with knees bent, "
                f"wincing as a parent's hand gently touches the stomach"
            )
        return (
            f"{child_description} lying on their back with both hands on their belly, "
            f"wincing slightly as a parent's hand gently touches the stomach"
        )
    if "wake" in low or "letharg" in low or "rous" in low:
        if infant:
            return (
                f"{child_description} asleep in a crib while a parent gently strokes "
                f"the cheek and the baby does not wake or open eyes"
            )
        return (
            f"{child_description} asleep on a pillow while a parent gently taps the "
            f"shoulder and the child does not wake"
        )
    return f"a simple health-warning visual for {cast.age.label} suggesting: {line[:80]}"


def _resolve_cast(script: str, language: str | None) -> VisualCast:
    lang = language or language_from_script_header(script) or "en"
    return get_visual_cast(lang, script)


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
    """When signs intro and sign list share one BODY line, split after the colon."""
    patterns = [
        r"(?:watch for|warning signs?|serious signs?|danger signs?).+?:\s*(.+)$",
        r"(?:señales?\s+de\s+alarma|signos?\s+de\s+alarma).+?:\s*(.+)$",
        r"(?:estate\s+atento|presta\s+atencion|presta\s+atención).+?:\s*(.+)$",
        r"(?:위험\s*신호|위험신호|이런\s*위험).+?:\s*(.+)$",
        r"(?:다만.*?(?:신호|alarma)).+?:\s*(.+)$",
    ]
    for pattern in patterns:
        match = re.search(pattern, line, re.I)
        if match:
            return _split_sign_sentences(match.group(1))
    return []


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
            if _is_signs_intro(line):
                capturing = True
            continue
        if _is_signs_intro(line):
            capturing = True
            bullets.extend(_inline_signs_from_line(line))
            continue
        if re.search(r"watch for|warning sign|serious sign|señales? de alarma|signos? de alarma|"
                     r"estate atento|위험\s*신호|위험신호", line, re.I):
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
    index: int, bullet: str, *, cast: VisualCast
) -> dict:
    visual = bullet_to_visual(bullet, child_description=cast.child, cast=cast)
    clip_id = signs_clip_id(index)
    label = f"SIGNS CLIP {index}"

    veo = (
        "Cinematic 4K. Single wordless presentation visual for a parent health video. "
        "NO text, NO words, NO letters, NO captions anywhere. "
        "Soft warm off-white background, one centered rounded card filling most of the frame, "
        "static camera, even bright lighting, tense-but-clear mood. "
        f"The card shows only this one realistic image: {visual}. "
        f"Cast consistency: {cast.child} "
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


def build_signs_clips_list(bullets: list[str], *, cast: VisualCast) -> list[dict]:
    if not bullets:
        return []
    return [
        build_one_signs_clip(i, bullet, cast=cast)
        for i, bullet in enumerate(bullets, start=1)
    ]


def format_signs_decision_lines(bullets: list[str], *, cast: VisualCast) -> list[str]:
    lines = []
    for i, bullet in enumerate(bullets, start=1):
        visual = bullet_to_visual(bullet, child_description=cast.child, cast=cast)
        lines.append(f"SIGNS CLIP {i}: {visual}")
    return lines


def merge_signs_clips_into_list(
    script: str, clips: list[dict], *, language: str | None = None
) -> list[dict]:
    """Replace any single 'signs' clip with signs_1..signs_N from the script."""
    bullets = extract_warning_bullets(script)
    cast = _resolve_cast(script, language)
    other = [c for c in clips if not is_signs_clip_id(str(c.get("id", "")))]
    signs_clips = build_signs_clips_list(bullets, cast=cast)
    merged = other + signs_clips
    merged.sort(key=lambda c: clip_sort_key(str(c["id"])))
    return merged


def update_signs_in_folder(
    clips_dir: Path, script_path: Path, *, language: str | None = None
) -> list[str]:
    """Write signs_1..signs_N into clips.json; return clip ids."""
    from derived_clips import sync_derived_in_folder

    _, signs_ids = sync_derived_in_folder(
        clips_dir, script_path, language=language
    )
    return signs_ids


if __name__ == "__main__":
    import argparse
    import sys

    parser = argparse.ArgumentParser(description="Refresh signs clips in a project folder.")
    parser.add_argument("clips_dir", type=Path)
    parser.add_argument("script", type=Path)
    parser.add_argument(
        "--language",
        choices=["en", "ko", "es"],
        default=None,
        help="Cast ethnicity/market (default: from script header)",
    )
    args = parser.parse_args()
    ids = update_signs_in_folder(args.clips_dir, args.script, language=args.language)
    print("Clip ids:", ", ".join(ids))
