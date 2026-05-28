#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

if ! grep -qE '^GEMINI_API_KEY=.+' .env 2>/dev/null; then
  echo "Add your API key to .env:"
  echo "  GEMINI_API_KEY=paste-your-key-here"
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage:"
  echo "  ./script-to-clips.sh <script.txt>"
  echo "  ./script-to-clips.sh --resume output/clips/your-run-folder"
  echo ""
  echo "Re-run the same script path to auto-continue an incomplete run."
  exit 1
fi

.venv/bin/python scripts/script_to_clips.py "$@"
