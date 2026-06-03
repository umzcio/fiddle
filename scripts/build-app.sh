#!/bin/bash
set -euo pipefail

# Builds a Release Fiddle.app: Developer ID signed, hardened runtime, no debug
# entitlements. The signing identity (Developer ID Application, Team 5JJ6G6A84S)
# and hardened runtime are configured in the Xcode project's Release config, so
# a plain Release build is already notarization-ready.
#
# Output: build/Fiddle.app
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Fiddle"
DERIVED="$ROOT/build/release"
APP_SRC="$DERIVED/Build/Products/Release/$APP_NAME.app"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "==> Building $APP_NAME (Release, Developer ID, hardened runtime)"
xcodebuild -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath "$DERIVED" \
    -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
    build

[ -d "$APP_SRC" ] || { echo "error: $APP_SRC not found"; exit 1; }
rm -rf "$APP_DIR"
cp -R "$APP_SRC" "$APP_DIR"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP_DIR"
codesign -dvv "$APP_DIR" 2>&1 | grep -E "Authority=|TeamIdentifier=|runtime" || true

# Hard fail if it is not a Developer ID signature (a local-only signature will
# never notarize, so catch it here rather than after a notary round-trip).
if ! codesign -dvv "$APP_DIR" 2>&1 | grep -q "Authority=Developer ID Application"; then
    echo "error: $APP_NAME.app is not Developer ID signed; check the Release signing config"
    exit 1
fi

echo "==> Done: $APP_DIR"
