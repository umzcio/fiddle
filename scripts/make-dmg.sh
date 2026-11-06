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
# Signed by team ID, which matches only that team's Developer ID certificate,
# and refused if the result names any other team.
TEAM_ID="V2P99VF75Q"
codesign --force --timestamp --sign "$TEAM_ID" "$DMG"
SIGINFO="$(codesign -dvv "$DMG" 2>&1 || true)"
case "$SIGINFO" in
    *"TeamIdentifier=$TEAM_ID"*) ;;
    *) echo "error: dmg is not signed by team $TEAM_ID"; exit 1 ;;
esac

echo "==> Done: $DMG"
