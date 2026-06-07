#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Scripts (output/scripts/) ==="
if compgen -G "output/scripts/*.txt" >/dev/null 2>&1; then
  ls -lt output/scripts/*.txt | head -10
else
  echo "  (none — run ./blog-to-script.sh \"URL\")"
fi

echo ""
echo "=== Clips runs (output/clips/) ==="
if compgen -G "output/clips/*" >/dev/null 2>&1; then
  ls -ltd output/clips/*/ 2>/dev/null | head -10
else
  echo "  (none — run ./script-to-clips.sh output/scripts/….txt --prompts-only)"
fi

echo ""
echo "=== Voiceovers (output/voiceovers/) ==="
if compgen -G "output/voiceovers/*" >/dev/null 2>&1; then
  ls -ltd output/voiceovers/*/ 2>/dev/null | head -10
else
  echo "  (none)"
fi
