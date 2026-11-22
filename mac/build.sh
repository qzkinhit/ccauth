#!/bin/sh
# Builds ccauth.app (universal: Apple silicon + Intel). Needs the Xcode Command Line Tools.
#   ./build.sh            -> mac/build/ccauth.app
#   ./build.sh --install  -> also copies it to /Applications
set -eu
cd "$(dirname "$0")"
OUT=build
APP="$OUT/ccauth.app"

mkdir -p "$OUT"
if [ -d "$APP" ]; then mv "$APP" "$OUT/.old-$(date +%s).app"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -parse-as-library -O -target "$arch-apple-macos14.0" \
    -o "$OUT/ccauth-$arch" Sources/*.swift
done
lipo -create "$OUT/ccauth-arm64" "$OUT/ccauth-x86_64" -output "$APP/Contents/MacOS/ccauth"

cp Info.plist "$APP/Contents/Info.plist"
cp ../ccauth "$APP/Contents/Resources/ccauth"
chmod +x "$APP/Contents/Resources/ccauth"

swift make_icon.swift "$OUT/AppIcon.iconset"
iconutil -c icns "$OUT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep -s - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  if [ -d /Applications/ccauth.app ]; then mv /Applications/ccauth.app "$OUT/.replaced-$(date +%s).app"; fi
  ditto "$APP" /Applications/ccauth.app
  echo "Installed /Applications/ccauth.app"
fi
