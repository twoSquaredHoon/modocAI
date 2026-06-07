#!/usr/bin/env bash
# Remove generated scripts, clips, and voiceovers (keeps .env and venv).
set -euo pipefail
cd "$(dirname "$0")"

FORCE=false
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
  FORCE=true
fi

OUTPUT_ROOT="output"
DIRS=(scripts clips voiceovers)

if [[ "$FORCE" != true ]]; then
  echo "This deletes everything under:"
  for d in "${DIRS[@]}"; do
    echo "  $OUTPUT_ROOT/$d/"
  done
  echo "  $OUTPUT_ROOT/*.mp4 (test clips at root)"
  echo ""
  read -r -p "Continue? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

mkdir -p "$OUTPUT_ROOT"

for d in "${DIRS[@]}"; do
  target="$OUTPUT_ROOT/$d"
  if [[ -d "$target" ]]; then
    rm -rf "$target"
    echo "Cleared $target/"
  fi
  mkdir -p "$target"
  touch "$target/.gitkeep"
done

# Remove stray test videos at output root
shopt -s nullglob
for f in "$OUTPUT_ROOT"/*.mp4 "$OUTPUT_ROOT"/*.wav; do
  [[ -e "$f" ]] && rm -f "$f" && echo "Removed $f"
done
shopt -u nullglob

echo ""
echo "Done. Output folders are empty and ready for a new blog post."
echo "Start fresh with:"
echo '  ./blog-to-script.sh "https://your-new-blog-url"'
