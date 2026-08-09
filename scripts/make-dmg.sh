#!/bin/bash
set -euo pipefail

# Packages build/Fiddle.app into a drag-to-Applications .dmg.
# Run scripts/build-app.sh first.
#
# Usage: scripts/make-dmg.sh [version]   (version defaults to the app's CFBundleShortVersionString)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Fiddle"
APP_DIR="$ROOT/build/$APP_NAME.app"
VERSION="${1:-$(defaults read "$APP_DIR/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 1.0.0)}"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
STAGE="$ROOT/build/dmg-stage"

[ -d "$APP_DIR" ] || { echo "error: $APP_DIR not found, run scripts/build-app.sh first"; exit 1; }

echo "==> Staging DMG contents"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGE"

# Sign the dmg itself. The app inside carries the stapled ticket Gatekeeper
# checks at launch, so an unsigned dmg WORKS, but it assesses as
# "rejected, source=no usable signature" under spctl, indistinguishable from
# a broken artifact. Signing before notarization flips the assessment to
# "accepted, source=Notarized Developer ID". Shipped unsigned through 1.0.7.
echo "==> Signing $DMG"
codesign --force --timestamp --sign "Developer ID Application" "$DMG"
codesign -dv "$DMG" >/dev/null 2>&1 || { echo "error: dmg signing failed"; exit 1; }

echo "==> Done: $DMG"
