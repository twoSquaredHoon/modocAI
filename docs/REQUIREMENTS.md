# Modoc AI — Requirements Document

**Version:** 1.0  
**Last updated:** 2026-06-08  
**Scope:** modocAI Python pipeline + Modoc Studio (macOS app)

---

## 1. Purpose & success criteria

### 1.1 Mission

Modoc AI (Parenting Laboratory) produces **medically accurate short-form parenting health videos** for young children with **minimum human effort**.

Primary distribution: YouTube, Instagram, Facebook, MoDoc blog embed.

### 1.2 North-star metric

```
KPI = Σ Views (all platforms) ÷ Σ Pipeline human execution time
```

- **Numerator:** total views across YouTube, MoDoc blog, Instagram, Facebook.
- **Denominator:** repeat human time per published video from source selection through publish, **including medical review** for all languages (EN / KO / ES).
- **Excludes:** internship / system-building time (see [KPI_RATING_FORM.md](./KPI_RATING_FORM.md)).
- KPI tracking starts after the end-to-end pipeline completes at least once.

### 1.3 Non-negotiable rule

**Be medically accurate.** Scripts, voiceovers, and clips must reflect the source blog only. No invented diagnoses, dosing, or emergency guidance.

---

## 2. System overview

Modoc AI is a **hybrid system**:

| Layer | Technology | Role |
|-------|------------|------|
| **Pipeline** | Python 3 + shell scripts | Blog → script → clip prompts → voiceover → Veo videos |
| **Studio** | SwiftUI macOS app | Project UI, workflow control, preview, KPI timing, version graph |
| **Storage** | Files on disk | No database; projects are folders under `output/projects/` |
| **AI services** | Google Gemini API | Text (script, clip decisions/prompts), TTS, Veo video |

```
Blog URL
   │
   ▼
[1] Script (Gemini text)          ── script.txt
   │
   ▼
[2] Clip prompts (Gemini text)    ── clip_decisions.txt, clip_prompts.txt, clips.json
   │                              └── derived_clips.py syncs EXPLAIN + SIGNS clips
   ▼
[3] Voiceover (Gemini TTS)        ── voiceover.wav, speech.txt, voiceover_meta.json
   │
   ▼
[4] Videos (Veo, paid)            ── videos/*.mp4
   │
   ▼
[5] Manual edit & publish         ── CapCut / Premiere → YouTube / IG / FB / blog
```

---

## 3. Environment & dependencies

### 3.1 Hardware & OS

| Requirement | Detail |
|-------------|--------|
| OS | macOS 14+ (Modoc Studio) |
| Architecture | Apple Silicon or Intel (Swift build) |
| Network | Required for Gemini API calls |
| Disk | Sufficient space for `.mp4` / `.wav` per project |

### 3.2 Software prerequisites

| Component | Version / note |
|-----------|----------------|
| Python | 3.x (via `./setup.sh` → `.venv/`) |
| Swift | 5.9+ / Xcode Command Line Tools |
| Shell | bash/zsh for wrapper scripts |

### 3.3 Python packages (`requirements.txt`)

- `google-genai>=1.0.0` — Gemini text, TTS, Veo
- `python-dotenv>=1.0.0` — load `.env`
- `trafilatura>=2.0.0` — blog article extraction

### 3.4 API key & configuration

| Item | Requirement |
|------|-------------|
| **`.env`** | Project root; `GEMINI_API_KEY=<key>` (or `GOOGLE_API_KEY`) |
| **`.env.example`** | Template only; committed to git |
| **`.env`** | Gitignored; never committed |
| **Billing** | Google account with billing enabled for **Veo** video generation |
| **Key source** | Only `scripts/gemini_util.py` → `load_dotenv(PROJECT_ROOT / ".env")` then env vars |

Setup:

```bash
./setup.sh          # creates .venv, .env if missing, pip install
./test-api.sh       # verify key (free text check)
./test-video.sh     # optional Veo smoke test (paid)
```

### 3.5 Modoc Studio config

| Setting | Default | Override |
|---------|---------|----------|
| modocAI root | `/Users/seunghoon/Documents/2.Area/modocAI` | UserDefaults `modocAIRootPath` |
| Python | `{root}/.venv/bin/python` | Must exist (`./setup.sh`) |
| Projects dir | `{root}/output/projects/` | — |

Launch:

```bash
./build-modoc-studio.sh   # or ./modoc-studio.sh
```

Do **not** use `swift run` from Terminal for normal use (keyboard focus issue).

---

## 4. Content sources & languages

### 4.1 Source content

- **Primary input:** MoDoc / FeverCoach blog URL (`https://www.fevercoach.us/post/...`).
- **Extraction:** `trafilatura` pulls article text; Gemini writes the spoken script from that text only.

