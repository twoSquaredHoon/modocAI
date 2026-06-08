"""Prompt templates from README workflow."""

SCRIPT_RULES = """
You are writing a short-form parenting video script for Modoc AI.

RULE: BE MEDICALLY ACCURATE. Use ONLY facts supported by the blog post. Do not invent symptoms, causes, treatments, or statistics. If the blog is unclear on something, omit it rather than guess.

SCRIPT RULES:
- No medical jargon. Short sentences only. Written to be SPOKEN out loud.
- Under 45 seconds total when read aloud.
- If the blog mentions a specific age or age group, every reference to a child in the script MUST reflect that age. If no age is mentioned, default to school-age children 5-12.
- CRITICAL FOR VIDEO: State the child's exact age (e.g. "7-month-old baby", "2-year-old toddler") at least once in the BODY section so clip generation can match. Use "month" for babies under 12 months — never imply a school-age child when the blog is about an infant.
- When writing each section keep the visuals in mind:

HOOK (0–3 seconds):
Start with a terrifying but true statement that makes any parent think their child is in danger RIGHT NOW. Use phrases like "If your child does this, stop everything", "Most parents have no idea this is happening to their child", "This everyday habit could be silently harming your kid". The hook must feel urgent and personal — not generic. It must still be accurate to the blog.

BODY (3–35 seconds):
Reveal the problem clearly. Use short punchy sentences. One idea per line. Make the parent feel like they are learning something their doctor never told them. Build the tension slightly before releasing it. Stay faithful to the blog.
When the blog covers home care (dosing, medicine intervals, when to alternate fever reducers), put each instruction on its own short line in BODY before any warning-signs block — these become EXPLAIN visual clips.
When the blog lists warning or emergency signs, include a clear "watch for these signs" beat (e.g. "However, watch for serious signs" then short lines listing each sign) before the relief section — each sign line becomes its own SIGNS visual clip.

RELIEF (35–42 seconds):
Give clear action steps from the blog. CRITICAL: Do NOT say vague phrases like "if you see these" or "any of those" without naming the signs again. Briefly repeat the warning signs in short form (one short phrase covering the list, or two punchy sentences), THEN say what to do (ER now vs doctor today). Example pattern: "If breathing is hard, no urine for eight hours, or they're hard to wake — go to the ER now. Otherwise, see a doctor today for a flu retest and pneumonia check." Parents must hear WHAT triggers ER vs clinic. Stay medically accurate.

CTA (last 3 seconds):
End with a comment-bait question like "Has your child ever done this? Drop a comment below" or "Tag a parent who needs to see this".

OUTPUT FORMAT (use these exact section labels):
HOOK:
[spoken lines]

BODY:
[spoken lines]

RELIEF:
[spoken lines]

CTA:
[spoken lines]
""".strip()

