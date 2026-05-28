#!/usr/bin/env python3
"""Generate a voiceover WAV from a Modoc video script using Gemini TTS."""

from __future__ import annotations

import argparse
import re
import sys
import wave
from datetime import datetime
from pathlib import Path

from google.genai import types

from gemini_util import PROJECT_ROOT, get_client

DEFAULT_TTS_MODEL = "gemini-2.5-flash-preview-tts"
DEFAULT_VOICE = "Kore"
OUTPUT_BASE = PROJECT_ROOT / "output" / "voiceovers"
SECTION_HEADERS = frozenset({"HOOK", "BODY", "RELIEF", "CTA"})


def load_script(path: Path) -> str:
    lines: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        lines.append(line)
    text = "\n".join(lines).strip()
    if not text:
        raise ValueError(f"No script content in {path}")
    return text


def script_to_speech_text(script: str) -> str:
    """Strip section labels; keep only lines meant to be spoken."""
    speech_lines: list[str] = []
    for line in script.splitlines():
        stripped = line.strip()
        if not stripped:
            if speech_lines and speech_lines[-1] != "":
                speech_lines.append("")
            continue
        header = stripped.rstrip(":").upper()
        if header in SECTION_HEADERS:
            continue
        speech_lines.append(stripped)
    text = "\n".join(speech_lines).strip()
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


def build_tts_prompt(speech_text: str, *, pace: str) -> str:
    pace_hints = {
        "slow": "Speak slowly and clearly.",
        "normal": "Speak at a natural conversational pace.",
        "fast": "Speak at a slightly brisk but clear pace.",
    }
    pace_hint = pace_hints.get(pace, pace_hints["normal"])

    return (
        "Read the following parenting video script aloud for social media. "
        "Sound warm, calm, and trustworthy — like a doctor speaking to parents. "
        f"{pace_hint} "
        "The full read should finish in under 45 seconds. "
        "Read every line exactly; do not add or skip words.\n\n"
        f"{speech_text}"
    )


def save_pcm_as_wav(pcm: bytes, path: Path, *, rate: int = 24000) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(pcm)


def extract_pcm(response) -> bytes:
    candidates = response.candidates
    if not candidates or not candidates[0].content or not candidates[0].content.parts:
        raise RuntimeError("No audio in TTS response.")
    for part in candidates[0].content.parts:
        inline = part.inline_data
        if inline and inline.data:
            return inline.data
    raise RuntimeError("No audio data in TTS response.")


def generate_voiceover(
    client,
    *,
    speech_text: str,
    model: str,
    voice: str,
    pace: str,
) -> bytes:
    prompt = build_tts_prompt(speech_text, pace=pace)
    print(f"Generating voiceover ({model}, voice={voice})...")

    response = client.models.generate_content(
        model=model,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_modalities=["AUDIO"],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=voice,
                    )
                ),
                language_code="en-US",
            ),
        ),
    )
    return extract_pcm(response)


def output_dir_for_script(script_path: Path) -> Path:
    slug = script_path.stem[:50]
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    return OUTPUT_BASE / f"{slug}-{stamp}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate voiceover audio from a Modoc script file."
    )
    parser.add_argument("script", type=Path, help="Script .txt from blog-to-script")
    parser.add_argument(
        "--model",
        default=DEFAULT_TTS_MODEL,
        help=f"TTS model (default: {DEFAULT_TTS_MODEL})",
    )
    parser.add_argument(
        "--voice",
        default=DEFAULT_VOICE,
        help=f"Prebuilt voice name (default: {DEFAULT_VOICE})",
    )
    parser.add_argument(
        "--pace",
        choices=["slow", "normal", "fast"],
        default="normal",
        help="Speaking pace hint (default: normal)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output .wav path (default: output/voiceovers/<slug>-<time>/voiceover.wav)",
    )
    parser.add_argument(
        "--clips-dir",
        type=Path,
        help="Also save voiceover.wav into a clips run folder",
    )
    args = parser.parse_args()

    script_path = args.script.expanduser().resolve()
    if not script_path.is_file():
        print(f"Script not found: {script_path}", file=sys.stderr)
        sys.exit(1)

    out_wav = args.output
    if out_wav is None:
        out_dir = output_dir_for_script(script_path)
        out_wav = out_dir / "voiceover.wav"
    else:
        out_wav = out_wav.expanduser().resolve()

    if out_wav.exists() and out_wav.stat().st_size > 1000:
        print(f"Already exists: {out_wav}")
        if args.clips_dir:
            clips_copy = args.clips_dir.expanduser().resolve() / "voiceover.wav"
            clips_copy.parent.mkdir(parents=True, exist_ok=True)
            clips_copy.write_bytes(out_wav.read_bytes())
            print(f"Copied to {clips_copy}")
        return

    try:
        script = load_script(script_path)
        speech_text = script_to_speech_text(script)
        if not speech_text:
            raise ValueError("No spoken lines found in script.")

        out_wav.parent.mkdir(parents=True, exist_ok=True)
        (out_wav.parent / "speech.txt").write_text(speech_text + "\n", encoding="utf-8")
        print(f"  {len(speech_text.split())} words to speak")

        client = get_client()
        pcm = generate_voiceover(
            client,
            speech_text=speech_text,
            model=args.model,
            voice=args.voice,
            pace=args.pace,
        )
        save_pcm_as_wav(pcm, out_wav)
        print(f"Saved → {out_wav}")

        if args.clips_dir:
            clips_copy = args.clips_dir.expanduser().resolve() / "voiceover.wav"
            clips_copy.parent.mkdir(parents=True, exist_ok=True)
            save_pcm_as_wav(pcm, clips_copy)
            print(f"Also saved → {clips_copy}")

    except Exception as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
