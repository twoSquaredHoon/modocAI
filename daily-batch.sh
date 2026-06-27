#!/usr/bin/env bash
# Nightly job: fetch today's new EN+KO articles, then run the full pipeline on each.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

echo "=== Fetch recent blog URLs ==="
./fetch-daily-urls.sh "$@"

if [[ ! -s urls.txt ]] || ! grep -qE '^https?://' urls.txt; then
  echo "No new URLs to process. Exiting."
  exit 0
fi

echo ""
echo "=== Run batch pipeline ==="
./batch-run.sh urls.txt "$@"
