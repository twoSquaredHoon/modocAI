#!/usr/bin/env python3
"""Read/write batch_state.json for overnight batch progress and resume."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

STATE_FILENAME = "batch_state.json"
STALE_SECONDS = 900  # 15 min without update while "running" → likely stuck


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def state_path(batch_dir: Path) -> Path:
    return batch_dir / STATE_FILENAME


def load(batch_dir: Path) -> dict[str, Any] | None:
    path = state_path(batch_dir)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def save(batch_dir: Path, state: dict[str, Any]) -> None:
    state["updated_at"] = _now_iso()
    batch_dir.mkdir(parents=True, exist_ok=True)
    state_path(batch_dir).write_text(
        json.dumps(state, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def pid_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def seconds_since(iso: str | None) -> float | None:
    if not iso:
        return None
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return max(0, (datetime.now(timezone.utc) - dt).total_seconds())
    except ValueError:
        return None


def effective_status(state: dict[str, Any] | None) -> str:
    """Return running | completed | failed | interrupted | idle."""
    if not state:
        return "idle"
    status = state.get("status", "idle")
    if status != "running":
        return status
    pid = state.get("pid")
    if pid_alive(pid):
        return "running"
    age = seconds_since(state.get("updated_at"))
    if age is not None and age > STALE_SECONDS:
        return "interrupted"
    return "interrupted" if not pid_alive(pid) else "running"


def begin(
    batch_dir: Path,
    *,
    urls_file: Path,
    total: int,
    skip_videos: bool,
    skip_article_check: bool,
    resume: bool,
) -> dict[str, Any]:
    prev = load(batch_dir)
    state: dict[str, Any] = {
        "version": 1,
        "status": "running",
        "batch_dir": str(batch_dir),
        "urls_file": str(urls_file),
        "started_at": prev.get("started_at") if resume and prev else _now_iso(),
        "updated_at": _now_iso(),
        "pid": os.getpid(),
        "resume": resume,
        "skip_videos": skip_videos,
        "skip_article_check": skip_article_check,
        "total": total,
        "completed": prev.get("completed", 0) if resume and prev else 0,
        "failed": prev.get("failed", 0) if resume and prev else 0,
        "skipped": prev.get("skipped", 0) if resume and prev else 0,
        "current": None,
        "last_error": None,
    }
    save(batch_dir, state)
    return state


def set_current(
    state: dict[str, Any],
    batch_dir: Path,
    *,
    index: int,
    url: str,
    language: str,
    folder: str | None,
    step: str,
) -> None:
    state["current"] = {
        "index": index,
        "url": url,
        "language": language,
        "folder": folder,
        "step": step,
    }
    state["pid"] = os.getpid()
    save(batch_dir, state)


def clear_current(state: dict[str, Any], batch_dir: Path) -> None:
    state["current"] = None
    save(batch_dir, state)


def record_result(
    state: dict[str, Any],
    batch_dir: Path,
    result_status: str,
) -> None:
    if result_status == "ok":
        state["completed"] = int(state.get("completed", 0)) + 1
    elif result_status == "failed":
        state["failed"] = int(state.get("failed", 0)) + 1
    elif result_status == "skipped":
        state["skipped"] = int(state.get("skipped", 0)) + 1
    save(batch_dir, state)


def finish(state: dict[str, Any], batch_dir: Path, *, success: bool) -> None:
    state["status"] = "completed" if success else "failed"
    state["current"] = None
    state["pid"] = None
    state["finished_at"] = _now_iso()
    save(batch_dir, state)


def mark_fetching(batch_dir: Path, *, pid: int | None = None) -> None:
    """Called at the start of daily-batch.sh before URL fetch."""
    state: dict[str, Any] = {
        "version": 1,
        "status": "running",
        "phase": "fetching",
        "batch_dir": str(batch_dir),
        "started_at": _now_iso(),
        "updated_at": _now_iso(),
        "pid": pid or os.getpid(),
        "total": 0,
        "completed": 0,
        "failed": 0,
        "skipped": 0,
        "current": {
            "index": 0,
            "url": "",
            "language": "",
            "folder": None,
            "step": "Fetching blog index",
        },
        "last_error": None,
    }
    save(batch_dir, state)


def touch_fetching(batch_dir: Path, *, step: str) -> None:
    state = load(batch_dir) or {}
    state["status"] = "running"
    state["phase"] = "fetching"
    state["updated_at"] = _now_iso()
    state["current"] = {
        "index": 0,
        "url": "",
        "language": "",
        "folder": None,
        "step": step,
    }
    save(batch_dir, state)


def mark_no_urls(batch_dir: Path) -> None:
    state = load(batch_dir) or {}
    state["status"] = "completed"
    state["phase"] = "fetching"
    state["current"] = None
    state["pid"] = None
    state["finished_at"] = _now_iso()
    state["last_error"] = "No new URLs to process"
    save(batch_dir, state)


def mark_fetch_failed(batch_dir: Path, error: str) -> None:
    state = load(batch_dir) or {}
    state["status"] = "failed"
    state["phase"] = "fetching"
    state["current"] = None
    state["pid"] = None
    state["finished_at"] = _now_iso()
    state["last_error"] = error
    save(batch_dir, state)


PID_FILENAME = "daily-batch.pid"


def pid_path(batch_dir: Path) -> Path:
    return batch_dir / PID_FILENAME


def write_pid(batch_dir: Path, pid: int) -> None:
    batch_dir.mkdir(parents=True, exist_ok=True)
    pid_path(batch_dir).write_text(f"{pid}\n", encoding="utf-8")


def read_pid(batch_dir: Path) -> int | None:
    path = pid_path(batch_dir)
    if not path.is_file():
        return None
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except ValueError:
        return None


def clear_pid(batch_dir: Path) -> None:
    path = pid_path(batch_dir)
    if path.is_file():
        path.unlink()


def is_batch_running(batch_dir: Path) -> bool:
    pid = read_pid(batch_dir)
    if pid and pid_alive(pid):
        return True
    state = load(batch_dir)
    if state and state.get("status") == "running":
        spid = state.get("pid")
        if spid and pid_alive(spid):
            return True
    return False
