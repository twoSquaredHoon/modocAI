#!/usr/bin/env bash
# Start daily-batch.sh detached (survives Terminal/Cursor closing).
# Run this from Terminal — not from an IDE background task.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

DATE=$(date +%Y-%m-%d)
BATCH_DIR="$ROOT/output/projects/$DATE"
mkdir -p "$BATCH_DIR"
LOG="$BATCH_DIR/daily-batch-run.log"

if [[ ! -d .venv ]]; then
  echo "Run ./setup.sh first."
  exit 1
fi

RUNNING=$(
  .venv/bin/python -c "
import sys
sys.path.insert(0, 'scripts')
from pathlib import Path
from batch_state import is_batch_running
print('yes' if is_batch_running(Path('$BATCH_DIR')) else 'no')
" 2>/dev/null || echo "no"
)

if [[ "$RUNNING" == "yes" ]]; then
  PID=$(.venv/bin/python -c "import sys; sys.path.insert(0,'scripts'); from pathlib import Path; from batch_state import read_pid; print(read_pid(Path('$BATCH_DIR')) or '')")
  echo "Daily batch already running for $DATE (PID ${PID:-unknown})."
  echo "Log: $LOG"
  exit 1
fi

echo "Starting daily batch for $DATE"
echo "Log: $LOG"

nohup env PYTHONUNBUFFERED=1 "$ROOT/daily-batch.sh" "$@" >>"$LOG" 2>&1 &
BATCH_PID=$!
disown -h "$BATCH_PID" 2>/dev/null || true

sleep 1
if kill -0 "$BATCH_PID" 2>/dev/null; then
  echo "Started (PID $BATCH_PID)"
  echo "Monitor: tail -f $LOG"
else
  echo "Batch exited immediately — check $LOG"
  tail -20 "$LOG" 2>/dev/null || true
  exit 1
fi
