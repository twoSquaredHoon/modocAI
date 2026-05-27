#!/usr/bin/env python3
"""Fetch a blog post URL and generate a spoken video script via Gemini."""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

import trafilatura
from google.genai import types

from gemini_util import PROJECT_ROOT, get_client
from prompts import SCRIPT_RULES

DEFAULT_MODEL = "gemini-2.5-flash"
OUTPUT_DIR = PROJECT_ROOT / "output" / "scripts"


def fetch_blog_text(url: str) -> str:
    print(f"Fetching: {url}")
    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        raise RuntimeError("Could not download the page. Check the URL and try again.")

    text = trafilatura.extract(
        downloaded,
        include_comments=False,
        include_tables=False,
        favor_precision=True,
    )
    if not text or len(text.strip()) < 200:
        raise RuntimeError(
            "Could not extract enough article text from that page. "
            "The site may block bots or use a layout trafilatura cannot read."
        )
    print(f"  Extracted {len(text)} characters of article text.")
    return text.strip()


def slug_from_url(url: str) -> str:
    path = urlparse(url).path.strip("/")
    slug = path.split("/")[-1] if path else "blog-post"
    slug = re.sub(r"[^\w\-]+", "-", slug.lower()).strip("-")
    return slug[:60] or "blog-post"


def generate_script(blog_text: str, *, model: str, source_url: str) -> str:
    client = get_client()
    print(f"Writing script with {model}...")

    user_message = f"""Blog URL: {source_url}

Blog article text:
---
{blog_text}
---

{SCRIPT_RULES}
"""

    response = client.models.generate_content(
        model=model,
        contents=user_message,
        config=types.GenerateContentConfig(
            temperature=0.4,
            system_instruction=(
                "You turn parenting blog posts into short spoken video scripts. "
                "Medical accuracy is mandatory; never add claims not in the source."
            ),
        ),
    )
    script = (response.text or "").strip()
    if not script:
        raise RuntimeError("Gemini returned an empty script.")
    return script


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Read a blog URL and generate a short-form video script."
    )
    parser.add_argument("url", help="Blog post URL")
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Gemini model (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Save script to this file (default: output/scripts/<slug>-<date>.txt)",
    )
    parser.add_argument(
        "--print-only",
        action="store_true",
        help="Print script to terminal only; do not save a file.",
    )
    args = parser.parse_args()

    url = args.url.strip()
    if not url.startswith(("http://", "https://")):
        print("URL must start with http:// or https://", file=sys.stderr)
        sys.exit(1)

    try:
        blog_text = fetch_blog_text(url)
        script = generate_script(blog_text, model=args.model, source_url=url)
    except Exception as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)

    print("\n" + "=" * 40 + "\n")
    print(script)

    if args.print_only:
        return

    out_path = args.output
    if out_path is None:
        stamp = datetime.now().strftime("%Y%m%d")
        out_path = OUTPUT_DIR / f"{slug_from_url(url)}-{stamp}.txt"

    out_path.parent.mkdir(parents=True, exist_ok=True)
    header = f"# Source: {url}\n# Generated: {datetime.now().isoformat(timespec='seconds')}\n\n"
    out_path.write_text(header + script + "\n", encoding="utf-8")
    print("\n" + "=" * 40)
    print(f"Saved to {out_path}")


if __name__ == "__main__":
    main()
