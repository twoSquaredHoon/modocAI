#!/usr/bin/env bash
# Build ModocStudio.app and launch it (keyboard focus goes to the app, not Terminal).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
STUDIO="$ROOT/ModocStudio"
APP="$ROOT/ModocStudio.app"

echo "Building Modoc Studio…"
cd "$STUDIO"
swift build -c release

BIN="$STUDIO/.build/release/ModocStudio"
if [[ ! -f "$BIN" ]]; then
  echo "Build failed: $BIN not found" >&2
  exit 1
fi

echo "Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ModocStudio"
cp "$STUDIO/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/ModocStudio"

echo "Quitting any old Modoc Studio window…"
osascript -e 'tell application "Modoc Studio" to quit' 2>/dev/null || true
killall ModocStudio 2>/dev/null || true
sleep 0.5

echo "Launching Modoc Studio.app ($(date '+%H:%M:%S'))"
open "$APP"

echo ""
echo "You should see two big buttons at the top of the sidebar:"
echo "  [ New Project ]"
echo "  [ Open Existing Project ]"
echo "⌘O = Open Existing Project"
