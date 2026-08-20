#!/bin/bash
# Install Auto Pause Mac Apps — no Gatekeeper warning.
#
#   curl -fsSL https://raw.githubusercontent.com/fazalrshah/auto-pause-mac-apps/main/install.sh | bash
#
# Downloads the latest release, installs it to /Applications, and clears the
# quarantine attribute macOS applies to downloaded files. Clearing quarantine is
# what removes the "Apple could not verify..." dialog — it is the same thing
# Homebrew does for every unnotarized cask.
set -euo pipefail

REPO="fazalrshah/auto-pause-mac-apps"
APP_NAME="Auto Pause Mac Apps.app"
INSTALL_DIR="/Applications"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; hdiutil detach "$TMP/mnt" -quiet 2>/dev/null || true' EXIT

echo "▸ Finding the latest release..."
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep '"browser_download_url".*\.dmg"' | head -1 | cut -d'"' -f4)

if [[ -z "$URL" ]]; then
  echo "✗ Couldn't find a DMG in the latest release." >&2
  echo "  Download manually: https://github.com/$REPO/releases/latest" >&2
  exit 1
fi

echo "▸ Downloading $(basename "$URL")..."
curl -fL# "$URL" -o "$TMP/app.dmg"

echo "▸ Mounting..."
mkdir -p "$TMP/mnt"
hdiutil attach "$TMP/app.dmg" -nobrowse -quiet -mountpoint "$TMP/mnt"

if [[ ! -d "$TMP/mnt/$APP_NAME" ]]; then
  echo "✗ '$APP_NAME' not found inside the disk image." >&2
  exit 1
fi

if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
  echo "▸ Removing the previous version..."
  pkill -f "$APP_NAME/Contents/MacOS/" 2>/dev/null || true
  sleep 1
  rm -rf "${INSTALL_DIR:?}/$APP_NAME"
fi

echo "▸ Installing to $INSTALL_DIR..."
cp -R "$TMP/mnt/$APP_NAME" "$INSTALL_DIR/"
hdiutil detach "$TMP/mnt" -quiet

# This is the step that prevents the Gatekeeper dialog.
echo "▸ Clearing the quarantine flag..."
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

echo "▸ Launching..."
open "$INSTALL_DIR/$APP_NAME"

echo
echo "✅ Installed. Look for the pause icon in your menu bar."
echo "   No Dock icon and no window — it lives entirely in the menu bar."
