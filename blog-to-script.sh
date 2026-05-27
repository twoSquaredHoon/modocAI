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
  echo "Usage: ./blog-to-script.sh <blog-url>"
  echo "Example: ./blog-to-script.sh https://example.com/your-post"
  exit 1
fi

.venv/bin/python scripts/blog_to_script.py "$@"
