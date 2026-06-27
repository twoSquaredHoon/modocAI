#!/usr/bin/env bash
# One-time setup after clone: venv, .env, output folders, Modoc Studio root path.
# Run once, then use ./build-modoc-studio.sh whenever you want the app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

log() { echo "$@"; }
warn() { echo "$@" >&2; }

if ! command -v python3 &>/dev/null; then
  warn "python3 not found. Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

# API key file (gitignored)
if [[ ! -f .env ]]; then
  cp .env.example .env
  log "Created .env"
fi

# Python environment (recreate if copied from another machine or Python was upgraded)
venv_usable() {
  [[ -x .venv/bin/python ]] && .venv/bin/python -c "import sys" &>/dev/null
}

if [[ -d .venv ]] && ! venv_usable; then
  warn "Broken .venv (Python interpreter missing). Recreating…"
  rm -rf .venv
fi

if [[ ! -d .venv ]]; then
  log "Creating Python venv…"
  python3 -m venv .venv
fi
.venv/bin/pip install -q -U pip
.venv/bin/pip install -q -r requirements.txt

# Output folders (CLI + Modoc Studio projects)
for d in output/projects output/scripts output/clips output/voiceovers; do
  mkdir -p "$d"
  [[ -f "$d/.gitkeep" ]] || touch "$d/.gitkeep"
done

# Shell scripts executable
for sh in *.sh; do
  [[ -f "$sh" ]] && chmod +x "$sh"
done

# Absolute repo path — Modoc Studio reads this on any machine after clone/rename
echo "$ROOT" > .modoc-root

# Register path for Modoc Studio (bundle id us.fevercoach.modoc-studio)
if defaults write us.fevercoach.modoc-studio modocAIRootPath "$ROOT" 2>/dev/null; then
  log "Registered modocAI root for Modoc Studio"
else
  log "Note: could not write UserDefaults (Modoc Studio will auto-detect from .modoc-root)"
fi

echo ""
echo "✓ modocAI ready at $ROOT"
if grep -qE '^GEMINI_API_KEY=.+' .env 2>/dev/null; then
  echo "  Next: ./build-modoc-studio.sh"
else
  echo "  Next: paste GEMINI_API_KEY into .env, then ./build-modoc-studio.sh"
  echo "  (The app opens without a key; pipeline steps need the key.)"
fi