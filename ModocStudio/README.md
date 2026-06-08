# Modoc Studio (Mac prototype)

Minimal SwiftUI app for the modocAI video pipeline: create projects from blog URLs, review script, generate clip prompts, generate Veo videos, and preview clips in-app.

## Requirements

- macOS 14+
- Xcode Command Line Tools / Swift 5.9+
- Gemini API key in `.env` (for pipeline steps only)

## Fresh install (once)

```bash
git clone … modocAI   # folder name modocAI recommended
cd modocAI
./setup.sh            # venv, .env, folders, app root path — run once
# paste GEMINI_API_KEY into .env if needed
./build-modoc-studio.sh
```

After that, only `./build-modoc-studio.sh` when you want to run the app.

## Run (recommended)

**Do not use `swift run` from Terminal** — keystrokes will go to Terminal, not the app.

Build a proper `.app` and launch it:

```bash
cd /Users/seunghoon/Documents/2.Area/modocAI
./modoc-studio.sh
```

This opens **Modoc Studio.app** in the Dock. Click the app window, then type in New Project.

**Open an existing project:** **File → Open Project…** (⌘O), or **Open Project…** in the sidebar. Pick any folder with `script.txt`, `clips.json`, or `project.json` — including legacy runs under `output/clips/…`.

### Or use Xcode

```bash
open ModocStudio/Package.swift
```

Press **⌘R** to run. Same result — keyboard goes to the app.

### Debug only (Terminal attached — typing may fail)

```bash
cd ModocStudio && swift run ModocStudio
```

## Flow

1. **New Project** → paste blog URL → script generates automatically
2. **Workflow** → review script → **Continue to clip prompts**
3. Review prompts (Prompts tab) → **Generate videos (Veo, paid)**
4. **Clips** tab → select clip → inline video preview

## Project files

Each project lives in one folder:

```
output/projects/<slug>-<timestamp>/
  project.json
  script.txt
  clip_decisions.txt
  clip_prompts.txt
  clips.json
  pipeline.log
  videos/*.mp4
```

## Config

Default modocAI root: `/Users/seunghoon/Documents/2.Area/modocAI`

To change, set UserDefaults key `modocAIRootPath` (Settings UI can be added later).

## Open in Xcode (optional)

```bash
open Package.swift
```

Run the **ModocStudio** scheme.
