#!/usr/bin/env bash
# Builds a release binary and wraps it into "Dynamac Island.app" (ad-hoc signed),
# bundling the MediaRemote adapter used for "all media sources".
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DynamacIsland"
APP="build/Dynamac Island.app"

./scripts/build-mediaremote.sh

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ThirdParty" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/DynamacIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R build/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP/Contents/Resources/"
cp Vendor/mediaremote-adapter/LICENSE "$APP/Contents/Resources/ThirdParty/mediaremote-adapter-LICENSE.txt"
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run with: open \"$APP\""
