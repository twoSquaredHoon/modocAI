# Modoc Studio

Mac app for the modocAI video pipeline: create projects from blog URLs, run pipeline steps, review outputs, and preview clips in-app.

See the main [README.md](../README.md) for the full workflow overview.

## Requirements

- macOS 14+
- Xcode Command Line Tools / Swift 5.9+
- `./setup.sh` completed in the modocAI repo root
- `GEMINI_API_KEY` in `.env` (for pipeline steps only — app opens without it)

## Fresh install (once)

```bash
git clone … modocAI
cd modocAI
./setup.sh
# paste GEMINI_API_KEY into .env
./build-modoc-studio.sh
```

## Run the app

```bash
./build-modoc-studio.sh     # build + launch
# or
./modoc-studio.sh
```

After setup, only `./build-modoc-studio.sh` is needed.

**Do not** use `swift run` from Terminal for normal use — keystrokes go to Terminal, not the app.

If the setup sheet appears, choose the **modocAI repo root** (folder with `setup.sh` and `scripts/`). If it says Python is missing, run `./setup.sh` in Terminal first.

## App workflow

**Typical use:** `./daily-batch.sh` before bed → open Modoc Studio in the morning to review and fix.

The app can also **New Project** for a one-off URL (optional full auto pipeline in the sheet).

1. **Open projects** — sidebar lists `output/projects/`; batch-created folders appear automatically after refresh.
2. **Review tabs** — Article check · Script · Prompts · Voiceover · Clips
3. **Workflow** — re-run steps or **Run remaining steps** if something failed
4. **Statistics / Graph** — timing and version history
5. **Finalize** — mark complete for KPI tracking

One project = one language (set at create / in `urls.txt`). Separate projects per EN / KO / ES article.

## Project files

```
output/projects/<slug>-<timestamp>/
  project.json
  script.txt
  clip_decisions.txt
  clip_prompts.txt
  clips.json
  voiceover.wav
  pipeline.log
  pipeline_stats.json
  workflow_graph.json
  videos/*.mp4
  languages/{en|ko|es}/…
```

## Config

The app finds the modocAI root via:

1. UserDefaults `modocAIRootPath` (set by `./setup.sh` or **Choose modocAI Folder…** in the menu)
2. `.modoc-root` file in the repo (written by `./setup.sh`)
3. Auto-detect when `ModocStudio.app` lives inside the repo

Python used for pipeline steps: `{modocAI root}/.venv/bin/python`

## Xcode (optional)

```bash
open ModocStudio/Package.swift
```

Press **⌘R** to run.
