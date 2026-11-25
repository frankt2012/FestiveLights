#!/bin/bash
#
# Builds FestiveLights and assembles a proper .app bundle (needed for
# LSUIElement to take effect). Usage:
#
#   ./build.sh          build the app bundle into dist/
#   ./build.sh run      build and launch the dist copy
#   ./build.sh install  build, install to /Applications, and launch
#
set -euo pipefail

cd "$(dirname "$0")"

CONFIGURATION="release"
APP_NAME="FestiveLights"
APP_BUNDLE="dist/${APP_NAME}.app"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

echo "▸ Compiling (${CONFIGURATION})…"
swift build -c "$CONFIGURATION"

echo "▸ Assembling ${APP_BUNDLE}…"
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Optionally bake in an update-feed URL for this build:
#   FESTIVELIGHTS_UPDATE_URL=https://example.com/latest.json ./build.sh
if [[ -n "${FESTIVELIGHTS_UPDATE_URL:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :FestiveLightsUpdateURL ${FESTIVELIGHTS_UPDATE_URL}" \
        "${APP_BUNDLE}/Contents/Info.plist"
fi

# Ad-hoc signature so macOS can launch it locally without a developer account.
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "▸ Built ${APP_BUNDLE}"

if [[ "${1:-}" == "install" ]]; then
    DEST="/Applications/${APP_NAME}.app"
    echo "▸ Installing to ${DEST}…"
    if [[ -w /Applications ]]; then
        pkill -x "${APP_NAME}" 2>/dev/null || true
        sleep 0.5
        rm -rf "$DEST"
        ditto "$APP_BUNDLE" "$DEST"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        echo "▸ Installed. Launching…"
        open "$DEST"
    else
        echo "No write access to /Applications."
        echo "Drag ${APP_BUNDLE} into /Applications instead."
    fi
elif [[ "${1:-}" == "run" ]]; then
    echo "▸ Launching…"
    open "$APP_BUNDLE"
else
    echo
    echo "Install it with:"
    echo "  ./build.sh install"
    echo "Run the dist copy with:"
    echo "  open ${APP_BUNDLE}"
fi
