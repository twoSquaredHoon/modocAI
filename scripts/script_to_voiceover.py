#!/usr/bin/env python3
"""Generate a voiceover WAV from a Modoc video script using Gemini TTS."""

from __future__ import annotations

import argparse
import json
import re
import sys
import wave
from datetime import datetime
from pathlib import Path

from google.genai import types

from gemini_util import PROJECT_ROOT, get_client
from path_hints import format_clips_dir_not_found, format_script_not_found

DEFAULT_TTS_MODEL = "gemini-2.5-flash-preview-tts"
DEFAULT_VOICE = "Kore"
OUTPUT_BASE = PROJECT_ROOT / "output" / "voiceovers"
SECTION_HEADERS = frozenset({"HOOK", "BODY", "RELIEF", "CTA"})
# Typical Veo clip lengths used by script_to_clips (seconds per clip type).
DEFAULT_CLIP_SECONDS = {
    "hook": 4,
    "body": 6,
    "signs": 6,
    "relief": 6,
    "cta": 4,
}
WPM_REFERENCE = {"slow": 130, "normal": 150, "fast": 175, "very_fast": 205}
PACE_ORDER = ["slow", "normal", "fast", "very_fast"]


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


def load_video_duration_from_clips(clips_dir: Path) -> int | None:
    """Sum duration_seconds from clips.json if present."""
    clips_json = clips_dir / "clips.json"
    if not clips_json.is_file():
        return None
    data = json.loads(clips_json.read_text(encoding="utf-8"))
    clips = data.get("clips")
    if not isinstance(clips, list) or not clips:
        return None
    total = 0
    for clip in clips:
        duration = int(clip.get("duration_seconds", 6))
        if duration in (4, 6, 8):
            total += duration
        else:
            total += 6
    return total


