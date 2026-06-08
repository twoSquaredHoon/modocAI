"""Build EXPLAIN clips (explain_1, explain_2, ...) for home-care / dosing beats in BODY."""

from __future__ import annotations

import json
import re
from pathlib import Path

from signs_clip_prompt import clip_sort_key, is_signs_clip_id
from visual_cast import VisualCast, get_visual_cast, language_from_script_header

EXPLAIN_CLIP_SECONDS = 4

SIGNS_INTRO_RE = re.compile(
    r"(?:watch for|warning signs?|serious signs?|danger signs?|"
    r"위험\s*신호|위험신호|이런\s*위험|"
    r"señales?\s+de\s+alarma|signos?\s+de\s+alarma|"
    r"다만.*(?:신호|병원|위험))",
    re.I,
)

EXPLAIN_LINE_RE = re.compile(
    r"(?:"
    r"\b\d+\s*(?:ml|mg|mL)\b|"
    r"(?:every|each|every)\s+\d+\s*(?:hour|hr|h)\b|"
    r"\d+\s*(?:hour|hr|h|시간)\s*(?:interval|간격|every)?|"
    r"(?:acetaminophen|ibuprofen|tylenol|motrin|advil|"
    r"아세트|이부프로|해열|교차\s*복용|복용|용량)|"
    r"(?:alternate|alternating|rotate|switch\s+to|교차)|"
    r"(?:dose|dosing|dosage|administer|give\s+(?:the|a)?)|"
    r"(?:fever\s+reducer|antipyretic)|"
    r"(?:ml\s*용량|간격으로)|"
    r"(?:cada\s+\d+\s*horas|acetaminof|ibuprofeno|dosis|administrar)"
    r")",
    re.I,
)


def explain_clip_id(index: int) -> str:
    return f"explain_{index}"


def is_explain_clip_id(clip_id: str) -> bool:
    return bool(re.match(r"^explain_\d+$", clip_id))


def _body_lines(script: str) -> list[str]:
    lines = script.splitlines()
    in_body = False
    body: list[str] = []
    for raw in lines:
        if raw.startswith("#"):
            continue
        stripped = raw.strip()
        if not stripped:
            continue
        upper = stripped.upper().rstrip(":")
        if upper in ("HOOK", "BODY", "RELIEF", "CTA"):
            in_body = upper == "BODY"
            continue
        if in_body:
            body.append(stripped)
    return body


def _is_signs_intro(line: str) -> bool:
    return bool(SIGNS_INTRO_RE.search(line))


def _is_explain_line(line: str) -> bool:
    if _is_signs_intro(line):
        return False
    return bool(EXPLAIN_LINE_RE.search(line))


def _split_sentences(text: str) -> list[str]:
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p.strip().rstrip(".") for p in parts if len(p.strip()) >= 4]


def _text_before_signs_intro(line: str) -> str:
    match = SIGNS_INTRO_RE.search(line)
    if match:
        return line[: match.start()].strip()
    return line


def extract_explain_bullets(script: str) -> list[str]:
    """BODY lines about dosing / home care before the warning-signs block."""
    body = _body_lines(script)
    bullets: list[str] = []
    for line in body:
        prefix = _text_before_signs_intro(line)
        for sent in _split_sentences(prefix):
            if _is_explain_line(sent):
                bullets.append(sent)
        if _is_signs_intro(line):
            break
    return bullets[:6]


