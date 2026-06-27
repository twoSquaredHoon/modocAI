#!/usr/bin/env python3
"""Compare a generated script against the original blog article via Gemini."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from blog_to_script import fetch_blog_text
from gemini_util import get_client
from language_config import get_language, normalize_language
from prompts import SCRIPT_VERIFICATION_PROMPT
from script_lines import format_script_for_review, load_script_body, parse_script_lines
from script_to_clips import extract_response_text, run_gemini_text

DEFAULT_MODEL = "gemini-2.5-flash"


def parse_verification_json(raw: str) -> dict:
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    data = json.loads(text)
    if data.get("verdict") not in ("pass", "review", "fail"):
        raise ValueError("JSON must include verdict: pass, review, or fail")
    return data


def format_verification_report(data: dict, *, source_url: str, language: str) -> str:
    verdict = str(data.get("verdict", "review")).upper()
    lines = [
        f"# Script vs article verification",
        f"",
        f"**Verdict:** {verdict}",
        f"**Source:** {source_url}",
        f"**Language:** {language}",
        f"**Checked:** {data.get('verified_at', '')}",
        f"",
        f"## Summary",
        str(data.get("summary", "")),
        f"",
    ]

    supported = data.get("supported_claims") or []
    if supported:
        lines.append("## Supported by article")
        for item in supported:
            lines.append(f"- {item}")
        lines.append("")

    invented = data.get("unsupported_or_invented") or []
    if invented:
        lines.append("## Unsupported or invented in script")
        for item in invented:
            sev = item.get("severity", "?")
            line_id = item.get("line_id")
            prefix = f"`{line_id}` " if line_id else ""
            lines.append(f"- **[{sev}]** {prefix}{item.get('claim', '')}")
            if item.get("note"):
                lines.append(f"  - {item['note']}")
        lines.append("")

    omissions = data.get("important_omissions") or []
    if omissions:
        lines.append("## Important omissions from script")
        for item in omissions:
            sev = item.get("severity", "?")
            lines.append(f"- **[{sev}]** {item.get('fact', '')}")
            if item.get("note"):
                lines.append(f"  - {item['note']}")
        lines.append("")

    age = data.get("age_consistency") or {}
    lines.append("## Age consistency")
    ok = age.get("ok", True)
    lines.append(f"- OK: {'yes' if ok else 'no'}")
    if age.get("article_age"):
        lines.append(f"- Article: {age['article_age']}")
    if age.get("script_age"):
        lines.append(f"- Script: {age['script_age']}")
    if age.get("note"):
        lines.append(f"- Note: {age['note']}")
    lines.append("")

    line_checks = data.get("script_line_checks") or []
    if line_checks:
        lines.append("## Script line checks")
        for item in line_checks:
            line_id = item.get("line_id", "?")
            status = str(item.get("status", "?")).upper()
            lines.append(f"- **[{status}]** `{line_id}`")
            for issue in item.get("issues") or []:
                kind = issue.get("kind", "issue")
                sev = issue.get("severity", "?")
                note = issue.get("note", "")
                lines.append(f"  - [{sev}] {kind}: {note}")
        lines.append("")

    fixes = data.get("recommended_fixes") or []
    if fixes:
        lines.append("## Recommended fixes")
        for fix in fixes:
            lines.append(f"- {fix}")
        lines.append("")

    return "\n".join(lines)


def compare_script_to_article(
    *,
    script_text: str,
    numbered_script: str,
    article_text: str,
    source_url: str,
    language: str,
    model: str,
) -> dict:
    lang = get_language(language)
    user = f"""{SCRIPT_VERIFICATION_PROMPT}

Blog URL: {source_url}
Script language: {lang.label}

ORIGINAL BLOG ARTICLE:
---
{article_text}
---

VIDEO SCRIPT (each line has a line_id tag — use these in script_line_checks):
---
{numbered_script}
---
"""
    client = get_client()
    raw = run_gemini_text(
        client,
        model=model,
        user=user,
        system=(
            "You are a strict medical fact-checker for parent-facing video scripts. "
            "Be lenient on HOOK lines (attention-grabbing tone is fine); be strict on BODY, RELIEF, and CTA. "
            "Output valid JSON only."
        ),
        json_mode=True,
        max_retries=3,
    )
    data = parse_verification_json(raw)
    data["verified_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    data["source_url"] = source_url
    data["language"] = language
    return data


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare a video script to the original blog article (Gemini)."
    )
    parser.add_argument("script", type=Path, help="Path to script.txt")
    parser.add_argument("--url", required=True, help="Original blog URL")
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Project folder for script_verification.json/.txt and source_article.txt",
    )
    parser.add_argument(
        "--language",
        default=None,
        choices=["en", "ko", "es"],
        help="Script language label for the reviewer",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Gemini model (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--use-cached-article",
        action="store_true",
        help="Use source_article.txt in output-dir instead of re-fetching",
    )
    args = parser.parse_args()

    script_path = args.script.expanduser().resolve()
    if not script_path.is_file():
        print(f"Script not found: {script_path}", file=sys.stderr)
        sys.exit(1)

    url = args.url.strip()
    if not url.startswith(("http://", "https://")):
        print("URL must start with http:// or https://", file=sys.stderr)
        sys.exit(1)

    out_dir = args.output_dir.expanduser().resolve() if args.output_dir else script_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    article_cache = out_dir / "source_article.txt"
    language = normalize_language(args.language)

    try:
        script_text = load_script_body(script_path)
        numbered_script = format_script_for_review(script_path)
        if args.use_cached_article and article_cache.is_file():
            print(f"Using cached article: {article_cache}")
            article_text = article_cache.read_text(encoding="utf-8").strip()
        else:
            article_text = fetch_blog_text(url)
            article_cache.write_text(article_text + "\n", encoding="utf-8")
            print(f"  Cached article → {article_cache}")

        print(f"Comparing script to article with {args.model}...")
        report = compare_script_to_article(
            script_text=script_text,
            numbered_script=numbered_script,
            article_text=article_text,
            source_url=url,
            language=language,
            model=args.model,
        )
    except Exception as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)

    json_path = out_dir / "script_verification.json"
    txt_path = out_dir / "script_verification.txt"
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    txt_path.write_text(
        format_verification_report(report, source_url=url, language=language),
        encoding="utf-8",
    )

    print(f"\nVerdict: {report['verdict'].upper()}")
    print(report.get("summary", ""))
    print(f"\nSaved → {json_path}")
    print(f"Saved → {txt_path}")


if __name__ == "__main__":
    main()
