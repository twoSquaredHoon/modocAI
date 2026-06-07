"""Helpful messages when output paths are missing."""

from __future__ import annotations

from pathlib import Path

from gemini_util import PROJECT_ROOT

SCRIPTS_DIR = PROJECT_ROOT / "output" / "scripts"
CLIPS_DIR = PROJECT_ROOT / "output" / "clips"


def _recent_paths(folder: Path, pattern: str, *, limit: int = 5) -> list[Path]:
    if not folder.is_dir():
        return []
    items = sorted(folder.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return items[:limit]


def format_script_not_found(requested: Path) -> str:
    lines = [
        f"Script not found: {requested}",
        "",
        "WORKFLOW.md uses placeholders — replace with your real file, e.g.:",
        "  output/scripts/q-my-6-year-old-has-gastroenteritis-but-is-getting-more-leth-20260527.txt",
        "",
    ]
    recent = _recent_paths(SCRIPTS_DIR, "*.txt")
    if recent:
        lines.append("Recent scripts in output/scripts/:")
        for path in recent:
            lines.append(f"  {path.relative_to(PROJECT_ROOT)}")
    else:
        lines.append("No scripts yet. Create one with:")
        lines.append('  ./blog-to-script.sh "https://your-blog-url"')
    lines.append("")
    lines.append("List files:  ls output/scripts/")
    return "\n".join(lines)


def format_clips_dir_not_found(requested: Path) -> str:
    lines = [
        f"Clips folder not found: {requested}",
        "",
        "Use the folder created by script-to-clips (not the placeholder name), e.g.:",
        "  output/clips/q-my-6-year-old-has-gastroenteritis-but-is-getting-20260527-2257",
        "",
    ]
    recent = _recent_paths(CLIPS_DIR, "*")
    recent = [p for p in recent if p.is_dir()]
    if recent:
        lines.append("Recent clips runs in output/clips/:")
        for path in recent:
            lines.append(f"  {path.relative_to(PROJECT_ROOT)}")
    else:
        lines.append("Create prompts first:")
        lines.append(
            "  ./script-to-clips.sh output/scripts/YOUR_SCRIPT.txt --prompts-only"
        )
    lines.append("")
    lines.append("List folders:  ls output/clips/")
    return "\n".join(lines)
