#!/usr/bin/env python3
"""Fetch FeverCoach blog posts published recently; skip already-processed articles."""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urljoin, urlparse

from trafilatura import fetch_url

from article_registry import migrate_from_projects, normalize_url, processed_urls
from gemini_util import PROJECT_ROOT

BLOG_INDEXES = {
    "en": "https://www.fevercoach.us/blog",
    "ko": "https://www.fevercoach.us/ko/blog",
}

SKIP_SLUG_FRAGMENTS = (
    "the-science-behind-fevercoach",
    "trusted-sources-for-reliable-fever-management",
)

DEFAULT_OUT = PROJECT_ROOT / "urls.txt"

_DATE_PUBLISHED_RE = re.compile(
    r'"datePublished"\s*:\s*"([^"]+)"',
    re.IGNORECASE,
)


def normalize_post_url(href: str, *, language: str) -> str | None:
    if href.startswith("/"):
        href = urljoin("https://www.fevercoach.us", href)
    parsed = urlparse(href)
    if parsed.netloc and "fevercoach.us" not in parsed.netloc:
        return None
    path = parsed.path.rstrip("/")
    if language == "ko":
        if not path.startswith("/ko/post/"):
            return None
    else:
        if not path.startswith("/post/") or path.startswith("/ko/post/"):
            return None
    slug = path.split("/post/", 1)[-1].lower()
    if any(skip in slug for skip in SKIP_SLUG_FRAGMENTS):
        return None
    return f"https://www.fevercoach.us{path}"


def extract_post_urls_from_index(html: str, *, language: str) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for match in re.finditer(r"""href=["']([^"']+)["']""", html):
        url = normalize_post_url(match.group(1).split("#")[0].split("?")[0], language=language)
        if not url or url in seen:
            continue
        seen.add(url)
        ordered.append(url)
    return ordered


def parse_published_at(raw: str) -> datetime | None:
    text = raw.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def fetch_published_at(post_url: str) -> datetime | None:
    print(f"  date lookup: {post_url}")
    html = fetch_url(post_url)
    if not html:
        return None
    match = _DATE_PUBLISHED_RE.search(html)
    if not match:
        return None
    return parse_published_at(match.group(1))


def fetch_recent_posts(
    index_url: str,
    *,
    language: str,
    since: datetime,
    max_pages: int = 20,
) -> list[tuple[str, datetime]]:
    """Return (url, published_at) for posts on the index newer than `since`."""
    results: list[tuple[str, datetime]] = []
    seen: set[str] = set()
    cutoff = since.astimezone(timezone.utc)

    for page in range(1, max_pages + 1):
        page_url = index_url if page == 1 else f"{index_url.rstrip('/')}/page/{page}"
        print(f"Fetching index: {page_url}")
        html = fetch_url(page_url)
        if not html:
            raise RuntimeError(f"Could not download index page: {page_url}")

        urls = extract_post_urls_from_index(html, language=language)
        if not urls and page > 1:
            break

        page_all_older = True
        for url in urls:
            if url in seen:
                continue
            seen.add(url)
            published = fetch_published_at(url)
            if published is None:
                print(f"    ? could not read date — skipping: {url}")
                continue
            if published >= cutoff:
                page_all_older = False
                results.append((url, published))
                print(f"    + {published.isoformat(timespec='seconds')}  {url}")
            else:
                print(f"    - too old ({published.date()}): {url}")

        if page_all_older:
            break

    results.sort(key=lambda item: item[1], reverse=True)
    return results


