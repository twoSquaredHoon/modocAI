# Modoc AI — Video pipeline commands

Rule for every step: **be medically accurate**. Scripts and clips must match the blog, not invent facts.

---

## Start a new video (clear old outputs)

```bash
./clear-outputs.sh
# or skip confirmation:
./clear-outputs.sh --yes
```

Removes all files under `output/scripts/`, `output/clips/`, and `output/voiceovers/`. Does **not** delete `.env` or your API key.

---

## One-time setup

1. Get a Gemini API key: https://aistudio.google.com/apikey  
   (Veo video needs billing enabled on your Google account.)

2. In the project folder, add your key to `.env`:
   ```
   GEMINI_API_KEY=your-key-here
   ```

3. Install dependencies (once per machine):
   ```bash
   cd /Users/seunghoon/Documents/2.Area/modocAI
   ./setup.sh
   ```

4. Optional — verify the API key:
   ```bash
   ./test-api.sh              # text + list models (free)
   ./test-video.sh            # one short Veo test clip (paid)
   ```

---

## Step 1 — Blog → script

**What it does:** Reads the blog URL, extracts the article, writes a short spoken script (HOOK / BODY / RELIEF / CTA).

**Command:**
```bash
./blog-to-script.sh "https://your-blog-post-url"
```

**Output:** `output/scripts/<slug>-<date>.txt`

**Example:**
```bash
./blog-to-script.sh "https://www.fevercoach.us/post/q-my-6-year-old-has-gastroenteritis-but-is-getting-more-lethargic-and-complaining-of-stomachaches"
```

---

## Step 2 — Script → voiceover

**What it does:** Turns the script into a `.wav` voiceover (Gemini TTS). Strips section labels; only spoken lines are read. **Pace is automatic by default** — it speeds up speech to fit your total video length.

**List your real file paths** (do not copy placeholder names like `your-script.txt`):
```bash
./list-outputs.sh
# or:  ls output/scripts/    ls output/clips/
```

**Command** (use the `.txt` filename you see in `output/scripts/`):
```bash
./script-to-voiceover.sh output/scripts/q-my-6-year-old-has-gastroenteritis-but-is-getting-more-leth-20260527.txt
```

**Best timing — pass your clips folder** (uses `clips.json` durations, e.g. 4+6+6+6+4 = 26s):
```bash
# After prompts exist (even before Veo finishes):
./script-to-clips.sh output/scripts/q-my-6-year-old-has-gastroenteritis-but-is-getting-more-leth-20260527.txt --prompts-only
./script-to-voiceover.sh output/scripts/q-my-6-year-old-has-gastroenteritis-but-is-getting-more-leth-20260527.txt \
  --clips-dir output/clips/q-my-6-year-old-has-gastroenteritis-but-is-getting-20260527-2257
```
Replace the clips folder with the one `list-outputs.sh` shows (timestamp may differ).

**Output:**
- `output/voiceovers/<slug>-<time>/voiceover.wav`
- `output/voiceovers/<slug>-<time>/speech.txt`
- `output/voiceovers/<slug>-<time>/voiceover_meta.json` — target vs actual seconds

**Options:**
```bash
--pace auto|slow|normal|fast|very_fast   # default: auto (faster when video is short)
--target-seconds 28                      # override total video length
--voice Kore
--model gemini-2.5-flash-preview-tts
```

**Manual alternative:** https://aistudio.google.com/generate-speech — paste script, keep total under ~1 minute.

---

## Step 3 — Script → clip prompts → Veo videos

**What it does:**
1. Decides what to show per section (HOOK, BODY clips, RELIEF, CTA)
2. Writes detailed video prompts
3. Generates each clip with Veo (paid; ~1–3 min per clip)

**Command:**
```bash
./script-to-clips.sh output/scripts/your-script-file.txt
```

**Output folder:** `output/clips/<slug>-<time>/`
- `clip_decisions.txt` — what each clip should show
- `clip_prompts.txt` — full prompts (human-readable)
- `clips.json` — prompts for resume / API
- `videos/hook.mp4`, `videos/body_1.mp4`, …

**Prompts only (no Veo cost):**
```bash
./script-to-clips.sh output/scripts/your-script-file.txt --prompts-only
```

**If generation stops partway — resume** (skips clips already saved):
```bash
./script-to-clips.sh --resume output/clips/your-clips-run-folder
```
Or run the same script path again; it auto-continues the latest incomplete run:
```bash
./script-to-clips.sh output/scripts/your-script-file.txt
```

**Add one new clip** (e.g. SIGNS) to a run that already has other `.mp4` files:
```bash
./generate-clip.sh signs output/clips/PROMPTS_FOLDER output/clips/VIDEOS_FOLDER
```

**SIGNS clips = one file per warning sign** (`signs_1.mp4`, `signs_2.mp4`, … — edit separately). Rebuild + regenerate all:
```bash
./refresh-signs-clip.sh output/clips/YOUR_CLIPS_FOLDER output/scripts/YOUR_SCRIPT.txt
```
Count adjusts automatically from the script (usually 3–6 signs).

---

## Full run (copy-paste template)

> **Do not** use literal names like `your-script.txt` or `your-clips-run-folder` — those are placeholders. Run `./list-outputs.sh` and paste your real paths.

```bash
cd /Users/seunghoon/Documents/2.Area/modocAI

# 1 — Script
./blog-to-script.sh "https://your-blog-post-url"
./list-outputs.sh   # copy the script path shown

# 2 — Clip prompts (fast; needed for accurate voiceover timing)
./script-to-clips.sh output/scripts/<paste-your-script>.txt --prompts-only
./list-outputs.sh   # copy the clips folder shown

# 3 — Voiceover (timed to clip lengths)
./script-to-voiceover.sh output/scripts/<paste-your-script>.txt \
  --clips-dir output/clips/<paste-your-clips-folder>

# 4 — Generate Veo clips (long; paid)
./script-to-clips.sh output/scripts/<paste-your-script>.txt
# or: ./script-to-clips.sh --resume output/clips/<paste-your-clips-folder>
```

**Blog → script → clips only** (skips voiceover):
```bash
./make-video.sh "BLOG_URL"
```
Then run voiceover separately if needed.

---

## Step 4 — Edit (manual, not automated yet)

1. Import `voiceover.wav` and all `videos/*.mp4` into your editor (CapCut, Premiere, etc.).
2. Align clips to the voiceover (HOOK first, then BODY, RELIEF, CTA).
3. Export for YouTube / Instagram / Facebook.

---

## Quick reference

| Step | Command |
|------|---------|
| Setup | `./setup.sh` |
| Test key | `./test-api.sh` |
| 1 Script | `./blog-to-script.sh "URL"` |
| 2 Voice | `./script-to-voiceover.sh output/scripts/….txt` |
| 3 Clips | `./script-to-clips.sh output/scripts/….txt` |
| Resume clips | `./script-to-clips.sh --resume output/clips/…` |
| Blog → clips | `./make-video.sh "URL"` |

---

## Output folders

```
output/
  scripts/       # .txt scripts from blogs
  voiceovers/    # .wav + speech.txt
  clips/         # prompts + videos/*.mp4 per run
```

`.env` is never committed (API key stays local).
