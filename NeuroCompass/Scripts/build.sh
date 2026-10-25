#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/NeuroCompass.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
SRC="$ROOT/Sources/NeuroCompass"
SDK="$(xcrun --show-sdk-path)"

echo "==> Cleaning $BUILD"
rm -rf "$BUILD"
mkdir -p "$MACOS" "$RES"

SWIFT_FILES=()
while IFS= read -r f; do
  SWIFT_FILES+=("$f")
done < <(find "$SRC" -name '*.swift' | sort)

echo "==> Compiling NeuroCompass (${#SWIFT_FILES[@]} files)"
swiftc -sdk "$SDK" \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework AVFoundation \
  -O \
  -o "$MACOS/NeuroCompass" \
  "${SWIFT_FILES[@]}"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "==> Built: $APP"
echo "    open \"$APP\""
