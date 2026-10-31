#!/usr/bin/env bash
# Builds Vendor/mediaremote-adapter (BSD-3-Clause, ungive/mediaremote-adapter) into
# build/MediaRemoteAdapter.framework with plain clang, so cmake isn't required.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=Vendor/mediaremote-adapter
OUT=build/MediaRemoteAdapter.framework
rm -rf "$OUT"
mkdir -p "$OUT/Versions/A/Resources"
clang -dynamiclib -fobjc-arc -fvisibility=default -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -I"$SRC/include" -I"$SRC/src" \
  "$SRC"/src/adapter/*.m "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$OUT/Versions/A/MediaRemoteAdapter"
cat > "$OUT/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
</dict></plist>
PLIST
ln -sfn A "$OUT/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$OUT/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$OUT/Resources"
codesign --force --sign - "$OUT" >/dev/null
echo "Built $OUT"
