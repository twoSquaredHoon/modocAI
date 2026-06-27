"""Parse and edit Modoc script.txt spoken lines (matches Modoc Studio ScriptParser)."""

from __future__ import annotations

from pathlib import Path

SECTION_HEADERS = {"HOOK", "BODY", "RELIEF", "CTA"}


def iter_spoken_line_records(path: Path):
    """Yield (file_line_index, line_id, section, text) for each spoken line."""
    section = "OTHER"
    section_index = 0
    lines = path.read_text(encoding="utf-8").splitlines()

    for index, raw in enumerate(lines):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        normalized = line.upper().strip(": ")
        if normalized in SECTION_HEADERS:
            section = normalized
            section_index = 0
            continue
        section_index += 1
        line_id = f"{section}-{section_index}"
        yield index, line_id, section, line


def parse_script_lines(path: Path) -> list[tuple[str, str, str]]:
    """Return (line_id, section, text)."""
    return [(line_id, section, text) for _, line_id, section, text in iter_spoken_line_records(path)]


def load_script_body(path: Path) -> str:
    parsed = parse_script_lines(path)
    if not parsed:
        raise ValueError(f"No script content in {path}")
    return "\n".join(text for _, _, text in parsed)


def format_script_for_review(path: Path) -> str:
    parsed = parse_script_lines(path)
    if not parsed:
        raise ValueError(f"No script content in {path}")
    return "\n".join(f"[{line_id}] {text}" for line_id, _, text in parsed)


def find_spoken_line(path: Path, line_id: str) -> tuple[int, str, str]:
    for index, lid, section, text in iter_spoken_line_records(path):
        if lid == line_id:
            return index, section, text
    raise ValueError(f"Line not found in script: {line_id}")


def remove_script_line(path: Path, line_id: str) -> str:
    """Remove a spoken line; return the removed text."""
    index, _, text = find_spoken_line(path, line_id)
    lines = path.read_text(encoding="utf-8").splitlines()
    del lines[index]
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return text


def replace_script_line(path: Path, line_id: str, new_text: str) -> str:
    """Replace a spoken line; return the previous text."""
    new_text = new_text.strip()
    if not new_text:
        raise ValueError("Replacement line cannot be empty")
    index, _, old = find_spoken_line(path, line_id)
    lines = path.read_text(encoding="utf-8").splitlines()
    lines[index] = new_text
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return old
