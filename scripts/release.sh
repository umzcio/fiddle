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

echo "==> [5/5] Done"
echo "  DMG: $DMG  ->  upload to the v$VERSION GitHub release"
