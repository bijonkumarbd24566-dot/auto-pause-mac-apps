#!/bin/bash
# Install Auto Pause Mac Apps — no Gatekeeper warning.
#
#   curl -fsSL https://raw.githubusercontent.com/fazalrshah/auto-pause-mac-apps/main/install.sh | bash
#
# Downloads the latest release, installs it to /Applications, and clears the
# quarantine attribute macOS applies to downloaded files. Clearing quarantine is
# what removes the "Apple could not verify..." dialog — the same thing Homebrew
# does for every unnotarized cask.
#
# Everything lives inside main() and is only called on the last line. When this
# script is piped into bash, bash reads it from the same pipe the commands inherit
# as stdin; without a wrapper, a child process can swallow part of the script and
# bash resumes parsing mid-token. Defining a function forces bash to read the whole
# body first. Child processes also get </dev/null so they cannot consume it.
set -euo pipefail

main() {
  local repo="fazalrshah/auto-pause-mac-apps"
  local app_name="Auto Pause Mac Apps.app"
  local install_dir="/Applications"
  local tmp
  tmp=$(mktemp -d)
  trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT

  echo "▸ Finding the latest release..."
  local url
  url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" </dev/null \
    | grep '"browser_download_url".*\.dmg"' | head -1 | cut -d'"' -f4)

  if [[ -z "$url" ]]; then
    echo "✗ Couldn't find a DMG in the latest release." >&2
    echo "  Download manually: https://github.com/$repo/releases/latest" >&2
    return 1
  fi

  echo "▸ Downloading $(basename "$url")..."
  curl -fL --progress-bar "$url" -o "$tmp/app.dmg" </dev/null

  echo "▸ Mounting..."
  mkdir -p "$tmp/mnt"
  hdiutil attach "$tmp/app.dmg" -nobrowse -quiet -mountpoint "$tmp/mnt" </dev/null

  if [[ ! -d "$tmp/mnt/$app_name" ]]; then
    echo "✗ '$app_name' not found inside the disk image." >&2
    return 1
  fi

  if [[ -d "$install_dir/$app_name" ]]; then
    echo "▸ Replacing the previous version..."
    pkill -f "$app_name/Contents/MacOS/" 2>/dev/null || true
    sleep 1
    rm -rf "${install_dir:?}/$app_name"
  fi

  echo "▸ Installing to $install_dir..."
  cp -R "$tmp/mnt/$app_name" "$install_dir/"
  hdiutil detach "$tmp/mnt" -quiet </dev/null || true

  # This is the step that prevents the Gatekeeper dialog.
  echo "▸ Clearing the quarantine flag..."
  xattr -dr com.apple.quarantine "$install_dir/$app_name" 2>/dev/null || true

  echo "▸ Launching..."
  open "$install_dir/$app_name" </dev/null

  echo
  echo "✅ Installed. Look for the pause icon in your menu bar."
  echo "   No Dock icon and no window — it lives entirely in the menu bar."
}

main "$@"