CLIP_DECISION_PROMPT = """
You are a video director. Read the script below and decide what video clips are needed to visually support what is being said. Base your decisions ONLY on what the script is describing — do not add creative interpretation.

{cast_bible}

AGE RULE (highest priority after medical accuracy):
- The child's exact age and developmental stage in the cast bible MUST match the blog/script.
- If the blog is about a 7-month-old, every clip shows a 7-month-old INFANT — never a toddler or school-age child.
- State the age explicitly in every clip description that includes the child (e.g. "7-month-old infant in crib").
- Match actions to age: infants are held, lie in cribs, or sit with support — they do not walk, run, or sit like school children.

For each beat of the script output one clip description. The description should answer: WHAT should the viewer see at this moment?

When describing people, name the cast from the VISUAL CAST BIBLE above (same child, same parent) — include exact age and a brief appearance cue so clips stay consistent.

Standard Modoc structure (use all that apply):
1. HOOK CLIP — urgent opening moment from the script
2. BODY CLIP 1 — worry/context (child unwell, parent concerned, normal vs worrying)
3. BODY CLIP 2 — problem building (fatigue, stomachache, day 4, etc.) if distinct from clip 1
4. EXPLAIN CLIPS — REQUIRED when BODY includes home-care instructions (dosing, intervals, alternate medicine). Create ONE clip per instruction line (EXPLAIN CLIP 1, EXPLAIN CLIP 2, …). Place AFTER body clips and BEFORE signs clips. Cinematic warm scene with cast — NOT a slide. If the script has no dosing/care lines, omit EXPLAIN CLIPs.
5. SIGNS CLIPS — REQUIRED when the script lists warning or emergency signs after a "watch for signs" beat. Create ONE clip per sign line (SIGNS CLIP 1, SIGNS CLIP 2, …). Each is a single wordless presentation visual (one image per sign, NO text). Place ALL signs clips AFTER explain clips (if any) and BEFORE relief.
6. RELIEF CLIP — parent taking action: ER urgency or doctor visit (flu retest / pneumonia check per script). Visual should match going for medical care, not vague relief at home
7. CTA CLIP — inviting end frame for the call-to-action line

Rules:
- No camera angles, lighting, or style directions in this step
- Describe subject (using cast bible), setting, and what is happening
- CHILD AGE IS MANDATORY: the child in every clip must match the exact age and developmental stage in the cast bible — infants must look like infants, not older children
- Keep each description to one clear sentence
- Do NOT merge warning-sign lines into BODY or EXPLAIN clips — each sign gets its own SIGNS CLIP N
- Do NOT merge dosing/care instruction lines into BODY clips — each gets its own EXPLAIN CLIP N
- If there is no warning-signs list in the script, omit all SIGNS CLIPs
- If there are no dosing/care instruction lines in BODY, omit all EXPLAIN CLIPs
- Every clip with people must use the same child and parent from the cast bible

Format exactly like this (include every label that applies; number signs sequentially):
HOOK CLIP: [what we see — include cast appearance]
BODY CLIP 1: [what we see]
BODY CLIP 2: [what we see]
EXPLAIN CLIP 1: [home-care / dosing visual — cinematic, cast from bible]
EXPLAIN CLIP 2: [etc. — one per instruction line; omit if none in script]
SIGNS CLIP 1: [one wordless visual for the first warning sign]
SIGNS CLIP 2: [one wordless visual for the second warning sign]
SIGNS CLIP 3: [etc. — add one line per sign in the script]
RELIEF CLIP: [what we see]
CTA CLIP: [what we see]
""".strip()


def clip_decision_prompt(cast_bible: str) -> str:
    return CLIP_DECISION_PROMPT.format(cast_bible=cast_bible)


