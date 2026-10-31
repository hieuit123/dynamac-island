#!/usr/bin/env bash
# Builds a release binary and wraps it into "Dynamac Island.app" (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DynamacIsland"
APP="build/Dynamac Island.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DynamacIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run with: open \"$APP\""
