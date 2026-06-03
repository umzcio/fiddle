#!/bin/bash
set -euo pipefail

# End-to-end release: build -> sign -> .dmg -> notarize -> staple.
# Produces build/Fiddle-<version>.dmg ready to upload to a GitHub release.
#
# Prereqs:
#   - The Release signing config is set (Developer ID, Team 5JJ6G6A84S, hardened
#     runtime), which it is in the Xcode project.
#   - scripts/.notary-config.local set up (see .notary-config.example).
#
# Usage: scripts/release.sh 1.0.0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: release.sh <version>  e.g. 1.0.0}"
APP_NAME="Fiddle"
APP_DIR="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
DIST="$ROOT/build/dist"
DOWNLOAD_URL_PREFIX="https://github.com/umzcio/fiddle/releases/download/v$VERSION/"
SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"

echo "==> [1/5] Build + sign app"
bash "$ROOT/scripts/build-app.sh"

echo "==> [2/5] Package .dmg"
bash "$ROOT/scripts/make-dmg.sh" "$VERSION"

echo "==> [3/5] Notarize the .dmg (also notarizes the app inside)"
bash "$ROOT/scripts/notarize.sh" "$DMG"

echo "==> [4/5] Staple the .app, then repackage so the shipped app carries its ticket"
xcrun stapler staple "$APP_DIR"
bash "$ROOT/scripts/make-dmg.sh" "$VERSION"
# The repackaged dmg is a new file, so it needs its own notarization + staple.
bash "$ROOT/scripts/notarize.sh" "$DMG"

echo "==> [5/6] Generate the signed Sparkle appcast"
# generate_appcast reads the EdDSA private key from the keychain, signs the dmg,
# and writes appcast.xml with the GitHub-release enclosure URL. Copy it to the
# repo root so SUFeedURL (raw.githubusercontent.com/.../main/appcast.xml) resolves.
rm -rf "$DIST"; mkdir -p "$DIST"
cp "$DMG" "$DIST/"
"$SPARKLE_BIN/generate_appcast" "$DIST" --download-url-prefix "$DOWNLOAD_URL_PREFIX"
cp "$DIST/appcast.xml" "$ROOT/appcast.xml"

echo "==> [6/6] Done"
echo "  DMG     : $DMG"
echo "  appcast : $ROOT/appcast.xml"
echo
echo "  Next:"
echo "    1) gh release create v$VERSION \"$DMG\" --title \"fiddle $VERSION\" --notes \"...\""
echo "       (or: gh release upload v$VERSION \"$DMG\" --clobber  to replace an existing release asset)"
echo "    2) git add appcast.xml && git commit -m \"appcast: $VERSION\" && git push   (so the update feed goes live)"
