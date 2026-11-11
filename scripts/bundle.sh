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
# Bundled alert sounds (the timer and calendar alarm).
cp Resources/Sounds/*.aiff "$APP/Contents/Resources/" 2>/dev/null || true

# Build AppIcon.icns from Resources/AppIcon.png (square PNG, ideally 1024x1024).
if [ -f Resources/AppIcon.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run with: open \"$APP\""
