**Modoc AI (Main project):** Decrease concern of parents

**Parenting Laboratory (the project that we are working on):**
Send parenting information of young children in short form videos
**Task:**
Create medically accurate videos with the least amount of effort

**Measure:**
(Views) / (work time)
Rule: BE MEDICALLY ACCURATE nothing else.

**Channel**
Youtube: [https://www.youtube.com/channel/UCMWz3D-NhAVQyxGvbRZTblw](https://www.youtube.com/channel/UCMWz3D-NhAVQyxGvbRZTblw)
Instagram
Facebook
Blog imbed

**Workflow**

See **[WORKFLOW.md](WORKFLOW.md)** for step-by-step commands (setup, script, voiceover, clips, resume).

1. Copy the blog post, make the script

**Automated (blog URL → script):** Paste your Gemini API key in `.env`, then run:
```bash
./setup.sh   # once
./blog-to-script.sh "https://your-blog-post-url"
```
Saves to `output/scripts/`. Uses the script rules below via Gemini.

**Manual prompt (paste blog text into Gemini/Chat):**
```
**SCRIPT RULES:**
_No medical jargon. Short sentences only. Written to be SPOKEN out loud. Under 45 seconds total when read aloud._

_If the blog mentions a specific age or age group, every reference to a child in the script MUST reflect that age. If no age is mentioned, default to school age children 5-12._

_When writing each section keep the visuals in mind:_
- _HOOK (0–3 seconds): Start with a terrifying but true statement that makes any parent think their child is in danger RIGHT NOW. Use phrases like 'If your child does this, stop everything', 'Most parents have no idea this is happening to their child', 'This everyday habit could be silently harming your kid'. The hook must feel urgent and personal — not generic._
- _BODY (3–35 seconds): Reveal the problem clearly. Use short punchy sentences. One idea per line. Make the parent feel like they are learning something their doctor never told them. Build the tension slightly before releasing it._
- _RELIEF (35–42 seconds): Briefly name the warning signs again in short form, then clear action — ER if those signs, otherwise doctor today. Do not say "if you see these" without listing what "these" are._
- _CTA (last 3 seconds): End with a comment-bait question like 'Has your child ever done this? Drop a comment below' or 'Tag a parent who needs to see this'._
```

2. Voiceover (script → audio)

**Automated (Gemini TTS, same API key in `.env`):** Pace defaults to **auto** — speeds up speech to match total video length.
```bash
./script-to-voiceover.sh output/scripts/your-script-20260527.txt
```
Best with clip timings: `--clips-dir output/clips/your-run-folder` (after `--prompts-only` or full clips run).

**Manual:** [AI Studio speech](https://aistudio.google.com/generate-speech) — paste script, adjust speed under 1 minute.

3. Clips prompts
- **STEP 1 — Clip decision prompt** Feed the script in and it decides what clips are needed based purely on what the script is saying. No visual rules yet, just "what should we see here."
```
 "You are a video director. Read the script below and decide what video clips are needed to visually support what is being said. Base your decisions ONLY on what the script is describing — do not add creative interpretation.
For each section of the script output one clip description. The description should answer only one question: WHAT should the viewer see at this moment?
Rules: No camera angles No lighting instructions No style directions Just describe the subject, the setting, and what is happening If the script mentions a specific age, the clip must reflect that age_ Keep each description to one clear sentence

_Format it as:_ _HOOK CLIP_ → _BODY CLIP 1_ → _BODY CLIP 2_ → _SIGNS CLIP_ (“look for these signs” / warning list) → _RELIEF CLIP_ → _CTA CLIP_
```


**STEP 2 — Clip description prompt** Take those decided clips and turn them into very specific detailed prompts ready to paste into Runway or Kling.
```
_"You are an AI video prompt specialist. Take the clip descriptions below and turn each one into a detailed AI video generation prompt ready to paste into Runway or Kling._

_Every prompt must include:_

_SUBJECT: Who or what is in the shot. Be very specific — include age, appearance, clothing, expression, and body language._

_SETTING: Where exactly is this happening. Describe the environment in detail — room size, objects visible, background details._

_ACTION: What is physically happening in the shot. Be precise — not 'child looks sick' but 'child lying on couch eyes half closed head resting on pillow blanket pulled up to chin'_

_MOOD: One word only — Tense, Neutral, Warm, Relieved_

_CAMERA: Static shot / Slow zoom in / Gentle handheld_

_LIGHTING: Dark and moody for hook / Neutral for body / Bright and warm for relief and CTA_

_STYLE: Cinematic realistic footage. 4K. Natural colors. No animation. No text on screen._

_Rules:- Never use vague words like "looks sick" or "seems worried" — describe exact physical details
- If a child is mentioned, include exact age range
- Each prompt must be self-contained and ready to paste directly into Runway or Kling with no editing
- Keep it under 480 tokens (~360 words / 3-4 sentences)

_Clip descriptions: [paste Step 1 output here]"_
```


**STEP 3 — You generate the clips**

**Automated (script → prompts → Veo clips):**
```bash
./script-to-clips.sh output/scripts/your-script-20260527.txt
```
Writes `output/clips/<name>/` with `clip_decisions.txt`, `clip_prompts.txt`, and `videos/*.mp4`.

Preview prompts only (no Veo charges):
```bash
./script-to-clips.sh output/scripts/your-script-20260527.txt --prompts-only
```

If generation stops partway, resume (skips clips already saved):
```bash
./script-to-clips.sh --resume output/clips/your-run-folder
# or re-run the same script path — it auto-continues the latest incomplete run
./script-to-clips.sh output/scripts/your-script-20260527.txt
```

**Full pipeline (blog URL → script → clips):**
```bash
./make-video.sh "https://your-blog-post-url"
```

**Manual:** Paste Step 1 output into Step 2, then generate in Runway/Kling.