def fetch_latest_posts(
    index_url: str,
    *,
    language: str,
    limit: int,
    max_pages: int = 3,
) -> list[tuple[str, datetime]]:
    """Return the N newest posts by publish date (ignores time window)."""
    collected: list[tuple[str, datetime]] = []
    seen: set[str] = set()

    for page in range(1, max_pages + 1):
        page_url = index_url if page == 1 else f"{index_url.rstrip('/')}/page/{page}"
        print(f"Fetching index: {page_url}")
        html = fetch_url(page_url)
        if not html:
            raise RuntimeError(f"Could not download index page: {page_url}")

        urls = extract_post_urls_from_index(html, language=language)
        if not urls and page > 1:
            break

        for url in urls:
            if url in seen:
                continue
            seen.add(url)
            published = fetch_published_at(url)
            if published is None:
                print(f"    ? could not read date — skipping: {url}")
                continue
            collected.append((url, published))
            print(f"    · {published.isoformat(timespec='seconds')}  {url}")

        if len(collected) >= limit:
            break

    collected.sort(key=lambda item: item[1], reverse=True)
    return collected[:limit]


def write_urls_file(
    path: Path,
    entries: list[tuple[str, str, datetime | None]],
) -> None:
    lines = [
        f"# Generated {datetime.now(timezone.utc).isoformat(timespec='seconds')}",
        f"# {len(entries)} URL(s) for batch-run.sh",
        "",
    ]
    for url, language, published in entries:
        suffix = f"  # published {published.isoformat(timespec='seconds')}" if published else ""
        lines.append(f"{url},{language}{suffix}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch blog posts published recently; skip articles already in the registry."
    )
    parser.add_argument(
        "--since-hours",
        type=float,
        default=24.0,
        help="Include posts published in the last N hours (default: 24; ignored if --latest is set)",
    )
    parser.add_argument(
        "--latest",
        type=int,
        default=0,
        metavar="N",
        help="Instead of time window: take the N newest posts per index by publish date",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Write urls.txt-style output (default: {DEFAULT_OUT})",
    )
    parser.add_argument(
        "--max-per-index",
        type=int,
        default=0,
        help="Optional cap per language after filtering (0 = no cap)",
    )
    parser.add_argument(
        "--en-only",
        action="store_true",
    )
    parser.add_argument(
        "--ko-only",
        action="store_true",
    )
    parser.add_argument(
        "--include-processed",
        action="store_true",
        help="Do not skip URLs already in processed_articles.json",
    )
    args = parser.parse_args()

    imported = migrate_from_projects()
    if imported:
        print(f"Imported {imported} existing project(s) into processed_articles.json")

    indexes: list[tuple[str, str]] = []
    if not args.ko_only:
        indexes.append(("en", BLOG_INDEXES["en"]))
    if not args.en_only:
        indexes.append(("ko", BLOG_INDEXES["ko"]))
    if not indexes:
        print("Nothing to fetch.", file=sys.stderr)
        sys.exit(1)

    since = datetime.now(timezone.utc) - timedelta(hours=args.since_hours)
    if args.latest > 0:
        print(f"Looking for the {args.latest} newest post(s) per index (by publish date)")
    else:
        print(f"Looking for posts published since {since.isoformat(timespec='seconds')}")

    done = processed_urls() if not args.include_processed else set()
    entries: list[tuple[str, str, datetime | None]] = []

    for language, index_url in indexes:
        print(f"\n{language.upper()} index")
        if args.latest > 0:
            posts = fetch_latest_posts(
                index_url, language=language, limit=args.latest
            )
        else:
            posts = fetch_recent_posts(index_url, language=language, since=since)
            if args.max_per_index > 0:
                posts = posts[: args.max_per_index]
        print(f"  {len(posts)} post(s) selected")
        for url, published in posts:
            key = normalize_url(url)
            if key in done:
                print(f"    skip (already processed): {url}")
                continue
            entries.append((url, language, published))

    if not entries:
        print("\nNo new URLs to write.", file=sys.stderr)
        sys.exit(0)

    out = args.output.expanduser().resolve()
    write_urls_file(out, entries)
    print(f"\nWrote {len(entries)} URL(s) → {out}")
    print("Next: ./batch-run.sh urls.txt")


if __name__ == "__main__":
    main()
