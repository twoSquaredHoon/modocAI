#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -lt 1 ]]; then
  echo "Usage: ./make-video.sh <blog-url> [--prompts-only]"
  echo ""
  echo "Runs blog-to-script, then script-to-clips."
  exit 1
fi

url="$1"
shift

echo "=== 1/2 Blog → script ==="
./blog-to-script.sh "$url"
script_path="$(ls -t output/scripts/*.txt 2>/dev/null | head -1)"
if [[ -z "${script_path:-}" || ! -f "$script_path" ]]; then
  echo "Could not find generated script in output/scripts/." >&2
  exit 1
fi
echo "Using script: $script_path"

echo ""
echo "=== 2/2 Script → clips ==="
./script-to-clips.sh "$script_path" "$@"
