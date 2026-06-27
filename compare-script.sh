#!/usr/bin/env bash
# Compare script.txt to the original blog article via Gemini.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -lt 2 ]]; then
  echo "Usage: ./compare-script.sh <script.txt> <blog-url> [--output-dir PROJECT_FOLDER]"
  exit 1
fi

SCRIPT="$1"
URL="$2"
shift 2

exec .venv/bin/python scripts/compare_script_to_article.py "$SCRIPT" --url "$URL" "$@"
