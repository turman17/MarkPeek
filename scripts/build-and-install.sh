#!/bin/bash
# Build MarkPeek, sign, install to /Applications, and register the Quick Look extension.
#
# Signing identity: set SIGNING_IDENTITY env var to override.
# Defaults to the first Apple Development certificate in the keychain so the
# signature stays stable across rebuilds (permissions persist); falls back to
# ad-hoc ("-") when no certificate is available.
set -euo pipefail

cd "$(dirname "$0")/.."

# Use the full Xcode even when the command-line tools are the selected developer dir.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version >/dev/null 2>&1; then
    if [ -d /Applications/Xcode.app ]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi
if ! xcodebuild -version >/dev/null 2>&1; then
    echo "xcodebuild isn't usable. Install Xcode and accept its license:" >&2
    echo "    sudo xcodebuild -license accept" >&2
    xcodebuild -version 2>&1 | head -3 >&2 || true
    exit 1
fi

if [ -z "${SIGNING_IDENTITY:-}" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
    SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
fi
echo "==> Signing identity: $SIGNING_IDENTITY"
CONFIGURATION="${CONFIGURATION:-Release}"

echo "==> Building MarkPeek ($CONFIGURATION)..."
xcodebuild -project MarkPeek.xcodeproj \
    -scheme MarkPeek \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath .local/DerivedData \
    -clonedSourcePackagesDirPath .local/DerivedData/SourcePackages \
    build

BUILT_APP=".local/DerivedData/Build/Products/${CONFIGURATION}/MarkPeek.app"
BUILT_APPEX="${BUILT_APP}/Contents/PlugIns/MarkPeekQuickLook.appex"
BUILT_THUMB="${BUILT_APP}/Contents/PlugIns/MarkPeekThumbnail.appex"

echo "==> Signing MarkPeekQuickLook with entitlements..."
codesign -f -s "$SIGNING_IDENTITY" \
    --entitlements MarkPeekQuickLook/MarkPeekQuickLook.entitlements \
    --options runtime \
    "$BUILT_APPEX"

echo "==> Signing MarkPeekThumbnail with entitlements..."
codesign -f -s "$SIGNING_IDENTITY" \
    --entitlements MarkPeekThumbnail/MarkPeekThumbnail.entitlements \
    --options runtime \
    "$BUILT_THUMB"

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
pluginkit -a "$DEST/Contents/PlugIns/MarkPeekThumbnail.appex"
pluginkit -e use -i com.markpeek.app.Thumbnail

echo "==> Resetting Quick Look cache..."
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo ""
echo "Done. Select a .md file in Finder and press Space."
echo "If you still see raw text, open /Applications/MarkPeek.app once, then check"
echo "System Settings > General > Login Items & Extensions > Quick Look."
