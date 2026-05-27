"""Shared Gemini API helpers for modocAI scripts."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from google import genai

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def get_api_key() -> str:
    load_dotenv(PROJECT_ROOT / ".env")
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key or not key.strip():
        print(
            "Missing API key. Open .env in the project root and set:\n"
            "  GEMINI_API_KEY=your-key-here",
            file=sys.stderr,
        )
        sys.exit(1)
    return key.strip()


def get_client() -> genai.Client:
    return genai.Client(api_key=get_api_key())
