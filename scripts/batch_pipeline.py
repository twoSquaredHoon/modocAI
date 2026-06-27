#!/usr/bin/env python3
"""Run the full Modoc pipeline sequentially for multiple blog URLs (overnight batch)."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from blog_to_script import slug_from_url
from article_registry import is_processed, migrate_from_projects, register_article
from gemini_util import PROJECT_ROOT

PROJECTS_DIR = PROJECT_ROOT / "output" / "projects"
BATCH_LOG_DIR = PROJECT_ROOT / "output" / "batch"
PYTHON = PROJECT_ROOT / ".venv" / "bin" / "python"


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


def create_project_folder(url: str, language: str) -> tuple[Path, dict]:
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    slug = slug_from_url(url)
    folder_name = f"{slug}-{stamp}"
    folder = PROJECTS_DIR / folder_name
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


def run_project_pipeline(
    folder: Path,
    manifest: dict,
    *,
    skip_article_check: bool,
    skip_videos: bool,
    log_file: Path,
) -> dict:
    url = manifest["blog_url"]
    language = manifest["language"]
    script_path = folder / "script.txt"

    def step(label: str, args: list[str]) -> None:
        log(f"  → {label}", file=log_file)
        run_cmd([str(PYTHON), *args], log_file=log_file, step_label=label)

    manifest["phase"] = "creatingScript"
    manifest["last_error"] = None
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
    manifest["title"] = title_from_script(script_path)
    manifest["phase"] = "scriptReview"
    save_manifest(folder, manifest)

    if not skip_article_check:
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

    manifest["phase"] = "generatingVoiceover"
    save_manifest(folder, manifest)
    step(
        "Voiceover",
        [
            "scripts/script_to_voiceover.py",
            str(script_path),
            "--output",
            str(folder / "voiceover.wav"),
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
    else:
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

    BATCH_LOG_DIR.mkdir(parents=True, exist_ok=True)
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
    batch_stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    master_log = BATCH_LOG_DIR / f"batch-{batch_stamp}.log"

    log(f"Batch started: {len(jobs)} project(s)", file=master_log)
    log(f"Skip videos: {args.skip_videos}", file=master_log)
    log(f"Skip article check: {args.skip_article_check}", file=master_log)

    results: list[dict] = []
    for index, (url, language) in enumerate(jobs, start=1):
        log(f"\n{'=' * 60}", file=master_log)
        log(f"[{index}/{len(jobs)}] {url} ({language})", file=master_log)
        project_log = BATCH_LOG_DIR / f"batch-{batch_stamp}-{index:02d}.log"
        if is_processed(url):
            log(f"  ⊘ Skip — already in processed_articles.json", file=master_log)
            results.append(
                {
                    "status": "skipped",
                    "url": url,
                    "language": language,
                    "reason": "already processed",
                }
            )
            continue
        try:
            folder, manifest = create_project_folder(url, language)
            manifest = run_project_pipeline(
                folder,
                manifest,
                skip_article_check=args.skip_article_check,
                skip_videos=args.skip_videos,
                log_file=project_log,
            )
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
                project_folder=str(folder) if "folder" in locals() else None,
                status="failed",
                error=err,
            )
            log(f"  ✗ Failed: {err}", file=master_log)
            if "folder" in locals():
                try:
                    mf_path = folder / "project.json"
                    if mf_path.is_file():
                        mf = json.loads(mf_path.read_text(encoding="utf-8"))
                        mf["phase"] = "failed"
                        mf["last_error"] = err
                        save_manifest(folder, mf)
                except OSError:
                    pass

    summary_path = BATCH_LOG_DIR / f"batch-{batch_stamp}-summary.json"
    summary_path.write_text(
        json.dumps(results, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    ok = sum(1 for r in results if r["status"] == "ok")
    skipped = sum(1 for r in results if r["status"] == "skipped")
    log(f"\nBatch finished: {ok}/{len(jobs)} succeeded ({skipped} skipped)", file=master_log)
    log(f"Summary → {summary_path}", file=master_log)
    log(f"Master log → {master_log}", file=master_log)
    log("\nOpen Modoc Studio — projects appear under output/projects/", file=master_log)

    if ok < len(jobs) - skipped:
        sys.exit(1)


if __name__ == "__main__":
    main()
