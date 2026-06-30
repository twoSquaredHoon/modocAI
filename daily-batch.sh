#!/usr/bin/env bash
# Daily batch: EN + KO posts from the last 24 hours → output/projects/YYYY-MM-DD/
# Pipeline stops after scripts and clip prompts (no voiceover or Veo videos).
# Skips URLs already in processed_articles.json.
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

DATE=$(date +%Y-%m-%d)
BATCH_DIR="$ROOT/output/projects/$DATE"
mkdir -p "$BATCH_DIR"
export PYTHONUNBUFFERED=1

cleanup() {
  .venv/bin/python -c "
import sys
sys.path.insert(0, 'scripts')
from pathlib import Path
from batch_state import clear_pid
clear_pid(Path('$BATCH_DIR'))
" 2>/dev/null || true
}
trap cleanup EXIT

.venv/bin/python -c "
import sys, os
sys.path.insert(0, 'scripts')
from pathlib import Path
from batch_state import mark_fetching, write_pid
batch = Path('$BATCH_DIR')
mark_fetching(batch, pid=os.getpid())
write_pid(batch, os.getpid())
"

echo "=== Fetch EN + KO posts from last 24 hours (skip already processed) ==="
echo "Batch folder: $BATCH_DIR"
rm -f "$BATCH_DIR/urls.txt"

if ! .venv/bin/python scripts/fetch_blog_index.py \
  --since-hours 24 \
  --output "$BATCH_DIR/urls.txt" \
  --batch-dir "$BATCH_DIR" \
  "$@"; then
  .venv/bin/python -c "
import sys
sys.path.insert(0, 'scripts')
from pathlib import Path
from batch_state import mark_fetch_failed
mark_fetch_failed(Path('$BATCH_DIR'), 'fetch_blog_index.py failed — see daily-batch-run.log')
"
  exit 1
fi

if [[ ! -s "$BATCH_DIR/urls.txt" ]] || ! grep -qE '^https?://' "$BATCH_DIR/urls.txt"; then
  echo "No new URLs to process. Exiting."
  .venv/bin/python -c "
import sys
sys.path.insert(0, 'scripts')
from pathlib import Path
from batch_state import mark_no_urls
mark_no_urls(Path('$BATCH_DIR'))
"
  exit 0
fi

echo ""
echo "=== Run batch pipeline (scripts + clip prompts only) ==="
echo '--skip-voiceover --skip-videos' > "$BATCH_DIR/batch_pipeline_flags.txt"
./batch-run.sh "$BATCH_DIR/urls.txt" --projects-dir "$BATCH_DIR" \
  --skip-voiceover --skip-videos "$@"
