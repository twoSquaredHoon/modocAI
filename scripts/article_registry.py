#!/usr/bin/env python3
"""Persistent registry of blog articles we already pipeline-processed."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from gemini_util import PROJECT_ROOT

REGISTRY_PATH = PROJECT_ROOT / "output" / "processed_articles.json"
PROJECTS_DIR = PROJECT_ROOT / "output" / "projects"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def normalize_url(url: str) -> str:
    return url.strip().rstrip("/")


def load_registry() -> dict[str, Any]:
    if not REGISTRY_PATH.is_file():
        return {"version": 1, "articles": {}}
    try:
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"version": 1, "articles": {}}
    if "articles" not in data:
        data["articles"] = {}
    return data


def save_registry(data: dict[str, Any]) -> None:
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def is_processed(url: str, *, include_failed: bool = False) -> bool:
    key = normalize_url(url)
    entry = load_registry()["articles"].get(key)
    if not entry:
        return False
    if include_failed:
        return True
    return entry.get("status") == "completed"


def register_article(
    url: str,
    *,
    language: str,
    project_folder: str | None = None,
    published_at: str | None = None,
    status: str = "completed",
    error: str | None = None,
) -> None:
    data = load_registry()
    key = normalize_url(url)
    data["articles"][key] = {
        "language": language,
        "processed_at": _now_iso(),
        "project_folder": project_folder,
        "published_at": published_at,
        "status": status,
        "error": error,
    }
    save_registry(data)


def migrate_from_projects() -> int:
    """Import blog URLs from existing project.json files into the registry."""
    data = load_registry()
    articles: dict[str, Any] = data["articles"]
    added = 0
    if not PROJECTS_DIR.is_dir():
        return 0
    for folder in PROJECTS_DIR.iterdir():
        if not folder.is_dir():
            continue
        manifest_path = folder / "project.json"
        if not manifest_path.is_file():
            continue
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        blog = manifest.get("blog_url") or manifest.get("blogURL")
        if not isinstance(blog, str) or not blog.startswith("http"):
            continue
        key = normalize_url(blog)
        if key in articles:
            continue
        phase = manifest.get("phase", "")
        status = "failed" if phase == "failed" else "completed"
        articles[key] = {
            "language": manifest.get("language", "en"),
            "processed_at": manifest.get("created_at") or _now_iso(),
            "project_folder": str(folder),
            "published_at": None,
            "status": status,
            "error": manifest.get("last_error"),
            "imported_from_project": True,
        }
        added += 1
    if added:
        data["articles"] = articles
        save_registry(data)
    return added


def processed_urls(*, include_failed: bool = False) -> set[str]:
    migrate_from_projects()
    data = load_registry()
    out: set[str] = set()
    for url, entry in data["articles"].items():
        if include_failed or entry.get("status") == "completed":
            out.add(normalize_url(url))
    return out
