#!/usr/bin/env bash
# Generate a single clip into an existing run folder.
# Usage: ./generate-clip.sh <clip_id> <prompts_dir> <output_dir>
# Example:
#   ./generate-clip.sh signs \
#     output/clips/q-my-6-year-old-has-gastroenteritis-but-is-getting-20260527-2325 \
#     output/clips/q-my-6-year-old-has-gastroenteritis-but-is-getting-20260527-2257
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -lt 3 ]]; then
  echo "Usage: ./generate-clip.sh <clip_id> <prompts_dir> <output_dir>"
  exit 1
fi

exec ./script-to-clips.sh --resume "$3" --only "$1" --prompts-dir "$2"
