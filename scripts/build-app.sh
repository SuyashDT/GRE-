#!/bin/bash
# Builds "GRE Prep.app" (and a zip of it) from the Swift package.
#
#   scripts/build-app.sh              # app for this Mac's architecture
#   scripts/build-app.sh --universal  # Apple silicon + Intel
#
# Needs macOS 14+ with Xcode or the Xcode Command Line Tools installed.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Validating content"
python3 scripts/validate_content.py Sources/GRECore/Resources/Content/*.json

echo "==> Compiling (release)"
swift build -c release --product GREPrep ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})"

APP="build/GRE Prep.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GREPrep" "$APP/Contents/MacOS/GREPrep"
cp Sources/GREPrep/Info.plist "$APP/Contents/Info.plist"
# The app looks for Contents/Resources/Content before the SwiftPM resource bundle.
cp -R Sources/GRECore/Resources/Content "$APP/Contents/Resources/Content"

echo "==> Making the icon"
ICON_TMP="$(mktemp -d)"
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

echo "==> Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP"

ZIP="build/GRE-Prep.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "Built: $APP"
echo "Zip:   $ZIP"
echo "Open it with:  open \"$APP\""
