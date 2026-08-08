#!/bin/bash
# Build MarkPeek, sign, install to /Applications, and register the Quick Look extension.
#
# Signing identity: set SIGNING_IDENTITY env var for distribution.
# For development/testing, defaults to ad-hoc signing ("-").
set -euo pipefail

cd "$(dirname "$0")/.."

SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
CONFIGURATION="${CONFIGURATION:-Release}"

echo "==> Building MarkPeek ($CONFIGURATION)..."
xcodebuild -project MarkPeek.xcodeproj \
    -scheme MarkPeek \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath .local/DerivedData \
    build

BUILT_APP=".local/DerivedData/Build/Products/${CONFIGURATION}/MarkPeek.app"
BUILT_APPEX="${BUILT_APP}/Contents/PlugIns/MarkPeekQuickLook.appex"

echo "==> Signing MarkPeekQuickLook with entitlements..."
codesign -f -s "$SIGNING_IDENTITY" \
    --entitlements MarkPeekQuickLook/MarkPeekQuickLook.entitlements \
    --options runtime \
    "$BUILT_APPEX"

echo "==> Signing MarkPeek with entitlements..."
codesign -f -s "$SIGNING_IDENTITY" \
    --entitlements MarkPeek/MarkPeek.entitlements \
    --options runtime \
    "$BUILT_APP"

DEST="/Applications/MarkPeek.app"
echo "==> Installing to $DEST..."
rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"

echo "==> Registering with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$DEST"

echo "==> Registering and enabling the Quick Look extension..."
pluginkit -a "$DEST/Contents/PlugIns/MarkPeekQuickLook.appex"
pluginkit -e use -i com.markpeek.app.QuickLook

echo "==> Resetting Quick Look cache..."
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo ""
echo "Done. Select a .md file in Finder and press Space."
echo "If you still see raw text, open /Applications/MarkPeek.app once, then check"
echo "System Settings > General > Login Items & Extensions > Quick Look."
