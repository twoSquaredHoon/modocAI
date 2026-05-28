"""Generate and download Veo videos via the Gemini API."""

from __future__ import annotations

import time
from pathlib import Path

from google import genai
from google.genai import types


def _video_generation_error(operation) -> str:
    response = operation.response
    msg = "No video in response."
    if response is None:
        return msg
    filtered = getattr(response, "rai_media_filtered_count", None)
    reasons = getattr(response, "rai_media_filtered_reasons", None)
    if filtered:
        msg += f" Content may have been blocked by safety filters."
        if reasons:
            msg += f" Reasons: {reasons}"
    return msg


def generate_video(
    client: genai.Client,
    *,
    model: str,
    prompt: str,
    output_path: Path,
    duration_seconds: int = 6,
    poll_seconds: int = 15,
    max_attempts: int = 2,
) -> Path:
    """Generate one clip and save to output_path."""
    last_error: Exception | None = None

    for attempt in range(1, max_attempts + 1):
        if attempt > 1:
            print(f"    retry {attempt}/{max_attempts}...")

        operation = client.models.generate_videos(
            model=model,
            prompt=prompt,
            config=types.GenerateVideosConfig(
                number_of_videos=1,
                duration_seconds=duration_seconds,
            ),
        )

        while not operation.done:
            time.sleep(poll_seconds)
            operation = client.operations.get(operation)

        if operation.error:
            last_error = RuntimeError(f"Video generation failed: {operation.error}")
            continue

        generated = operation.response.generated_videos if operation.response else None
        if not generated or generated[0].video is None:
            last_error = RuntimeError(_video_generation_error(operation))
            continue

        video = generated[0].video
        output_path.parent.mkdir(parents=True, exist_ok=True)

        if video.video_bytes:
            output_path.write_bytes(video.video_bytes)
        else:
            data = client.files.download(file=video)
            output_path.write_bytes(data)

        return output_path

    assert last_error is not None
    raise last_error
