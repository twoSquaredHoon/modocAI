# Batch & pipeline commands

Quick reference for testing the overnight batch system from the repo root (`modocAI/`).

Requires `./setup.sh` once and `GEMINI_API_KEY` in `.env`.

---

## One article (testing)

```bash
# Newest English post only → full pipeline (best for a quick end-to-end test)
./batch-one.sh

# Same but skip paid Veo videos
./batch-one.sh --skip-videos

# Same but skip article-check step
./batch-one.sh --skip-article-check

# Fetch only (writes urls.txt) — 1 newest per index = 1 EN + 1 KO
./fetch-latest.sh

# Fetch 1 newest English only
./fetch-latest.sh --en-only

# Fetch 1 newest Korean only
./fetch-latest.sh --ko-only

# Re-fetch even if already in the processed list (force re-test)
./fetch-latest.sh --en-only --include-processed

# Fetch then run batch yourself
./fetch-latest.sh --en-only
./batch-run.sh urls.txt --limit 1
./batch-run.sh urls.txt --limit 1 --skip-videos
```

---

## Daily / overnight (production)

```bash
# 5 newest EN + 5 newest KO → output/projects/YYYY-MM-DD/ (skip already processed)
./start-daily-batch.sh    # recommended — survives Terminal closing

# Or run in foreground (blocks until done)
./daily-batch.sh

# Same but skip paid Veo videos
./daily-batch.sh --skip-videos

# Resume after interrupt or partial failure
./resume-batch.sh              # today
./resume-batch.sh 2026-06-28   # specific date folder

# Wider time window instead of "5 newest" (legacy fetch)
./fetch-daily-urls.sh --since-hours 24
./batch-run.sh urls.txt
```

---

## Batch from a URL list

```bash
cp urls.example.txt urls.txt
# edit urls.txt — one URL per line, optional: url,language

./batch-run.sh urls.txt
./batch-run.sh urls.txt --limit 1          # first URL only
./batch-run.sh urls.txt --skip-videos
./batch-run.sh urls.txt --skip-article-check
./batch-run.sh urls.txt --language en      # default lang for lines without ,lang
```

---

## Python scripts directly

```bash
# Fetch index → urls.txt
.venv/bin/python scripts/fetch_blog_index.py --since-hours 24 --output urls.txt
.venv/bin/python scripts/fetch_blog_index.py --latest 1 --en-only --output urls.txt

# Run pipeline from urls.txt
.venv/bin/python scripts/batch_pipeline.py urls.txt
.venv/bin/python scripts/batch_pipeline.py urls.txt --limit 1 --skip-videos

# Single steps (manual debugging)
./blog-to-script.sh "https://www.fevercoach.us/post/..." --output output/projects/test/script.txt
./compare-script.sh output/projects/<folder>/script.txt --url "https://..." --output-dir output/projects/<folder>
./script-to-clips.sh output/projects/<folder>/script.txt --prompts-only
./script-to-voiceover.sh output/projects/<folder>/script.txt --clips-dir output/projects/<folder>
```

---

## Processed-article registry

```bash
# List of URLs already pipelined (auto-created)
cat output/processed_articles.json

# Registry is updated automatically when batch-run finishes
# Existing output/projects/ folders are imported on first fetch/batch run
```

---

## Logs & output

```bash
# Batch run logs
ls -lt output/batch/

# Project folders (open in Modoc Studio)
ls output/projects/

# Refresh app project list
./build-modoc-studio.sh   # or open app and click refresh in sidebar
```

---

## API / env smoke tests

```bash
./test-api.sh      # free — Gemini text
./test-video.sh    # paid — one Veo clip
```

---

## App (review only)

```bash
./build-modoc-studio.sh    # build + launch Modoc Studio
./modoc-studio.sh
```

Use the app to review Article check, Clips, Voiceover, and regenerate individual clips. Bulk generation stays in Terminal.
