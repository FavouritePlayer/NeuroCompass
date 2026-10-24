#!/usr/bin/env bash
# Build ScreenShade.app with the Command Line Tools Swift compiler (no Xcode.app required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/ScreenShade.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
SRC="$ROOT/Sources/ScreenShade"

SDK="$(xcrun --show-sdk-path)"
SWIFT_FILES=("$SRC"/*.swift)

echo "==> Cleaning $BUILD"
rm -rf "$BUILD"
mkdir -p "$MACOS" "$RES"

echo "==> Compiling Swift ($(basename "$SDK"))"
swiftc -sdk "$SDK" \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework QuartzCore \
  -O \
  -o "$MACOS/ScreenShade" \
  "${SWIFT_FILES[@]}"

echo "==> Bundling Info.plist + sample config"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/config/config.json" "$RES/config.json"

# Ad-hoc sign so Gatekeeper is happier for local runs.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "==> Built: $APP"
echo "    Run:   open \"$APP\""
echo "    Or:    \"$MACOS/ScreenShade\""
