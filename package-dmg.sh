#!/bin/zsh
# Build a distributable DMG containing a universal "Auto Pause Mac Apps.app".
set -e
cd "$(dirname "$0")"

VERSION="${1:-1.1.0}"
DMG="AutoPauseMacApps-${VERSION}.dmg"
STAGE=".dmg-stage"

echo "▸ Building universal app..."
./build.sh --universal

echo "▸ Staging disk image contents..."
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "Auto Pause Mac Apps.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Installing Auto Pause Mac Apps
==============================

1. Drag "Auto Pause Mac Apps" onto the Applications folder in this window.
2. Open Applications, right-click the app -> Open, then confirm.

That second step is needed only the first time. The app is signed
ad-hoc rather than notarized (it is 100% free and open source), so
macOS asks for confirmation before the first launch.

It lives in your menu bar - look for the pause icon near the clock.
There is no Dock icon and no window.

Source and docs: https://github.com/fazalrshah/auto-pause-mac-apps
TXT

echo "▸ Creating DMG..."
hdiutil create -volname "Auto Pause Mac Apps" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

SIZE=$(du -h "$DMG" | cut -f1)
echo "✅ $PWD/$DMG ($SIZE)"
lipo -archs "Auto Pause Mac Apps.app/Contents/MacOS/AutoPauseMacApps" | sed 's/^/   architectures: /'
