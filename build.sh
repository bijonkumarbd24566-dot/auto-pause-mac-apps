#!/bin/zsh
# Build "Auto Pause Mac Apps.app". Requires only Xcode Command Line Tools — no Xcode needed.
#   ./build.sh              → native build for this Mac (fast, for development)
#   ./build.sh --universal  → Apple Silicon + Intel universal binary (for release)
set -e
cd "$(dirname "$0")"

UNIVERSAL=0
[[ "$1" == "--universal" ]] && UNIVERSAL=1

APP="Auto Pause Mac Apps.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if (( UNIVERSAL )); then
  # SwiftPM's --arch needs Xcode's xcbuild, which Command Line Tools don't ship.
  # Cross-compile each slice separately and stitch them with lipo instead.
  echo "▸ Building arm64 slice..."
  swift build -c release --scratch-path .build-arm64 \
    -Xswiftc -target -Xswiftc arm64-apple-macosx14.0
  echo "▸ Building x86_64 slice..."
  swift build -c release --scratch-path .build-x86_64 \
    -Xswiftc -target -Xswiftc x86_64-apple-macosx14.0
  echo "▸ Merging into a universal binary..."
  lipo -create -output "$APP/Contents/MacOS/AutoPauseMacApps" \
    .build-arm64/release/AutoPauseMacApps .build-x86_64/release/AutoPauseMacApps
else
  echo "▸ Building for $(uname -m)..."
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/AutoPauseMacApps" "$APP/Contents/MacOS/AutoPauseMacApps"
fi

cp Info.plist "$APP/Contents/Info.plist"
[[ -f AppIcon.icns ]] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a Developer ID if one is installed, otherwise fall back to ad-hoc.
# A Developer ID certificate requires a paid Apple Developer Program membership;
# without it macOS shows a Gatekeeper warning on first launch, which the Homebrew
# cask and install.sh both avoid by clearing the quarantine attribute.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')

if [[ -n "$IDENTITY" ]]; then
  echo "▸ Signing with: $IDENTITY"
  codesign --force --deep --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"
  echo "   Signed for distribution. Run ./notarize.sh to notarize."
else
  echo "▸ Signing (ad-hoc — no Developer ID certificate found)..."
  codesign --force --deep --sign - "$APP"
fi

echo "✅ Built $PWD/$APP"
lipo -archs "$APP/Contents/MacOS/AutoPauseMacApps" 2>/dev/null | sed 's/^/   architectures: /'
echo "   Install: cp -r \"Auto Pause Mac Apps.app\" /Applications/"
