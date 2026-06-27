#!/usr/bin/env bash
# Run the full pipeline sequentially for each URL in a list (overnight batch).
# Projects land in output/projects/ — open them in Modoc Studio to review and edit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

if ! grep -qE '^GEMINI_API_KEY=.+' .env 2>/dev/null; then
  echo "Add GEMINI_API_KEY to .env before running batch jobs."
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: ./batch-run.sh <urls.txt> [options passed to batch_pipeline.py]"
  echo ""
  echo "  urls.txt — one blog URL per line (# comments OK)"
  echo "             optional: url,language   e.g. https://...,ko"
  echo ""
  echo "Examples:"
  echo "  ./batch-run.sh urls.txt"
  echo "  ./batch-run.sh urls.txt --limit 5"
  echo "  ./batch-run.sh urls.txt --skip-videos"
  echo ""
  echo "Logs: output/batch/batch-<timestamp>.log"
  exit 1
fi

URLS_FILE=$1
shift

exec .venv/bin/python scripts/batch_pipeline.py "$URLS_FILE" "$@"
