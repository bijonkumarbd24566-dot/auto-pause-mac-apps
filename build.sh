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

echo "▸ Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

echo "✅ Built $PWD/$APP"
lipo -archs "$APP/Contents/MacOS/AutoPauseMacApps" 2>/dev/null | sed 's/^/   architectures: /'
echo "   Install: cp -r \"Auto Pause Mac Apps.app\" /Applications/"
