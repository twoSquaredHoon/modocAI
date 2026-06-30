#!/usr/bin/env bash
# Resume an interrupted daily batch in output/projects/YYYY-MM-DD/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

DATE="${1:-$(date +%Y-%m-%d)}"
shift 2>/dev/null || true
BATCH_DIR="$ROOT/output/projects/$DATE"

if [[ ! -f "$BATCH_DIR/urls.txt" ]]; then
  echo "No urls.txt in $BATCH_DIR"
  echo "Usage: ./resume-batch.sh [YYYY-MM-DD]"
  exit 1
fi

export PYTHONUNBUFFERED=1
echo "Resuming batch in $BATCH_DIR"

BATCH_FLAGS=(--skip-voiceover --skip-videos)
if [[ -f "$BATCH_DIR/batch_pipeline_flags.txt" ]]; then
  read -r -a BATCH_FLAGS < "$BATCH_DIR/batch_pipeline_flags.txt"
fi

exec ./batch-run.sh "$BATCH_DIR/urls.txt" --projects-dir "$BATCH_DIR" --resume \
  "${BATCH_FLAGS[@]}" "$@"
