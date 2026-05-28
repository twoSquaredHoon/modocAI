#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env — add your API key there."
fi

python3 -m venv .venv
.venv/bin/pip install -q -r requirements.txt
echo "Done. Add your key to .env, then run:"
echo "  ./test-api.sh"
echo "  ./blog-to-script.sh \"https://your-blog-url\""
echo "  ./script-to-voiceover.sh output/scripts/your-script.txt"
echo "  ./script-to-clips.sh output/scripts/your-script.txt"
echo "  ./make-video.sh \"https://your-blog-url\""