### 4.2 Supported languages

| Code | Label | Script rules | TTS voice | TTS locale |
|------|-------|--------------|-----------|------------|
| `en` | English | `SCRIPT_RULES` | Charon | en-US |
| `ko` | Korean | `SCRIPT_RULES_KO` | Kore | ko-KR |
| `es` | Spanish | `SCRIPT_RULES_ES` | Aoede | es-US |

- English blog may be translated to KO/ES faithfully; no added medical claims.
- Korean uses syllable-based pacing heuristics for TTS timing.

### 4.3 Multi-language project model

Each project supports **independent EN / KO / ES workspaces**:

```
output/projects/<slug>-<timestamp>/
  project.json                    # active language + phase
  script.txt                      # mirrors active language (Python compat)
  clips.json, videos/, …          # mirrors active language
  languages/
    en/   script.txt, clips.json, videos/, workflow_graph.json, …
    ko/   …
    es/   …
  pipeline_stats.json             # KPI timing (project-level)
```

**Behavior:**

- Switching language **persists** the current language to `languages/{code}/`, then **activates** the target (copies to project root or clears root if empty).
- Empty language → workflow steps appear fresh (grey / no artifacts).
- Legacy single-language projects auto-migrate to `languages/{active}/` on open.

---

## 5. Script requirements

### 5.1 Structure

Every script has four spoken sections:

```
HOOK:
BODY:
RELIEF:
CTA:
```

### 5.2 Content rules (all languages)

| Rule | Detail |
|------|--------|
| Length | Under ~45 seconds when read aloud |
| Style | Spoken language; short sentences; no medical jargon |
| Age | If blog mentions age, all child references must match; else default school age 5–12 |
| HOOK | Urgent, personal, accurate — not generic fear-mongering |
| BODY | One sentence per line; context → EXPLAIN lines → signs intro (`:`) → one sign per line |
| EXPLAIN | Home-care / dosing instructions from blog; one instruction per line |
| SIGNS | Warning signs after intro line ending with `:`; one sign per line |
| RELIEF | Re-state warning signs briefly, then ER vs doctor action — no vague “if you see these” |
| CTA | Comment-bait question (e.g. “Has your child ever…?”) |

### 5.3 Script generation

| Field | Value |
|-------|-------|
| Script | `scripts/blog_to_script.py` |
| Model | `gemini-2.5-flash` |
| CLI | `./blog-to-script.sh "URL" [--language en\|ko\|es]` |
| Output | `script.txt` (Studio: project folder) |

---

## 6. Clip pipeline requirements

### 6.1 Clip sequence

Standard order:

```
hook → body_1, body_2, … → explain_1, … → signs_1, … → relief → cta
```

| Clip type | Required when | Duration |
|-----------|---------------|----------|
| `hook` | Always | 4s |
| `body_N` | Always (typically 2–3) | 6s each |
| `explain_N` | BODY has home-care / dosing lines | 4s each |
| `signs_N` | BODY has warning-sign list | 4s each |
| `relief` | Always | 6s |
| `cta` | Always | 4s |

> **Note:** 7–10s clip durations have been discussed but are **not** implemented; current spec is 4s / 6s as above.

### 6.2 Three-step clip generation

1. **Clip decisions** — what to show per section (no camera/style yet).
2. **Detailed prompts** — subject, setting, action, mood, camera, lighting, style; JSON in `clips.json`.
3. **Veo generation** — one `.mp4` per clip id.

| Field | Value |
|-------|-------|
| Text model | `gemini-2.5-flash` |
| Video model | `veo-3.1-fast-generate-preview` |
| Script | `scripts/script_to_clips.py` |
| Derived sync | `scripts/derived_clips.py` — ensures EXPLAIN/SIGNS in decisions, prompts, JSON |

**EXPLAIN clips:** cinematic warm scene with consistent cast; no on-screen text.  
**SIGNS clips:** one wordless presentation visual per sign; soft warm background; no text.

### 6.3 Visual cast

- `visual_cast.txt` defines consistent character appearance per language/region.
- Cast bible injected into clip prompt step for continuity across clips.

### 6.4 Resume & partial generation

| Capability | Requirement |
|------------|-------------|
| Resume | `--resume <folder>` skips clips with existing valid `.mp4` (>1KB) |
| Prompts only | `--prompts-only` — no Veo charges |
| Single clip | `--only <clip_id>` |
| Regenerate signs | `./refresh-signs-clip.sh` |
| Add clip | `./generate-clip.sh` |

### 6.5 CLI equivalents

