#!/bin/bash
# Builds Drift.app as a universal binary (Apple Silicon + Intel), macOS 12+.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Drift.app"
SDK="$(xcrun --show-sdk-path)"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for ARCH in arm64 x86_64; do
  echo "→ compiling $ARCH"
  swiftc -O -whole-module-optimization \
    -target "$ARCH-apple-macos12.0" -sdk "$SDK" \
    Sources/*.swift -o "build/obj/Drift-$ARCH" \
    -framework Cocoa -framework Metal -framework MetalKit -framework IOKit
done
lipo -create build/obj/Drift-arm64 build/obj/Drift-x86_64 -output "$APP/Contents/MacOS/Drift"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ icon"
swiftc -O tools/make_icon.swift -o build/obj/make_icon
build/obj/make_icon build/obj/AppIcon.iconset
iconutil -c icns build/obj/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ signing (ad-hoc)"
# Folders synced by iCloud Drive tag files with extended attributes, which codesign rejects.
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

mkdir -p dist
rm -f dist/Drift.zip
ditto -c -k --keepParent "$APP" dist/Drift.zip

lipo -info "$APP/Contents/MacOS/Drift"
echo "✓ Built $APP and dist/Drift.zip"
