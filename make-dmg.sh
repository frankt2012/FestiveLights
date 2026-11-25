#!/bin/bash
#
# Packages dist/FestiveLights.app as a styled, compressed DMG.
# Build first:
#   FESTIVELIGHTS_UPDATE_URL=https://raw.githubusercontent.com/frankt2012/FestiveLights/main/latest.json ./build.sh
#   ./make-dmg.sh
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="FestiveLights"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
APP_BUNDLE="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"
RW_DMG="dist/${APP_NAME}-rw.dmg"
STAGE="dist/${APP_NAME}-dmg-stage"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Missing $APP_BUNDLE — run ./build.sh first." >&2
    exit 1
fi

echo "▸ Staging ${DMG_PATH}…"
rm -rf "$STAGE" "$DMG_PATH" "$RW_DMG"
mkdir -p "$STAGE/.background"
ditto "$APP_BUNDLE" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
cp docs/images/dmg-background.png "$STAGE/.background/dmg-background.png"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDRW \
    "$RW_DMG" >/dev/null

MOUNT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | awk '/\/Volumes\// {print $NF; exit}')"
if [[ -z "${MOUNT:-}" ]]; then
    echo "Could not mount the writable DMG." >&2
    exit 1
fi

# Style the Finder window. If Finder scripting is unavailable, the DMG is
# still valid: the app and Applications shortcut are already in place.
osascript <<OSA >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 700, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to file ".background:dmg-background.png"
        set position of item "${APP_NAME}.app" of container window to {150, 212}
        set position of item "Applications" of container window to {450, 212}
        close
    end tell
end tell
OSA

# Make the volume show the app icon.
SetFile -a C "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" >/dev/null

echo "▸ Compressing…"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE"

(cd dist && shasum -a 256 "$(basename "$DMG_PATH")") | tee "${DMG_PATH}.sha256"
echo "▸ Built ${DMG_PATH}"