```bash
./script-to-clips.sh output/scripts/<file>.txt [--prompts-only]
./script-to-clips.sh --resume output/clips/<folder>
./make-video.sh "URL"    # blog → script → clips (no voiceover)
```

---

## 7. Voiceover requirements

| Field | Value |
|-------|-------|
| Script | `scripts/script_to_voiceover.py` |
| Model | `gemini-2.5-flash-preview-tts` |
| Default pace | `auto` — fit speech to total video length from `clips.json` |
| Pace options | `auto`, `slow`, `normal`, `fast`, `very_fast` |
| Output | `voiceover.wav`, `speech.txt`, `voiceover_meta.json` |

**Inputs:**

- `script.txt` — section labels stripped; only spoken lines read.
- `--clips-dir` — uses clip durations for target seconds (recommended after prompts exist).

**CLI:** `./script-to-voiceover.sh <script.txt> [--clips-dir <folder>]`

---

## 8. Modoc Studio — functional requirements

### 8.1 Project lifecycle

| Feature | Requirement |
|---------|-------------|
| New project | Paste blog URL + language → auto-runs Blog → Script |
| Open project | ⌘O or sidebar; accepts folder with `project.json`, `script.txt`, or `clips.json` |
| Legacy import | Folders under `output/clips/…` supported via manifest inference |
| Project list | Sorted by `created_at`; remembers opened paths in UserDefaults |

### 8.2 Project phases (`project.json`)

| Phase | Meaning |
|-------|---------|
| `creatingScript` | Script generation in progress |
| `scriptReview` | Script ready for review |
| `generatingPrompts` | Clip prompt step running |
| `promptsReview` | Prompts ready |
| `generatingVoiceover` | TTS running |
| `voiceoverReview` | Voiceover ready |
| `generatingVideos` | Veo running |
| `ready` | All clips + voiceover complete |
| `failed` | Last step failed; `last_error` set |

Phases are inferred from disk state when not actively running.

### 8.3 Workflow tab

Four pipeline steps, **runnable in any order** (each step checks its own inputs):

1. **Script** — Blog → Script (`blog_to_script.py`)
2. **Clip prompts** — `script_to_clips.py --prompts-only` + `derived_clips.py`
3. **Voiceover** — `script_to_voiceover.py`
4. **Video clips** — `script_to_clips.py --resume`

Additional:

- Live log during runs
- **Finalize** button — marks language complete for KPI; ends open manual-review timer
- Timing chips (automated vs manual review)

### 8.4 Detail tabs

| Tab | Purpose |
|-----|---------|
| Workflow | Run steps, finalize, timing |
| Graph | 3-lane version graph (EN / KO / ES) |
| Statistics | Per-language pipeline time breakdown |
| Script | Read generated script |
| Prompts | Decisions + clip prompt list |
| Voiceover | Play `voiceover.wav` |
| Clips | Gallery + inline AVPlayer preview; per-clip regenerate |
| Log | Current pipeline run output |

### 8.5 Clips tab

- Split view: clip list + video player (Auto Layout pinned).
- Regenerate single clip or all clips.
- Clip sort order: hook → body → explain → signs → relief → cta.

### 8.6 Workflow version graph

| Node kind | Meaning |
|-----------|---------|
| `script`, `prompts`, `voiceover`, `videos`, `clip` | Pipeline step runs |
| `complete` | Full milestone: script + clips JSON + voiceover + all videos |
| `revision` | Post-complete change; branches from tip as **Change:** nodes |

- Full snapshot on **complete** (script, prompts, clips, voiceover, videos, stats).
- Graph stored at `languages/{lang}/workflow_graph.json` (+ root mirror for active lang).
- Snapshots under `languages/{lang}/runs/<node-id>/`.

### 8.7 Pipeline time tracking (`pipeline_stats.json`)

Tracks per language:

| Event | Description |
|-------|-------------|
| `project_started` | Project opened / created |
| `language_started` | First work in a language |
| `language_switch` | EN ↔ KO ↔ ES switch |
| `automated_step` | Duration of each pipeline run |
| `manual_review` | Time between steps until next run or finalize |
| `finalized` | User clicked Finalize |

Statistics tab shows automated total, manual review total, and per-step breakdown.

### 8.8 Error handling

| Condition | Behavior |
|-----------|----------|
| Missing `.venv` | Error: “Run ./setup.sh” |
| Missing API key | Python exits 1; message in log |
| Pipeline exit ≠ 0 | Phase → `failed`; error in manifest + log |
| Veo safety filter | Retry once; RAI reason in log |

---

## 9. Data model & artifacts

### 9.1 Project folder (active language at root)