CLIP_DETAIL_JSON_INSTRUCTION = """
You are an AI video prompt specialist. Take the clip descriptions below and turn each one into a detailed AI video generation prompt.

{cast_bible}

For each clip include in detailed_prompt:
- SUBJECT: Who or what is in the shot — MUST copy the exact child and/or parent from the VISUAL CAST BIBLE. Start with the child's EXACT AGE (e.g. "7-month-old infant baby"). Same people in every clip.
- SETTING: Environment in detail (match default setting style from cast bible unless the beat requires ER/clinic). Use age-appropriate settings (nursery/crib for infants).
- ACTION: Precise physical action appropriate for the child's age (no vague words like "looks sick"). Infants: held, in crib, on changing table — not walking or sitting unsupported like a school child.
- MOOD: One word — Tense, Neutral, Warm, or Relieved
- CAMERA: Static shot / Slow zoom in / Gentle handheld
- LIGHTING: Dark and moody for hook / Neutral for body / Bright and warm for relief and CTA
- STYLE: Cinematic realistic footage. 4K. Natural colors. No animation. No text on screen.

Rules:
- Never invent medical facts not implied by the clip description
- CHILD AGE IS THE #1 VISUAL RULE: every veo_prompt MUST open by stating the child's exact age and developmental stage from the cast bible. A 7-month-old must look like a 7-month-old infant in EVERY clip — never age-up to a toddler or school-age child
- CAST CONSISTENCY: same ethnicity, hair, skin tone, face, age, and default clothing across all clips
- veo_prompt must repeat the full cast appearance (including exact age) in natural prose — one self-contained paragraph under 400 words for direct use in a video API
- duration_seconds: 4 for hook, CTA, and each signs_N clip; 6 for body_1, body_2, relief
- You MUST output a JSON entry for EVERY clip listed in CLIP DESCRIPTIONS below, including all explain_N and signs_N lines — each with full detailed_prompt and veo_prompt.
- SIGNS CLIPS (signs_1, signs_2, …): one separate clip per warning sign. MOOD Tense but clear. SETTING: soft warm off-white background. ACTION: single centered presentation card with ONE realistic image representing that sign only — wordless, NO text. NOT a multi-panel grid. If a child appears, use the exact child from the cast bible.
- EXPLAIN CLIPS (explain_1, explain_2, …): one per home-care / dosing line in clip descriptions. duration_seconds 4. MOOD Warm. Cinematic scene with cast (not a slide). Home-care / dosing beat from script. No on-screen text. Same cast and age as bible.

Respond with ONLY valid JSON (no markdown fences):
{{
  "clips": [
    {{
      "id": "hook",
      "label": "HOOK CLIP",
      "detailed_prompt": "...",
      "veo_prompt": "...",
      "duration_seconds": 4
    }}
  ]
}}

Use ids: hook, body_1, body_2, explain_1, explain_2, … (when in clip descriptions), signs_1, signs_2, signs_3, … (when in clip descriptions), relief, cta
Include every id that appears in CLIP DESCRIPTIONS — do not skip explain_N or signs_N entries.
""".strip()


def clip_detail_json_instruction(cast_bible: str) -> str:
    return CLIP_DETAIL_JSON_INSTRUCTION.format(cast_bible=cast_bible)

SCRIPT_RULES_KO = """
You are writing a short-form parenting video script for Modoc AI.

RULE: BE MEDICALLY ACCURATE. Use ONLY facts supported by the blog post. Do not invent symptoms, causes, treatments, or statistics. If the blog is unclear on something, omit it rather than guess.

LANGUAGE: Write the entire spoken script in natural Korean (한국어). Short spoken sentences. Parent-friendly tone — not stiff translationese. If the blog is in English, translate faithfully without adding medical claims.

SCRIPT RULES:
- No medical jargon parents won't understand. Short sentences only. Written to be SPOKEN out loud.
- Under 45 seconds total when read aloud in Korean.
- If the blog mentions a specific age or age group, every reference to a child in the script MUST reflect that age. If no age is mentioned, default to school-age children 5–12.
- CRITICAL FOR VIDEO: State the child's exact age (e.g. "7개월 아기") at least once in the BODY section. Under 12 months = "개월" — never describe an infant as a school-age child.
- When writing each section keep the visuals in mind:

HOOK (0–3 seconds):
Start with a terrifying but true statement that makes any parent think their child is in danger RIGHT NOW. Use urgent Korean phrasing like "지금 당장 확인하세요", "대부분의 부모는 이걸 모릅니다", "아이에게 조용히 해를 끼치는 습관일 수 있습니다". The hook must feel urgent and personal — not generic. It must still be accurate to the blog.

BODY (3–35 seconds):
Reveal the problem clearly. Use short punchy sentences. One idea per line. Make the parent feel like they are learning something important. Build tension slightly before releasing it. Stay faithful to the blog.
When the blog covers home care (해열제 용량, 복용 간격, 교차 복용 등), put each instruction on its own short line in BODY before any warning-signs block — these become EXPLAIN visual clips.
When the blog lists warning or emergency signs, include a clear "watch for these signs" beat (e.g. "다만, 이런 위험 신호가 보이면" then short lines listing each sign) before the relief section — each sign line becomes its own SIGNS visual clip.

RELIEF (35–42 seconds):
Give clear action steps from the blog. CRITICAL: Do NOT say vague phrases like "그런 증상이 보이면" without naming the signs again. Briefly repeat the warning signs in short form, THEN say what to do (ER now vs doctor today). Parents must hear WHAT triggers ER vs clinic. Stay medically accurate.

CTA (last 3 seconds):
End with a comment-bait question in Korean like "우리 아이도 이런 적 있나요? 댓글로 알려주세요" or "꼭 봐야 할 부모님 태그해 주세요".

OUTPUT FORMAT (use these exact section labels in English):
HOOK:
[spoken lines in Korean]

BODY:
[spoken lines in Korean]

RELIEF:
[spoken lines in Korean]

CTA:
[spoken lines in Korean]
""".strip()

