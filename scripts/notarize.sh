#!/bin/bash
set -euo pipefail

# Notarizes a .dmg / .zip / .app with Apple, then staples the ticket.
# Credentials come from a notarytool keychain profile, "notary" by default
# (override with NOTARY_PROFILE); create it once with
#   xcrun notarytool store-credentials notary
# Never put notary keys or passwords in this repo.
#
# Usage: scripts/notarize.sh build/Fiddle-1.1.0.dmg

ARTIFACT="${1:?usage: notarize.sh <path-to-dmg-zip-or-app>}"
PROFILE="${NOTARY_PROFILE:-notary}"

echo "==> Submitting $(basename "$ARTIFACT") to Apple notary"
xcrun notarytool submit "$ARTIFACT" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"
echo "==> Notarized + stapled: $ARTIFACT"