```
output/projects/<slug>-<timestamp>/
  project.json
  script.txt
  clip_decisions.txt
  clip_prompts.txt
  clips.json
  visual_cast.txt
  voiceover.wav
  speech.txt
  voiceover_meta.json
  pipeline.log
  pipeline_stats.json
  workflow_graph.json
  videos/
    hook.mp4
    body_1.mp4
    explain_1.mp4
    signs_1.mp4
    relief.mp4
    cta.mp4
  languages/
    en/ …
    ko/ …
    es/ …
```

### 9.2 `project.json`

```json
{
  "id": "slug-timestamp",
  "title": "…",
  "blog_url": "https://…",
  "created_at": "ISO8601",
  "phase": "scriptReview",
  "language": "en",
  "last_error": null
}
```

### 9.3 `clips.json` (per clip)

```json
{
  "clips": [
    {
      "id": "hook",
      "label": "HOOK CLIP",
      "detailed_prompt": "…",
      "veo_prompt": "…",
      "duration_seconds": 4,
      "script_line": "…"
    }
  ]
}
```

### 9.4 Legacy CLI output layout

Pre-Studio runs may live under:

```
output/scripts/
output/clips/<slug>-<time>/
output/voiceovers/<slug>-<time>/
```

Studio prefers `output/projects/` but can open legacy folders.

---

## 10. Shell scripts reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | venv + pip + create `.env` if missing |
| `test-api.sh` | API key validation |
| `test-video.sh` | Optional Veo test clip |
| `blog-to-script.sh` | Step 1 |
| `script-to-voiceover.sh` | Step 2 |
| `script-to-clips.sh` | Step 3 |
| `make-video.sh` | Blog → script → clips |
| `clear-outputs.sh` | Wipe `output/scripts`, `clips`, `voiceovers` (keeps `.env`) |
| `list-outputs.sh` | Show recent artifact paths |
| `generate-clip.sh` | Add/regenerate one clip type |
| `refresh-signs-clip.sh` | Rebuild all signs clips from script |
| `build-modoc-studio.sh` | Build + launch Modoc Studio.app |
| `modoc-studio.sh` | Launch wrapper |

---

## 11. External services

| Service | Use | Cost |
|---------|-----|------|
| Gemini text (`gemini-2.5-flash`) | Script, clip decisions, prompts | API usage |
| Gemini TTS (`gemini-2.5-flash-preview-tts`) | Voiceover | API usage |
| Veo (`veo-3.1-fast-generate-preview`) | Video clips | Paid; ~1–3 min/clip |
| Blog host (fevercoach.us) | Source articles | — |

---

## 12. Manual / out-of-scope (current)

| Item | Status |
|------|--------|
| Final video edit (timeline, captions, export) | **Manual** — CapCut, Premiere, etc. |
| Upload to YouTube / IG / FB / blog | **Manual** |
| Medical review workflow | **Manual** — tracked in KPI form |
| Platform view counts in app | **Not built** — manual weekly log ([KPI_RATING_FORM.md](./KPI_RATING_FORM.md)) |
| Automated publish | Future |
| Clip duration 7–10s | Discussed, not implemented |
| Settings UI for modocAI root | UserDefaults only |
| API key validation in Studio UI | `hasAPIKey` exists but unused |

---

## 13. Non-functional requirements

| Area | Requirement |
|------|-------------|
| **Security** | API key local only; `.env` gitignored |
| **Recoverability** | Resume video gen; workflow graph snapshots |
| **Portability** | Projects are self-contained folders |
| **Observability** | `pipeline.log` per project; Studio log tab |
| **Performance** | Veo bounded by Google API (~minutes per clip) |
| **Usability** | Launch as `.app` for proper keyboard focus |
| **Accuracy** | Prompts enforce blog-faithful scripts and clip decisions |

---

## 14. Acceptance criteria (end-to-end)

A project language is **complete** when:

- [ ] `script.txt` exists and passes medical review
- [ ] `clips.json` includes all required clip types (incl. EXPLAIN/SIGNS when script has them)
- [ ] `voiceover.wav` exists
- [ ] Every clip in `clips.json` has a valid `videos/<id>.mp4`
- [ ] User marks **Finalize** (KPI manual review closed)
- [ ] Manual edit + multi-platform publish (outside app)

---

## 15. Related documents

| Document | Contents |
|----------|----------|
| [README.md](../README.md) | Product overview, script rules, channel links |
| [WORKFLOW.md](../WORKFLOW.md) | Step-by-step CLI commands |
| [ModocStudio/README.md](../ModocStudio/README.md) | App build & run |
| [KPI_RATING_FORM.md](./KPI_RATING_FORM.md) | Weekly KPI logging form (EN/KO) |

---

## 16. Revision history

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | 2026-06-08 | Initial consolidated requirements (pipeline + Studio + KPI + i18n) |
