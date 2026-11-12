#!/bin/bash
# Package /Applications/MarkPeek.app (built by build-and-install.sh) as a DMG
# and a zip. The zip is what the in-app updater downloads from GitHub Releases.
#
#   bash scripts/create-dmg.sh                 # writes to .local/release
#   OUT_DIR=~/Desktop bash scripts/create-dmg.sh
#
# Requires create-dmg (brew install create-dmg).
set -euo pipefail

APP_NAME="MarkPeek"
APP_PATH="/Applications/${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${VERSION:-$(defaults read "${APP_PATH}/Contents/Info.plist" CFBundleShortVersionString)}"
NAME="${APP_NAME}-v${VERSION}"
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/.local/release}"
DMG_OUTPUT="${OUT_DIR}/${NAME}.dmg"
ZIP_OUTPUT="${OUT_DIR}/${NAME}.zip"
BG_IMAGE="${PROJECT_DIR}/docs/dmg-background.tiff"

command -v create-dmg >/dev/null || { echo "create-dmg is missing: brew install create-dmg" >&2; exit 1; }
[ -d "$APP_PATH" ] || { echo "$APP_PATH not found. Run scripts/build-and-install.sh first." >&2; exit 1; }
codesign --verify --deep --strict "$APP_PATH"

mkdir -p "$OUT_DIR"
STAGING="$(mktemp -d "/tmp/${NAME}-staging.XXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating ${NAME}.dmg"
rm -f "$DMG_OUTPUT" "$ZIP_OUTPUT"
create-dmg \
    --volname "$APP_NAME" \
    --background "$BG_IMAGE" \
    --window-pos 200 200 \
    --window-size 660 400 \
    --icon-size 80 \
    --icon "${APP_NAME}.app" 190 180 \
    --icon "Applications" 470 180 \
    --hide-extension "${APP_NAME}.app" \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$STAGING"

echo "==> Creating ${NAME}.zip (used by Check for Updates)"
ditto -c -k --keepParent "$STAGING/${APP_NAME}.app" "$ZIP_OUTPUT"

echo ""
echo "DMG: $DMG_OUTPUT"
echo "ZIP: $ZIP_OUTPUT"
ls -lh "$DMG_OUTPUT" "$ZIP_OUTPUT"
