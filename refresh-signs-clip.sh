#!/usr/bin/env bash
# Rebuild signs_1, signs_2, … prompts and generate each clip separately (for editing).
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -lt 2 ]]; then
  echo "Usage: ./refresh-signs-clip.sh <clips_output_dir> <script.txt> [prompts_dir]"
  echo ""
  echo "Creates signs_1.mp4, signs_2.mp4, … (one Veo clip per warning sign)."
  exit 1
fi

OUT_DIR="$1"
SCRIPT="$2"
PROMPTS_DIR="${3:-$OUT_DIR}"

IDS=$(.venv/bin/python scripts/signs_clip_prompt.py "$PROMPTS_DIR" "$SCRIPT" | \
  sed -n 's/^Clip ids: //p')

rm -f "$OUT_DIR/videos/signs.mp4"
for f in "$OUT_DIR/videos/signs_"*.mp4; do
  [[ -e "$f" ]] && rm -f "$f"
done

echo "Generating: $IDS"
./script-to-clips.sh --resume "$OUT_DIR" --only signs --prompts-dir "$PROMPTS_DIR"
