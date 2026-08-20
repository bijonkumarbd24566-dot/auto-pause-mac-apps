#!/bin/bash
# Notarize the DMG so macOS launches it with no warning at all.
#
# Requires a paid Apple Developer Program membership ($99/year) — Apple issues
# "Developer ID Application" certificates only to paid members. Free Apple IDs get
# "Apple Development" certificates, which Gatekeeper does NOT accept for distribution.
#
# One-time setup:
#   1. Enroll:  https://developer.apple.com/programs/
#   2. In Xcode or the developer portal, create a "Developer ID Application"
#      certificate and install it in your login keychain.
#   3. Create an app-specific password at https://appleid.apple.com (Sign-In & Security).
#   4. Store the credentials once:
#        xcrun notarytool store-credentials "AutoPauseNotary" \
#          --apple-id "you@example.com" --team-id "YOURTEAMID" --password "app-specific-password"
#
# Then:  ./notarize.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.2.0}"
DMG="AutoPauseMacApps-${VERSION}.dmg"
PROFILE="${NOTARY_PROFILE:-AutoPauseNotary}"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')

if [[ -z "$IDENTITY" ]]; then
  cat >&2 <<'MSG'
✗ No "Developer ID Application" certificate found.

Without one, macOS shows the "Apple could not verify..." dialog on first launch.
That certificate requires a paid Apple Developer Program membership ($99/year):
https://developer.apple.com/programs/

Until then, users can install without any warning using:
  brew install --cask fazalrshah/tap/auto-pause-mac-apps
or the one-line installer in the README.
MSG
  exit 1
fi

echo "▸ Building and signing with: $IDENTITY"
./build.sh --universal

echo "▸ Packaging $DMG..."
./package-dmg.sh "$VERSION"

echo "▸ Submitting to Apple for notarization (this usually takes 1-5 minutes)..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling the ticket to the DMG..."
xcrun stapler staple "$DMG"

echo "▸ Verifying..."
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true

echo
echo "✅ $DMG is signed, notarized and stapled."
echo "   It will now open on any Mac with no Gatekeeper warning."