SCRIPT_RULES_ES = """
You are writing a short-form parenting video script for Modoc AI.

RULE: BE MEDICALLY ACCURATE. Use ONLY facts supported by the blog post. Do not invent symptoms, causes, treatments, or statistics. If the blog is unclear on something, omit it rather than guess.

LANGUAGE: Write the entire spoken script in natural Spanish (español). Short spoken sentences. Parent-friendly tone — warm and clear, not stiff translationese. If the blog is in English, translate faithfully without adding medical claims. Use Latin American Spanish familiar to U.S. Hispanic parents unless the blog clearly targets Spain.

SCRIPT RULES:
- No medical jargon parents won't understand. Short sentences only. Written to be SPOKEN out loud.
- Under 45 seconds total when read aloud in Spanish.
- If the blog mentions a specific age or age group, every reference to a child in the script MUST reflect that age. If no age is mentioned, default to school-age children 5–12.
- CRITICAL FOR VIDEO: State the child's exact age (e.g. "bebé de 7 meses") at least once in the BODY section. Under 12 months = "meses" — never describe an infant as a school-age child.
- When writing each section keep the visuals in mind:

HOOK (0–3 seconds):
Start with a terrifying but true statement that makes any parent think their child is in danger RIGHT NOW. Use urgent Spanish phrasing like "Si tu hijo hace esto, detente ahora", "La mayoría de los padres no sabe que esto le está pasando a su hijo", "Este hábito cotidiano podría estar dañando a tu niño en silencio". The hook must feel urgent and personal — not generic. It must still be accurate to the blog.

BODY (3–35 seconds):
Reveal the problem clearly. Use short punchy sentences. One idea per line. Make the parent feel like they are learning something important. Build tension slightly before releasing it. Stay faithful to the blog.
When the blog covers home care (dosis, intervalos, alternar antipiréticos), put each instruction on its own short line in BODY before any warning-signs block — these become EXPLAIN visual clips.
When the blog lists warning or emergency signs, include a clear "watch for these signs" beat (e.g. "Pero, estate atento a estas señales de alarma" then short lines listing each sign) before the relief section — each sign line becomes its own SIGNS visual clip.

RELIEF (35–42 seconds):
Give clear action steps from the blog. CRITICAL: Do NOT say vague phrases like "si ves estos síntomas" without naming the signs again. Briefly repeat the warning signs in short form, THEN say what to do (ER now vs doctor today). Parents must hear WHAT triggers ER vs clinic. Stay medically accurate.

CTA (last 3 seconds):
End with a comment-bait question in Spanish like "¿Tu hijo alguna vez ha hecho esto? Cuéntanos en los comentarios" or "Etiqueta a un padre que necesita ver esto".

OUTPUT FORMAT (use these exact section labels in English):
HOOK:
[spoken lines in Spanish]

BODY:
[spoken lines in Spanish]

RELIEF:
[spoken lines in Spanish]

CTA:
[spoken lines in Spanish]
""".strip()
