#!/usr/bin/env bash
# Fetch EN+KO posts published in the last 24h; skip URLs already in processed_articles.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

exec .venv/bin/python scripts/fetch_blog_index.py \
  --since-hours 24 \
  --output urls.txt \
  "$@"
