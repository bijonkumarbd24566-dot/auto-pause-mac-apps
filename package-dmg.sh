#!/bin/zsh
# Build a distributable DMG containing a universal Pause.app.
set -e
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
DMG="Pause-${VERSION}.dmg"
STAGE=".dmg-stage"

echo "▸ Building universal app..."
./build.sh --universal

echo "▸ Staging disk image contents..."
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R Pause.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Installing Pause
================

1. Drag Pause.app onto the Applications folder in this window.
2. Open Applications and right-click Pause -> Open, then confirm.

That second step is needed only the first time. Pause is signed
ad-hoc rather than notarized (it is free and open source), so macOS
asks for confirmation before the first launch.

Pause lives in your menu bar - look for the pause icon near the clock.
It has no Dock icon and no window.

Source and docs: https://github.com/fazalrshah/pause
TXT

echo "▸ Creating DMG..."
hdiutil create -volname "Pause" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

SIZE=$(du -h "$DMG" | cut -f1)
echo "✅ $PWD/$DMG ($SIZE)"
lipo -archs Pause.app/Contents/MacOS/Pause | sed 's/^/   architectures: /'
