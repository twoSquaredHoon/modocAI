"""Prompt templates from README workflow."""

SCRIPT_RULES = """
You are writing a short-form parenting video script for Modoc AI.

RULE: BE MEDICALLY ACCURATE. Use ONLY facts supported by the blog post. Do not invent symptoms, causes, treatments, or statistics. If the blog is unclear on something, omit it rather than guess.

SCRIPT RULES:
- No medical jargon. Short sentences only. Written to be SPOKEN out loud.
- Under 45 seconds total when read aloud.
- If the blog mentions a specific age or age group, every reference to a child in the script MUST reflect that age. If no age is mentioned, default to school-age children 5-12.
- When writing each section keep the visuals in mind:

HOOK (0–3 seconds):
Start with a terrifying but true statement that makes any parent think their child is in danger RIGHT NOW. Use phrases like "If your child does this, stop everything", "Most parents have no idea this is happening to their child", "This everyday habit could be silently harming your kid". The hook must feel urgent and personal — not generic. It must still be accurate to the blog.

BODY (3–35 seconds):
Reveal the problem clearly. Use short punchy sentences. One idea per line. Make the parent feel like they are learning something their doctor never told them. Build the tension slightly before releasing it. Stay faithful to the blog.

RELIEF (35–42 seconds):
Give the solution or reassurance clearly and confidently from the blog. They should feel relieved but also grateful they watched.

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
