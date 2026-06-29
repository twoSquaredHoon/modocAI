#!/usr/bin/env python3
"""Run the full Modoc pipeline sequentially for multiple blog URLs (overnight batch)."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from article_registry import is_processed, migrate_from_projects, normalize_url, register_article
from batch_state import (
    begin as begin_batch_state,
    clear_current,
    effective_status,
    finish as finish_batch_state,
    load as load_batch_state,
    record_result,
    save as save_batch_state,
    set_current,
)
from blog_to_script import slug_from_url
from gemini_util import PROJECT_ROOT

PROJECTS_DIR = PROJECT_ROOT / "output" / "projects"
BATCH_LOG_DIR = PROJECT_ROOT / "output" / "batch"
PYTHON = PROJECT_ROOT / ".venv" / "bin" / "python"
LANGUAGE_SUBDIRS = {"en": "english", "ko": "korean", "es": "spanish"}


def log(msg: str, *, file: Path | None = None) -> None:
    line = msg.rstrip()
    print(line, flush=True)
    if file:
        with file.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")


def run_cmd(
    args: list[str],
    *,
    log_file: Path | None = None,
    step_label: str = "",
) -> None:
    if step_label and log_file:
        log(f"\n--- {step_label} ---", file=log_file)
    proc = subprocess.run(
        args,
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
    )
    if log_file:
        if proc.stdout:
            log(proc.stdout.rstrip(), file=log_file)
        if proc.stderr:
            log(proc.stderr.rstrip(), file=log_file)
    else:
        if proc.stdout:
            print(proc.stdout.rstrip(), flush=True)
        if proc.stderr:
            print(proc.stderr.rstrip(), file=sys.stderr, flush=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"Command failed (exit {proc.returncode}): {' '.join(args)}"
        )


def title_from_script(script_path: Path) -> str:
    for raw in script_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.upper().endswith(":") and len(line) < 20:
            continue
        return line[:72]
    return "Untitled project"


def save_manifest(folder: Path, manifest: dict) -> None:
    path = folder / "project.json"
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_manifest(folder: Path) -> dict | None:
    path = folder / "project.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def parse_urls_file(path: Path, default_language: str) -> list[tuple[str, str]]:
    jobs: list[tuple[str, str]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if "," in line:
            url, lang = line.rsplit(",", 1)
            url, lang = url.strip(), lang.strip().lower()
        else:
            url, lang = line, default_language
        if not url.startswith(("http://", "https://")):
            raise ValueError(f"Invalid URL line: {raw!r}")
        if lang not in ("en", "ko", "es"):
            raise ValueError(f"Language must be en, ko, or es: {raw!r}")
        jobs.append((url, lang))
    return jobs


def language_subdir(language: str) -> str:
    return LANGUAGE_SUBDIRS.get(language, language)


def batch_project_roots(projects_dir: Path) -> list[Path]:
    """Language subfolders plus the batch root (legacy flat layout)."""
    roots = [projects_dir]
    for name in (*LANGUAGE_SUBDIRS.values(), *LANGUAGE_SUBDIRS.keys()):
        path = projects_dir / name
        if path.is_dir() and path not in roots:
            roots.append(path)
    return roots


def create_project_folder(
    url: str,
    language: str,
    *,
    projects_dir: Path,
) -> tuple[Path, dict]:
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    slug = slug_from_url(url)
    folder_name = f"{slug}-{stamp}"
    parent = projects_dir / language_subdir(language)
    parent.mkdir(parents=True, exist_ok=True)
    folder = parent / folder_name
    folder.mkdir(parents=True, exist_ok=False)
    manifest = {
        "id": folder_name,
        "title": slug.replace("-", " ").title(),
        "blog_url": url,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "phase": "creatingScript",
        "language": language,
        "last_error": None,
    }
    save_manifest(folder, manifest)
    return folder, manifest


def find_project_folder(projects_dir: Path, url: str) -> Path | None:
    key = normalize_url(url)
    matches: list[tuple[str, Path]] = []
    for root in batch_project_roots(projects_dir):
        if not root.is_dir():
            continue
        for child in root.iterdir():
            if not child.is_dir():
                continue
            manifest = load_manifest(child)
            if not manifest:
                continue
            blog = manifest.get("blog_url") or manifest.get("blogURL")
            if isinstance(blog, str) and normalize_url(blog) == key:
                matches.append((manifest.get("created_at", ""), child))
    if not matches:
        return None
    matches.sort(key=lambda item: item[0], reverse=True)
    return matches[0][1]


def project_is_complete(folder: Path, *, skip_videos: bool) -> bool:
    manifest = load_manifest(folder)
    if not manifest:
        return False
    phase = manifest.get("phase")
    if skip_videos:
        return phase in ("promptsReview", "voiceoverReview", "ready")
    return phase == "ready"


def run_project_pipeline(
    folder: Path,
    manifest: dict,
    *,
    skip_article_check: bool,
    skip_videos: bool,
    log_file: Path,
    resume: bool = False,
    on_step: Callable[[str], None] | None = None,
) -> dict:
    url = manifest["blog_url"]
    language = manifest["language"]
    script_path = folder / "script.txt"

    def step(label: str, args: list[str]) -> None:
        if on_step:
            on_step(label)
        log(f"  → {label}", file=log_file)
        run_cmd([str(PYTHON), *args], log_file=log_file, step_label=label)

    manifest["last_error"] = None
    save_manifest(folder, manifest)

    if not resume or not script_path.is_file():
        manifest["phase"] = "creatingScript"
        save_manifest(folder, manifest)
        step(
            "Script",
            [
                "scripts/blog_to_script.py",
                url,
                "--output",
                str(script_path),
                "--language",
                language,
            ],
        )
    manifest["title"] = title_from_script(script_path) if script_path.is_file() else manifest.get("title")
    manifest["phase"] = "scriptReview"
    save_manifest(folder, manifest)

    verification_path = folder / "script_verification.json"
    if not skip_article_check and (not resume or not verification_path.is_file()):
        step(
            "Article check",
            [
                "scripts/compare_script_to_article.py",
                str(script_path),
                "--url",
                url,
                "--output-dir",
                str(folder),
                "--language",
                language,
            ],
        )

    clips_path = folder / "clips.json"
    if not resume or not clips_path.is_file():
        manifest["phase"] = "generatingPrompts"
        save_manifest(folder, manifest)
        step(
            "Clip prompts",
            [
                "scripts/script_to_clips.py",
                str(script_path),
                "--output-dir",
                str(folder),
                "--prompts-only",
                "--language",
                language,
            ],
        )
        step(
            "Derived clips",
            [
                "scripts/derived_clips.py",
                str(folder),
                str(script_path),
                "--language",
                language,
            ],
        )
        manifest["phase"] = "promptsReview"
        save_manifest(folder, manifest)

    voiceover_path = folder / "voiceover.wav"
    if not resume or not voiceover_path.is_file():
        manifest["phase"] = "generatingVoiceover"
        save_manifest(folder, manifest)
        step(
            "Voiceover",
            [
                "scripts/script_to_voiceover.py",
                str(script_path),
                "--output",
                str(voiceover_path),
                "--clips-dir",
                str(folder),
                "--language",
                language,
            ],
        )
        manifest["phase"] = "voiceoverReview"
        save_manifest(folder, manifest)

    if not skip_videos:
        manifest["phase"] = "generatingVideos"
        save_manifest(folder, manifest)
        step(
            "Veo videos",
            ["scripts/script_to_clips.py", "--resume", str(folder)],
        )
        manifest["phase"] = "ready"
    elif manifest.get("phase") != "ready":
        manifest["phase"] = "promptsReview"
    manifest["last_error"] = None
    save_manifest(folder, manifest)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run the full pipeline sequentially for each URL in a list (overnight batch)."
    )
    parser.add_argument(
        "urls_file",
        type=Path,
        help="Text file: one blog URL per line (optional: url,language)",
    )
    parser.add_argument(
        "--language",
        default="en",
        choices=["en", "ko", "es"],
        help="Default language when not specified on the line (default: en)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Max number of URLs to process (0 = all)",
    )
    parser.add_argument(
        "--skip-videos",
        action="store_true",
        help="Stop after voiceover (no paid Veo generation)",
    )
    parser.add_argument(
        "--skip-article-check",
        action="store_true",
        help="Skip script vs article verification",
    )
    parser.add_argument(
        "--projects-dir",
        type=Path,
        default=PROJECTS_DIR,
        help="Parent folder for new project directories (default: output/projects)",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Continue a batch: reuse existing project folders and skip finished steps",
    )
    args = parser.parse_args()

    if not PYTHON.is_file():
        print("Run ./setup.sh first (.venv missing).", file=sys.stderr)
        sys.exit(1)

    urls_path = args.urls_file.expanduser().resolve()
    if not urls_path.is_file():
        print(f"URLs file not found: {urls_path}", file=sys.stderr)
        sys.exit(1)

    jobs = parse_urls_file(urls_path, args.language)
    if args.limit > 0:
        jobs = jobs[: args.limit]

    if not jobs:
        print("No URLs to process.", file=sys.stderr)
        sys.exit(1)

    imported = migrate_from_projects()
    if imported:
        print(f"Imported {imported} existing project(s) into processed_articles.json")

    projects_dir = args.projects_dir.expanduser().resolve()
    projects_dir.mkdir(parents=True, exist_ok=True)

    existing = load_batch_state(projects_dir)
    if args.resume:
        status = effective_status(existing)
        if status == "running":
            print(
                "Batch already marked running (PID may still be active). "
                "Stop it first or wait for it to finish.",
                file=sys.stderr,
            )
            sys.exit(1)
        print(f"Resume mode — continuing batch in {projects_dir}")
    elif existing and effective_status(existing) == "running":
        print(
            f"Batch appears to be running in {projects_dir}. "
            "Use --resume after it stops, or ./resume-batch.sh",
            file=sys.stderr,
        )
        sys.exit(1)

    batch_stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    if projects_dir != PROJECTS_DIR.resolve():
        log_dir = projects_dir
    else:
        BATCH_LOG_DIR.mkdir(parents=True, exist_ok=True)
        log_dir = BATCH_LOG_DIR
    master_log = log_dir / f"batch-{batch_stamp}.log"

    batch_state = begin_batch_state(
        projects_dir,
        urls_file=urls_path,
        total=len(jobs),
        skip_videos=args.skip_videos,
        skip_article_check=args.skip_article_check,
        resume=args.resume,
    )

    log(f"Batch started: {len(jobs)} project(s)", file=master_log)
    log(f"Projects dir: {projects_dir}", file=master_log)
    log(f"Resume: {args.resume}", file=master_log)
    log(f"Skip videos: {args.skip_videos}", file=master_log)
    log(f"Skip article check: {args.skip_article_check}", file=master_log)

    results: list[dict] = []
    for index, (url, language) in enumerate(jobs, start=1):
        log(f"\n{'=' * 60}", file=master_log)
        log(f"[{index}/{len(jobs)}] {url} ({language})", file=master_log)
        project_log = log_dir / f"batch-{batch_stamp}-{index:02d}.log"

        existing_folder = find_project_folder(projects_dir, url)
        if existing_folder and project_is_complete(
            existing_folder, skip_videos=args.skip_videos
        ):
            log(f"  ⊘ Skip — already complete in batch folder", file=master_log)
            record_result(batch_state, projects_dir, "skipped")
            results.append(
                {
                    "status": "skipped",
                    "url": url,
                    "language": language,
                    "reason": "already complete in batch",
                    "folder": str(existing_folder),
                }
            )
            continue

        if not args.resume and is_processed(url):
            log(f"  ⊘ Skip — already in processed_articles.json", file=master_log)
            record_result(batch_state, projects_dir, "skipped")
            results.append(
                {
                    "status": "skipped",
                    "url": url,
                    "language": language,
                    "reason": "already processed",
                }
            )
            continue

        folder: Path | None = None
        try:
            if existing_folder and args.resume:
                folder = existing_folder
                manifest = load_manifest(folder)
                if not manifest:
                    raise RuntimeError(f"Missing project.json in {folder}")
                log(f"  ↻ Resuming → {folder}", file=master_log)
                resume_run = True
            elif existing_folder and not project_is_complete(
                existing_folder, skip_videos=args.skip_videos
            ):
                folder = existing_folder
                manifest = load_manifest(folder)
                if not manifest:
                    raise RuntimeError(f"Missing project.json in {folder}")
                log(f"  ↻ Continuing partial project → {folder}", file=master_log)
                resume_run = True
            else:
                folder, manifest = create_project_folder(
                    url, language, projects_dir=projects_dir
                )
                resume_run = False

            def on_step(label: str) -> None:
                set_current(
                    batch_state,
                    projects_dir,
                    index=index,
                    url=url,
                    language=language,
                    folder=str(folder),
                    step=label,
                )

            set_current(
                batch_state,
                projects_dir,
                index=index,
                url=url,
                language=language,
                folder=str(folder),
                step="starting",
            )
            manifest = run_project_pipeline(
                folder,
                manifest,
                skip_article_check=args.skip_article_check,
                skip_videos=args.skip_videos,
                log_file=project_log,
                resume=resume_run,
                on_step=on_step,
            )
            clear_current(batch_state, projects_dir)
            record_result(batch_state, projects_dir, "ok")
            results.append(
                {
                    "status": "ok",
                    "url": url,
                    "language": language,
                    "folder": str(folder),
                    "title": manifest.get("title"),
                }
            )
            register_article(
                url,
                language=language,
                project_folder=str(folder),
                status="completed",
            )
            log(f"  ✓ Done → {folder}", file=master_log)
        except Exception as exc:
            err = str(exc)
            batch_state["last_error"] = err
            save_batch_state(projects_dir, batch_state)
            clear_current(batch_state, projects_dir)
            record_result(batch_state, projects_dir, "failed")
            results.append(
                {
                    "status": "failed",
                    "url": url,
                    "language": language,
                    "error": err,
                }
            )
            register_article(
                url,
                language=language,
                project_folder=str(folder) if folder else None,
                status="failed",
                error=err,
            )
            log(f"  ✗ Failed: {err}", file=master_log)
            if folder:
                try:
                    mf_path = folder / "project.json"
                    if mf_path.is_file():
                        mf = json.loads(mf_path.read_text(encoding="utf-8"))
                        mf["phase"] = "failed"
                        mf["last_error"] = err
                        save_manifest(folder, mf)
                except OSError:
                    pass

    summary_path = log_dir / f"batch-{batch_stamp}-summary.json"
    summary_path.write_text(
        json.dumps(results, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    ok = sum(1 for r in results if r["status"] == "ok")
    skipped = sum(1 for r in results if r["status"] == "skipped")
    failed = sum(1 for r in results if r["status"] == "failed")
    finish_batch_state(
        batch_state,
        projects_dir,
        success=failed == 0,
    )

    log(f"\nBatch finished: {ok}/{len(jobs)} succeeded ({skipped} skipped, {failed} failed)", file=master_log)
    log(f"Summary → {summary_path}", file=master_log)
    log(f"Master log → {master_log}", file=master_log)
    log(f"\nOpen Modoc Studio — projects appear under {projects_dir}", file=master_log)

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
