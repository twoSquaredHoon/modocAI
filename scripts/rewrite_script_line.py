#!/usr/bin/env python3
"""Rewrite one script line using Gemini and the original article."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from gemini_util import get_client
from language_config import get_language, normalize_language
from prompts import SCRIPT_LINE_REWRITE_PROMPT
from script_lines import find_spoken_line, replace_script_line
from script_to_clips import run_gemini_text

DEFAULT_MODEL = "gemini-2.5-flash"


def load_line_issues(verification_path: Path, line_id: str) -> list[dict]:
    if not verification_path.is_file():
        return []
    data = json.loads(verification_path.read_text(encoding="utf-8"))
    issues: list[dict] = []
    for check in data.get("script_line_checks") or []:
        if check.get("line_id") == line_id:
            issues.extend(check.get("issues") or [])
    for item in data.get("unsupported_or_invented") or []:
        if item.get("line_id") == line_id:
            issues.append(
                {
                    "kind": "unsupported",
                    "severity": item.get("severity", "medium"),
                    "note": item.get("note") or item.get("claim", ""),
                }
            )
    return issues


def rewrite_line(
    *,
    line_text: str,
    line_id: str,
    section: str,
    article_text: str,
    issues: list[dict],
    language: str,
    model: str,
) -> str:
    lang = get_language(language)
    issue_block = ""
    if issues:
        lines = []
        for issue in issues:
            kind = issue.get("kind", "issue")
            sev = issue.get("severity", "?")
            note = issue.get("note", "")
            lines.append(f"- [{sev}] {kind}: {note}")
        issue_block = "PROBLEMS TO FIX:\n" + "\n".join(lines) + "\n\n"

    user = f"""{SCRIPT_LINE_REWRITE_PROMPT}

Script language: {lang.label}
Line id: {line_id}
Section: {section}

{issue_block}ORIGINAL LINE:
{line_text}

ORIGINAL BLOG ARTICLE:
---
{article_text}
---
"""
    client = get_client()
    is_hook = section.upper() == "HOOK"
    system = (
        "You rewrite one spoken script line. "
        + (
            "HOOK: keep it punchy and attention-grabbing; only fix false medical claims. "
            if is_hook
            else "BODY/RELIEF/CTA: must be medically accurate per the article. "
        )
        + "Output only the new line text, nothing else."
    )
    raw = run_gemini_text(
        client,
        model=model,
        user=user,
        system=system,
        max_retries=3,
    )
    new_line = raw.strip().strip('"').strip("'")
    if not new_line or "\n" in new_line:
        raise ValueError("Gemini did not return a single valid replacement line")
    return new_line


def main() -> None:
    parser = argparse.ArgumentParser(description="Rewrite one script line via Gemini.")
    parser.add_argument("script", type=Path, help="Path to script.txt")
    parser.add_argument("--line-id", required=True, help="Line id e.g. BODY-3")
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Project folder (source_article.txt, script_verification.json)",
    )
    parser.add_argument("--language", default=None, choices=["en", "ko", "es"])
    parser.add_argument("--model", default=DEFAULT_MODEL)
    args = parser.parse_args()

    script_path = args.script.expanduser().resolve()
    if not script_path.is_file():
        print(f"Script not found: {script_path}", file=sys.stderr)
        sys.exit(1)

    out_dir = args.output_dir.expanduser().resolve() if args.output_dir else script_path.parent
    article_path = out_dir / "source_article.txt"
    if not article_path.is_file():
        print(f"Missing cached article: {article_path}", file=sys.stderr)
        sys.exit(1)

    line_id = args.line_id.strip()
    language = normalize_language(args.language)
    verification_path = out_dir / "script_verification.json"

    try:
        file_index, section, line_text = find_spoken_line(script_path, line_id)
        _ = file_index
        article_text = article_path.read_text(encoding="utf-8").strip()
        issues = load_line_issues(verification_path, line_id)

        print(f"Rewriting {line_id} with {args.model}...")
        new_line = rewrite_line(
            line_text=line_text,
            line_id=line_id,
            section=section,
            article_text=article_text,
            issues=issues,
            language=language,
            model=args.model,
        )
        old_line = replace_script_line(script_path, line_id, new_line)
    except Exception as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)

    result_path = out_dir / ".last_script_line_edit.json"
    result_path.write_text(
        json.dumps(
            {
                "action": "rewrite",
                "line_id": line_id,
                "old_line": old_line,
                "new_line": new_line,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"\nOLD: {old_line}")
    print(f"NEW: {new_line}")
    print(f"Updated → {script_path}")


if __name__ == "__main__":
    main()
