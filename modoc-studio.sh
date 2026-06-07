#!/usr/bin/env bash
# Launch Modoc Studio as a real Mac .app (so typing does not go to Terminal).
set -euo pipefail
cd "$(dirname "$0")"
exec ./build-modoc-studio.sh
