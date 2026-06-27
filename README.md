# Modoc AI

**Mission:** Medically accurate short-form parenting health videos for young children — with minimum human effort.

**Rule:** Be medically accurate. Scripts and clips must match the source blog, not invent facts.

**KPI:** Views ÷ pipeline work time (see [docs/KPI_RATING_FORM.md](docs/KPI_RATING_FORM.md))

**Channels:** [YouTube](https://www.youtube.com/channel/UCMWz3D-NhAVQyxGvbRZTblw) · Instagram · Facebook · MoDoc blog embed

---

## How it works

Modoc AI is two parts:

| Part | What it does |
|------|----------------|
| **Modoc Studio** (Mac app) | Review & edit projects — script check, clips, voiceover, regenerate; optional single-project create |
| **Python pipeline** (`scripts/`) | Blog → script → article check → clip prompts → voiceover → Veo (CLI + overnight batch) |

The app calls the same Python scripts you can run from Terminal. Everything is stored as files on disk — no database.

```
Blog URL (FeverCoach)
        │
        ▼
   ① Script          Gemini text — HOOK / BODY / EXPLAIN / SIGNS / RELIEF / CTA
        │
        ▼
   ② Clip prompts    Gemini decides what to show + writes Veo prompts (consistent cast)
        │
        ▼
   ③ Voiceover       Gemini TTS — paced to clip lengths
        │
        ▼
   ④ Video clips     Veo — one .mp4 per clip (hook, body, explain, signs, relief, cta)
        │
        ▼
   ⑤ Edit & publish  Manual — CapCut, Premiere, YouTube / IG / FB
```

**Clip order:** `hook` → `body_1`, `body_2`, … → `explain_1`, … → `signs_1`, … → `relief` → `cta`  
**Durations:** 4s (hook, explain, signs, cta) · 6s (body, relief)

**Languages:** English, Korean, Spanish — separate workspace per language under each project (`languages/en`, `ko`, `es`).

---

## Setup (once per machine)

```bash
git clone <repo-url> modocAI
cd modocAI
./setup.sh                  # Python venv, .env, output folders, app path
```

Add your Gemini API key to `.env`:

```
GEMINI_API_KEY=your-key-here
```

Get a key at https://aistudio.google.com/apikey (Veo video needs billing on your Google account).

Verify (optional):

```bash
./test-api.sh               # free — text + list models
./test-video.sh             # paid — one short Veo test clip
```

If `./setup.sh` fails with a broken venv (`bad interpreter`), it will recreate `.venv` automatically. You can also run `rm -rf .venv && ./setup.sh`.

---

## Run the app

**First time after setup:**

```bash
./build-modoc-studio.sh
```

**Every time after that:**

```bash
./build-modoc-studio.sh     # or ./modoc-studio.sh
```

Do **not** use `swift run` from Terminal for normal use — keyboard focus goes to Terminal, not the app.

On first launch, if prompted, choose the **modocAI repo root** (the folder containing `setup.sh` and `scripts/`).

More app details: [ModocStudio/README.md](ModocStudio/README.md)

---

## Workflow in Modoc Studio (review & edit)

Modoc Studio is mainly for **reviewing and fixing** work produced by the pipeline. You can still create a single project from the app if you want.

1. Open projects from the sidebar (or **Open Existing Project** → `output/projects/...`).
2. **Article check** — verify script vs blog; rewrite, remove, or disregard flagged lines.
3. **Script** — select lines for custom clips.
4. **Clips** — preview videos; regenerate individual clips.
5. **Voiceover** — listen and compare.
6. **Workflow** — re-run any step or **Run remaining steps** if batch stopped partway.
7. **Statistics / Graph** — timing and version history.
8. **Edit & publish** — export `voiceover.wav` + `videos/*.mp4` to CapCut etc.

One project = one language. Create separate projects (or batch jobs) for EN / KO / ES articles.

---

## Overnight batch (bulk generation)

Run several articles **one after another** from Terminal while you sleep. Projects appear in Modoc Studio the next morning.

### Daily EN + KO (recommended)

Each run fetches posts **published in the last 24 hours** from both indexes, skips articles already in `output/processed_articles.json`, then runs the pipeline:

```bash
./daily-batch.sh
```

Registry: `output/processed_articles.json` — one entry per blog URL so the same article is never processed twice. Existing projects are imported into the registry automatically on first run.

Or step by step:

```bash
./fetch-daily-urls.sh          # → urls.txt (last 24h, EN + KO, skip processed)
./batch-run.sh urls.txt        # sequential full pipeline; registers each URL when done
```

Blog indexes:
- English: https://www.fevercoach.us/blog
- Korean: https://www.fevercoach.us/ko/blog

Options:

```bash
./fetch-daily-urls.sh --since-hours 36   # wider window if you missed a day
./batch-run.sh urls.txt --skip-videos
```

**Testing one article:** see [docs/BATCH-COMMANDS.md](docs/BATCH-COMMANDS.md)

```bash
./batch-one.sh                  # newest EN post → full pipeline
./batch-one.sh --skip-videos    # same, no Veo
./fetch-latest.sh --en-only     # fetch only, no pipeline
```

Schedule the same time daily (example macOS `launchd` — run at 2am):

```bash
# ~/Library/LaunchAgents/us.fevercoach.modoc.daily.plist → cd modocAI && ./daily-batch.sh
```

Manual URL list (optional):

```bash
cp urls.example.txt urls.txt
# edit urls.txt — one URL per line (optional: url,ko)

./batch-run.sh urls.txt
```

Each project runs: **Script → Article check → Clip prompts → Voiceover → Veo videos** (same as the app’s full auto pipeline).

| Flag | Meaning |
|------|---------|
| `--limit 5` | Process at most 5 URLs |
| `--skip-videos` | Stop before paid Veo generation |
| `--skip-article-check` | Skip Gemini script vs article step |
| `--language ko` | Default language when not on the line |

Logs: `output/batch/batch-<timestamp>.log` and `batch-<timestamp>-summary.json`

---

## Workflow from Terminal (single project CLI)

Same pipeline without the app. See **[WORKFLOW.md](WORKFLOW.md)** for full commands.

```bash
# 1 — Script
./blog-to-script.sh "https://www.fevercoach.us/post/your-post"

# 2 — Clip prompts (no Veo cost)
./script-to-clips.sh output/scripts/<your-script>.txt --prompts-only

# 3 — Voiceover (best after prompts exist)
./script-to-voiceover.sh output/scripts/<your-script>.txt \
  --clips-dir output/projects/<your-project-folder>

# 4 — Veo videos (paid; resumes if interrupted)
./script-to-clips.sh --resume output/projects/<your-project-folder>
```

Shortcut — blog → script → clips (no voiceover):

```bash
./make-video.sh "https://your-blog-url"
```

List real file paths (don't guess names):

```bash
./list-outputs.sh
```

---

## Where things live

### Repo layout

```
modocAI/
  .env                 # API key (gitignored)
  setup.sh             # one-time environment setup
  build-modoc-studio.sh
  scripts/             # Python pipeline
  ModocStudio/         # SwiftUI app source
  ModocStudio.app      # built app (gitignored)
  output/              # generated content (gitignored except .gitkeep)
```

### Project folder (Modoc Studio)

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
  videos/*.mp4
  languages/
    en/   …
    ko/   …
    es/   …
```

AI-generated output under `output/` is **not committed to git**.

---

## Script & prompt rules (source of truth)

Script generation rules live in code, not in this README:

| File | Contents |
|------|----------|
| [scripts/prompts.py](scripts/prompts.py) | `SCRIPT_RULES`, `SCRIPT_RULES_KO`, `SCRIPT_RULES_ES` + clip prompts |
| [scripts/language_config.py](scripts/language_config.py) | Per-language TTS voice and system instructions |
| [scripts/blog_to_script.py](scripts/blog_to_script.py) | Blog fetch + Gemini script call |

Edit `scripts/prompts.py` to change how scripts and clips are written.

---

## More docs

| Doc | Contents |
|-----|----------|
| [WORKFLOW.md](WORKFLOW.md) | CLI commands, resume, options |
| [ModocStudio/README.md](ModocStudio/README.md) | App build, tabs, config |
| [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) | Full system requirements |
| [docs/KPI_RATING_FORM.md](docs/KPI_RATING_FORM.md) | Weekly KPI logging |
