#!/bin/bash
set -euo pipefail

# Builds a distributable Fiddle.app: archives the Release config, then exports
# with the Developer ID method. The export (not a plain `build`) is what strips
# the get-task-allow debug entitlement, adds the secure timestamp, and signs the
# nested code correctly, so the result actually passes notarization.
#
# Output: build/Fiddle.app
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Fiddle"
ARCHIVE="$ROOT/build/$APP_NAME.xcarchive"
EXPORT_DIR="$ROOT/build/export"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "==> Archiving $APP_NAME (Release)"
rm -rf "$ARCHIVE"
xcodebuild -scheme "$APP_NAME" -configuration Release \
    -archivePath "$ARCHIVE" \
    -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
    archive

echo "==> Exporting Developer ID app"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist"

[ -d "$EXPORT_DIR/$APP_NAME.app" ] || { echo "error: export produced no $APP_NAME.app"; exit 1; }
rm -rf "$APP_DIR"
cp -R "$EXPORT_DIR/$APP_NAME.app" "$APP_DIR"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP_DIR"
SIGINFO="$(codesign -dvv "$APP_DIR" 2>&1 || true)"
echo "$SIGINFO" | grep -E "Authority=|TeamIdentifier=|runtime" || true

# Distribution sanity checks (capture first; piping to grep -q under pipefail
# can SIGPIPE the producer and read as a false failure).
case "$SIGINFO" in
    *"Authority=Developer ID Application"*) ;;
    *) echo "error: $APP_NAME.app is not Developer ID signed"; exit 1 ;;
esac
ENTS="$(codesign -d --entitlements - "$APP_DIR" 2>/dev/null || true)"
case "$ENTS" in
    *get-task-allow*) echo "error: get-task-allow present, this is a development signature, not distributable"; exit 1 ;;
esac

echo "==> Done: $APP_DIR"
