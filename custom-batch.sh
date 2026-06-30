#!/usr/bin/env bash
# Custom batch: configurable fetch + pipeline for Modoc Studio and CLI.
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

DATE_FOLDER=""
FETCH_MODE="latest"
ARTICLE_COUNT=5
SINCE_HOURS=24
LANGUAGE="en"
INCLUDE_PROCESSED=0
PROCESS_LIMIT=0
RUN_ARTICLE_CHECK=1
RUN_VOICEOVER=0
RUN_VIDEOS=0

usage() {
  cat <<'EOF'
Usage: ./custom-batch.sh [options]

Fetch (pick one mode):
  --latest N              Newest N post(s) per selected language index (default mode)
  --since-hours H         Posts published in the last H hours
  --max-per-index N       Cap per language after time-window fetch (with --since-hours)

Language:
  --language en|ko|both   Blog index to use (default: en)

Pipeline:
  --skip-article-check    Skip script vs article verification
  --skip-voiceover        Skip voiceover generation
  --skip-videos           Skip Veo video generation
  --full-pipeline         Shorthand: article check + voiceover + videos

Other:
  --date-folder NAME      output/projects/NAME (default: YYYY-MM-DD-custom-HHmm)
  --limit N               Process at most N URLs from the fetch result (0 = all)
  --include-processed     Re-fetch URLs already in processed_articles.json
  -h, --help              Show this help

Examples:
  ./custom-batch.sh --latest 3 --language ko
  ./custom-batch.sh --since-hours 48 --max-per-index 5 --language both --limit 8
  ./custom-batch.sh --latest 1 --language en --full-pipeline
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date-folder)
      DATE_FOLDER="$2"
      shift 2
      ;;
    --latest)
      FETCH_MODE="latest"
      ARTICLE_COUNT="$2"
      shift 2
      ;;
    --since-hours)
      FETCH_MODE="since"
      SINCE_HOURS="$2"
      shift 2
      ;;
    --max-per-index)
      ARTICLE_COUNT="$2"
      shift 2
      ;;
    --language)
      LANGUAGE="$2"
      shift 2
      ;;
    --limit)
      PROCESS_LIMIT="$2"
      shift 2
      ;;
    --include-processed)
      INCLUDE_PROCESSED=1
      shift
      ;;
    --skip-article-check)
      RUN_ARTICLE_CHECK=0
      shift
      ;;
    --skip-voiceover)
      RUN_VOICEOVER=0
      shift
      ;;
    --skip-videos)
      RUN_VIDEOS=0
      shift
      ;;
    --full-pipeline)
      RUN_ARTICLE_CHECK=1
      RUN_VOICEOVER=1
      RUN_VIDEOS=1
      shift
      ;;
    --run-voiceover)
      RUN_VOICEOVER=1
      shift
      ;;
    --run-videos)
      RUN_VIDEOS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$DATE_FOLDER" ]]; then
  DATE_FOLDER="$(date +%Y-%m-%d)-custom-$(date +%H%M)"
fi

BATCH_DIR="$ROOT/output/projects/$DATE_FOLDER"
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

FETCH_ARGS=(scripts/fetch_blog_index.py --output "$BATCH_DIR/urls.txt" --batch-dir "$BATCH_DIR")
if [[ "$FETCH_MODE" == "latest" ]]; then
  FETCH_ARGS+=(--latest "$ARTICLE_COUNT")
else
  FETCH_ARGS+=(--since-hours "$SINCE_HOURS")
  if [[ "$ARTICLE_COUNT" -gt 0 ]]; then
    FETCH_ARGS+=(--max-per-index "$ARTICLE_COUNT")
  fi
fi

case "$LANGUAGE" in
  en) FETCH_ARGS+=(--en-only) ;;
  ko) FETCH_ARGS+=(--ko-only) ;;
  both) ;;
  *)
    echo "Invalid --language: $LANGUAGE (use en, ko, or both)" >&2
    exit 1
    ;;
esac

if [[ "$INCLUDE_PROCESSED" -eq 1 ]]; then
  FETCH_ARGS+=(--include-processed)
fi

echo "=== Custom batch fetch ==="
echo "Batch folder: $BATCH_DIR"
rm -f "$BATCH_DIR/urls.txt"

if ! .venv/bin/python "${FETCH_ARGS[@]}"; then
  .venv/bin/python -c "
import sys
sys.path.insert(0, 'scripts')
from pathlib import Path
from batch_state import mark_fetch_failed
mark_fetch_failed(Path('$BATCH_DIR'), 'fetch_blog_index.py failed — see custom-batch-run.log')
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

: > "$BATCH_DIR/batch_pipeline_flags.txt"
BATCH_FLAG_ARGS=()
[[ "$RUN_ARTICLE_CHECK" -eq 0 ]] && BATCH_FLAG_ARGS+=(--skip-article-check)
[[ "$RUN_VOICEOVER" -eq 0 ]] && BATCH_FLAG_ARGS+=(--skip-voiceover)
[[ "$RUN_VIDEOS" -eq 0 ]] && BATCH_FLAG_ARGS+=(--skip-videos)
[[ "$PROCESS_LIMIT" -gt 0 ]] && BATCH_FLAG_ARGS+=(--limit "$PROCESS_LIMIT")
printf '%s\n' "${BATCH_FLAG_ARGS[*]}" > "$BATCH_DIR/batch_pipeline_flags.txt"

echo ""
echo "=== Run batch pipeline ==="
echo "Flags: ${BATCH_FLAG_ARGS[*]:-(through clip prompts)}"
./batch-run.sh "$BATCH_DIR/urls.txt" --projects-dir "$BATCH_DIR" "${BATCH_FLAG_ARGS[@]}"