def explain_line_to_visual(line: str, *, cast: VisualCast) -> str:
    """Cinematic instructional scene (wordless — no readable labels)."""
    low = line.lower()
    parent = cast.parent
    child = cast.child
    infant = cast.age.is_infant

    if re.search(r"아세트|acetaminophen|tylenol|해열제", low):
        if infant:
            return (
                f"{parent} carefully giving liquid medicine to {child} from an oral "
                f"syringe with a small measured amount; a simple wall clock in soft "
                f"focus suggests timed intervals; warm calm nursery lighting; no readable text"
            )
        return (
            f"{parent} giving a measured dose of liquid fever medicine to {child} "
            f"with an oral syringe; clock suggesting regular time intervals; no readable labels"
        )

    if re.search(r"이부프로|ibuprofen|motrin|advil|교차", low):
        return (
            f"{parent} looking concerned while checking {child} who appears fussy and warm; "
            f"parent reaches for a second fever medicine bottle on a shelf — calm instructional "
            f"moment, not emergency panic; no readable text on bottles"
        )

    if re.search(r"\d+\s*(?:ml|mL|mg)|용량", low):
        if infant:
            return (
                f"{parent} preparing a small oral syringe dose beside {child} on the "
                f"changing table; warm neutral home setting; no readable numbers or labels"
            )
        return (
            f"{parent} preparing an oral syringe with liquid medicine for {child}; "
            f"no readable text on packaging"
        )

    if re.search(r"(?:hour|시간|간격|cada\s+\d+\s*horas)", low):
        return (
            f"{parent} giving medicine to {child} while a wall clock is visible in the "
            f"background suggesting regular timing; calm instructional mood"
        )

    return (
        f"{parent} providing home fever care to {child} as described in the script line; "
        f"warm calm instructional scene in a nursery; no on-screen text"
    )


def build_one_explain_clip(index: int, bullet: str, *, cast: VisualCast) -> dict:
    visual = explain_line_to_visual(bullet, cast=cast)
    clip_id = explain_clip_id(index)
    label = f"EXPLAIN CLIP {index}"

    veo = (
        f"Cinematic 4K realistic footage. Warm calm instructional parenting health scene. "
        f"NO text, NO words, NO letters, NO captions anywhere on screen. "
        f"{visual}. "
        f"Cast consistency — child: {cast.child} Parent: {cast.parent}. "
        f"Natural colors, gentle handheld or static shot, soft daylight. "
        f"{EXPLAIN_CLIP_SECONDS} seconds."
    )

    detailed = (
        f"SUBJECT: {cast.child}; {cast.parent}.\n"
        f"SETTING: {cast.setting}\n"
        f"ACTION: {visual}\n"
        f"Script line: {bullet}\n"
        "MOOD: Warm\n"
        "CAMERA: Gentle handheld or static\n"
        "LIGHTING: Soft natural daylight\n"
        "STYLE: Cinematic realistic. 4K. No text on screen."
    )

    return {
        "id": clip_id,
        "label": label,
        "detailed_prompt": detailed,
        "veo_prompt": veo,
        "duration_seconds": EXPLAIN_CLIP_SECONDS,
        "script_line": bullet,
    }


def build_explain_clips_list(bullets: list[str], *, cast: VisualCast) -> list[dict]:
    if not bullets:
        return []
    return [
        build_one_explain_clip(i, bullet, cast=cast)
        for i, bullet in enumerate(bullets, start=1)
    ]


def format_explain_decision_lines(bullets: list[str], *, cast: VisualCast) -> list[str]:
    lines = []
    for i, bullet in enumerate(bullets, start=1):
        visual = explain_line_to_visual(bullet, cast=cast)
        lines.append(f"EXPLAIN CLIP {i}: {visual}")
    return lines


def merge_explain_clips_into_list(
    script: str, clips: list[dict], *, language: str | None = None
) -> list[dict]:
    """Replace explain clips with explain_1..explain_N parsed from the script."""
    bullets = extract_explain_bullets(script)
    cast = get_visual_cast(language or language_from_script_header(script) or "en", script)
    other = [
        c
        for c in clips
        if not is_explain_clip_id(str(c.get("id", "")))
    ]
    explain_clips = build_explain_clips_list(bullets, cast=cast)
    merged = other + explain_clips
    merged.sort(key=lambda c: clip_sort_key(str(c["id"])))
    return merged


def update_explain_in_folder(
    clips_dir: Path, script_path: Path, *, language: str | None = None
) -> list[str]:
    from derived_clips import sync_derived_in_folder

    explain_ids, _ = sync_derived_in_folder(
        clips_dir, script_path, language=language
    )
    return explain_ids


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Refresh explain clips in a project folder.")
    parser.add_argument("clips_dir", type=Path)
    parser.add_argument("script", type=Path)
    parser.add_argument(
        "--language",
        choices=["en", "ko", "es"],
        default=None,
    )
    args = parser.parse_args()
    ids = update_explain_in_folder(args.clips_dir, args.script, language=args.language)
    print("Clip ids:", ", ".join(ids) if ids else "(none)")
