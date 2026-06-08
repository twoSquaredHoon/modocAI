"""Language settings for script generation and TTS."""

from __future__ import annotations

from dataclasses import dataclass

from prompts import SCRIPT_RULES, SCRIPT_RULES_ES, SCRIPT_RULES_KO

SUPPORTED_LANGUAGES = frozenset({"en", "ko", "es"})


@dataclass(frozen=True)
class LanguageSettings:
    code: str
    label: str
    script_rules: str
    script_system: str
    tts_language_code: str
    tts_voice: str
    uses_syllable_pacing: bool


LANGUAGES: dict[str, LanguageSettings] = {
    "en": LanguageSettings(
        code="en",
        label="English",
        script_rules=SCRIPT_RULES,
        script_system=(
            "You turn parenting blog posts into short spoken video scripts. "
            "Medical accuracy is mandatory; never add claims not in the source. "
            "Write the script in English."
        ),
        tts_language_code="en-US",
        tts_voice="Charon",
        uses_syllable_pacing=False,
    ),
    "ko": LanguageSettings(
        code="ko",
        label="Korean",
        script_rules=SCRIPT_RULES_KO,
        script_system=(
            "You turn parenting blog posts into short spoken video scripts. "
            "Medical accuracy is mandatory; never add claims not in the source. "
            "Write the entire spoken script in natural Korean (한국어). "
            "If the blog is in English, translate faithfully — do not add medical claims."
        ),
        tts_language_code="ko-KR",
        tts_voice="Kore",
        uses_syllable_pacing=True,
    ),
    "es": LanguageSettings(
        code="es",
        label="Spanish",
        script_rules=SCRIPT_RULES_ES,
        script_system=(
            "You turn parenting blog posts into short spoken video scripts. "
            "Medical accuracy is mandatory; never add claims not in the source. "
            "Write the entire spoken script in natural Spanish (español). "
            "If the blog is in English, translate faithfully — do not add medical claims."
        ),
        tts_language_code="es-US",
        tts_voice="Aoede",
        uses_syllable_pacing=False,
    ),
}


def normalize_language(code: str | None) -> str:
    if not code:
        return "en"
    key = code.strip().lower().replace("_", "-")
    if key in ("ko", "ko-kr", "kr"):
        return "ko"
    if key in ("es", "es-es", "es-us", "es-mx", "es-419", "spanish"):
        return "es"
    if key in ("en", "en-us", "en-gb"):
        return "en"
    if key in SUPPORTED_LANGUAGES:
        return key
    raise ValueError(f"Unsupported language {code!r}. Use: en, ko, es")


def get_language(code: str | None) -> LanguageSettings:
    return LANGUAGES[normalize_language(code)]
