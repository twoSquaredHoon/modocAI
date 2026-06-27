#!/usr/bin/env bash
# Fetch the N newest posts per blog index (default: 1 EN + 1 KO). For testing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

exec .venv/bin/python scripts/fetch_blog_index.py \
  --latest 1 \
  --output urls.txt \
  "$@"
