#!/usr/bin/env bash
# Test helper: fetch the single newest English post and run the full pipeline on it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

echo "=== Fetch 1 newest EN post ==="
./fetch-latest.sh --en-only --output urls.txt "$@"

if [[ ! -s urls.txt ]] || ! grep -qE '^https?://' urls.txt; then
  echo "No URL to process (may already be in processed_articles.json)."
  echo "Try: ./fetch-latest.sh --en-only --include-processed"
  exit 0
fi

echo ""
echo "=== Run pipeline (1 article) ==="
./batch-run.sh urls.txt --limit 1 "$@"
