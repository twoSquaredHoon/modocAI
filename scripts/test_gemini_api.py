#!/usr/bin/env python3
"""Quick Gemini API key check for modocAI (text + optional Veo video)."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types

from gemini_util import get_client


def test_auth_and_models(client: genai.Client) -> list[str]:
    """List models; returns Veo model ids if the key is valid."""
    print("Checking API key (listing models)...")
    veo_models: list[str] = []
    count = 0
    for model in client.models.list():
        count += 1
        name = getattr(model, "name", "") or ""
        if "veo" in name.lower():
            veo_models.append(name)
    print(f"  OK — listed {count} models.")
    if veo_models:
        print("  Veo (video) models visible:")
        for m in sorted(veo_models)[:8]:
            print(f"    - {m}")
        if len(veo_models) > 8:
            print(f"    ... and {len(veo_models) - 8} more")
    else:
        print("  (No Veo models in list — video may still work if billing is enabled.)")
    return veo_models


def test_text(client: genai.Client) -> None:
    print("Checking text API (gemini-2.5-flash)...")
    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents="Reply with exactly: API key works",
        config=types.GenerateContentConfig(temperature=0),
    )
    text = (response.text or "").strip()
    print(f"  OK — model replied: {text[:80]}{'...' if len(text) > 80 else ''}")


def test_video(
    client: genai.Client,
    *,
    model: str,
    prompt: str,
    duration_seconds: int,
    output_dir: Path,
) -> Path:
    print()
    print("Starting Veo video generation (paid; often 1–3 minutes)...")
    print(f"  model: {model}")
    print(f"  prompt: {prompt!r}")
    operation = client.models.generate_videos(
        model=model,
        prompt=prompt,
        config=types.GenerateVideosConfig(
            number_of_videos=1,
            duration_seconds=duration_seconds,
        ),
    )
    poll_seconds = 15
    while not operation.done:
        print(f"  waiting... ({poll_seconds}s)")
        time.sleep(poll_seconds)
        operation = client.operations.get(operation)

    if operation.error:
        raise RuntimeError(f"Video generation failed: {operation.error}")

    generated = operation.response.generated_videos
    if not generated:
        raise RuntimeError("No video in response.")

    video = generated[0].video
    if video is None:
        raise RuntimeError("No video payload in response.")

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / "test_clip.mp4"

    if video.video_bytes:
        out_path.write_bytes(video.video_bytes)
    else:
        # Veo returns a remote file reference; download via Files API.
        data = client.files.download(file=video)
        out_path.write_bytes(data)

    print(f"  OK — saved to {out_path}")
    return out_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Test a Gemini API key (free text check; optional Veo video)."
    )
    parser.add_argument(
        "--video",
        action="store_true",
        help="Generate a short test clip (uses paid Veo quota).",
    )
    parser.add_argument(
        "--model",
        default="veo-3.1-fast-generate-preview",
        help="Veo model id (default: veo-3.1-fast-generate-preview).",
    )
    parser.add_argument(
        "--prompt",
        default="A parent gently helping a school-age child with homework at a kitchen table, warm daylight, cinematic.",
        help="Prompt for --video.",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=4,
        choices=[4, 6, 8],
        help="Clip length in seconds for --video (default: 4).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "output",
        help="Where to save test_clip.mp4 (default: ./output).",
    )
    args = parser.parse_args()

    client = get_client()
    print("Gemini API key test\n" + "=" * 40)

    try:
        test_auth_and_models(client)
        test_text(client)
        if args.video:
            test_video(
                client,
                model=args.model,
                prompt=args.prompt,
                duration_seconds=args.duration,
                output_dir=args.output_dir,
            )
        else:
            print()
            print("Text checks passed. To test video generation (paid):")
            print("  python scripts/test_gemini_api.py --video")
    except Exception as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)

    print("\nAll requested checks passed.")


if __name__ == "__main__":
    main()