def estimate_video_seconds(speech_text: str) -> int:
    """Estimate total video length when clips.json is not available yet."""
    words = len(speech_text.split())
    lines = [line for line in speech_text.splitlines() if line.strip()]
    # Roughly hook + 1–2 body beats + relief + cta (4–5 clips at 4–6s each).
    clip_count = min(6, max(4, 3 + len(lines) // 5))
    sign_lines = len(
        [
            ln
            for ln in speech_text.splitlines()
            if ln.strip()
            and re.search(
                r"urinat|dry lip|belly|wake|no tear|diaper|stomach",
                ln,
                re.I,
            )
        ]
    )
    from_clips = (
        DEFAULT_CLIP_SECONDS["hook"]
        + DEFAULT_CLIP_SECONDS["relief"]
        + DEFAULT_CLIP_SECONDS["cta"]
        + max(1, clip_count - 4) * DEFAULT_CLIP_SECONDS["body"]
        + sign_lines * DEFAULT_CLIP_SECONDS["signs"]
    )
    # Shorter scripts → shorter videos; cap near social length.
    from_words = max(22, min(36, int(words * 0.32)))
    return min(from_clips, from_words)


def resolve_target_seconds(
    speech_text: str,
    *,
    clips_dir: Path | None,
    target_seconds: int | None,
) -> int:
    if target_seconds is not None:
        return max(15, target_seconds)
    if clips_dir is not None:
        from_clips = load_video_duration_from_clips(clips_dir)
        if from_clips:
            return from_clips
    return estimate_video_seconds(speech_text)


def pick_pace_for_target(word_count: int, target_seconds: float) -> str:
    """Choose pace so estimated read time fits the video (biased slightly fast)."""
    if word_count <= 0 or target_seconds <= 0:
        return "fast"
    wpm_needed = (word_count / target_seconds) * 60
    if wpm_needed >= WPM_REFERENCE["fast"] + 12:
        return "very_fast"
    if wpm_needed >= WPM_REFERENCE["normal"] + 10:
        return "fast"
    if wpm_needed >= WPM_REFERENCE["slow"] + 8:
        return "normal"
    return "slow"


def faster_pace(pace: str) -> str | None:
    try:
        idx = PACE_ORDER.index(pace)
    except ValueError:
        return "fast"
    if idx >= len(PACE_ORDER) - 1:
        return None
    return PACE_ORDER[idx + 1]


def build_tts_prompt(
    speech_text: str,
    *,
    pace: str,
    target_seconds: float,
) -> str:
    pace_hints = {
        "slow": "Speak slowly and clearly.",
        "normal": "Speak at a steady conversational pace.",
        "fast": (
            "Speak at a brisk, clear pace — typical for a short social media video. "
            "Keep energy up without sounding rushed or sloppy."
        ),
        "very_fast": (
            "Speak noticeably faster with tight pacing, as in a 30-second Reels or TikTok "
            "voiceover. Every word must stay clear, but minimize pauses between sentences."
        ),
    }
    pace_hint = pace_hints.get(pace, pace_hints["fast"])
    target_int = max(15, int(round(target_seconds)))

    return (
        "Read the following parenting video script aloud for social media. "
        "Sound warm, calm, and trustworthy — like a doctor speaking to parents. "
        f"{pace_hint} "
        f"IMPORTANT: The entire script must finish in about {target_int} seconds "
        f"to match the video length ({target_int}s of footage). "
        "Read every line exactly; do not add or skip words.\n\n"
        f"{speech_text}"
    )


def pcm_duration_seconds(pcm: bytes, *, rate: int = 24000, sample_width: int = 2) -> float:
    return len(pcm) / (rate * sample_width)


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
    target_seconds: float,
) -> bytes:
    prompt = build_tts_prompt(
        speech_text, pace=pace, target_seconds=target_seconds
    )
    print(f"Generating voiceover ({model}, voice={voice}, pace={pace})...")

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
        choices=["auto", "slow", "normal", "fast", "very_fast"],
        default="auto",
        help=(
            "Speaking pace (default: auto — fits voiceover to video length from "
            "--clips-dir, --target-seconds, or an estimate)"
        ),
    )
    parser.add_argument(
        "--target-seconds",
        type=int,
        metavar="SEC",
        help="Total video duration to match (overrides clip sum / estimate)",
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
        print(format_script_not_found(script_path), file=sys.stderr)
        sys.exit(1)

    if args.clips_dir:
        clips_path_check = args.clips_dir.expanduser().resolve()
        if not clips_path_check.is_dir():
            print(format_clips_dir_not_found(clips_path_check), file=sys.stderr)
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

        word_count = len(speech_text.split())
        clips_path = args.clips_dir.expanduser().resolve() if args.clips_dir else None
        video_seconds = resolve_target_seconds(
            speech_text,
            clips_dir=clips_path,
            target_seconds=args.target_seconds,
        )
        # Aim slightly under video length so edit has room for clip transitions.
        speak_target = video_seconds * 0.93

        if args.pace == "auto":
            pace = pick_pace_for_target(word_count, speak_target)
        else:
            pace = args.pace

        wpm_est = (word_count / speak_target) * 60 if speak_target else 0
        print(f"  {word_count} words | video ~{video_seconds}s | target voice ~{speak_target:.0f}s")
        print(f"  pace: {pace} (~{wpm_est:.0f} wpm needed)")

        client = get_client()
        pcm = generate_voiceover(
            client,
            speech_text=speech_text,
            model=args.model,
            voice=args.voice,
            pace=pace,
            target_seconds=speak_target,
        )

        duration = pcm_duration_seconds(pcm)
        if duration > video_seconds * 1.08:
            faster = faster_pace(pace)
            if faster:
                print(
                    f"  Voiceover is {duration:.1f}s (over {video_seconds}s video); "
                    f"retrying with {faster}..."
                )
                pace = faster
                pcm = generate_voiceover(
                    client,
                    speech_text=speech_text,
                    model=args.model,
                    voice=args.voice,
                    pace=pace,
                    target_seconds=speak_target * 0.9,
                )
                duration = pcm_duration_seconds(pcm)

        save_pcm_as_wav(pcm, out_wav)
        print(f"Saved → {out_wav} ({duration:.1f}s audio, {video_seconds}s video)")

        meta = {
            "word_count": word_count,
            "video_seconds": video_seconds,
            "speak_target_seconds": round(speak_target, 1),
            "audio_seconds": round(duration, 1),
            "pace": pace,
        }
        (out_wav.parent / "voiceover_meta.json").write_text(
            json.dumps(meta, indent=2) + "\n", encoding="utf-8"
        )
        if duration > video_seconds * 1.05:
            print(
                f"  Note: audio is still longer than video — use --pace very_fast "
                f"or shorten the script.",
                file=sys.stderr,
            )

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
