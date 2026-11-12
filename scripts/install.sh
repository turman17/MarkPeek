#!/bin/bash
# Install or update MarkPeek from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/turman17/MarkPeek/main/scripts/install.sh | bash
#
# Downloads the release zip, replaces /Applications/MarkPeek.app, clears the
# quarantine flag (the app is not notarized), and refreshes Quick Look.
# Pin a version with: ... | MARKPEEK_VERSION=1.0.0 bash
set -euo pipefail

REPO="turman17/MarkPeek"
APP="MarkPeek.app"
DEST="/Applications"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "MarkPeek is a macOS app." >&2
    exit 1
fi

if [ -n "${MARKPEEK_VERSION:-}" ]; then
    API="https://api.github.com/repos/$REPO/releases/tags/v${MARKPEEK_VERSION#v}"
else
    API="https://api.github.com/repos/$REPO/releases/latest"
fi

echo "==> Looking up the release"
ZIP_URL="$(curl -fsSL "$API" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
if [ -z "$ZIP_URL" ]; then
    echo "No zip found in the release at $API" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading $(basename "$ZIP_URL")"
curl -fL --progress-bar "$ZIP_URL" -o "$TMP/MarkPeek.zip"
ditto -x -k "$TMP/MarkPeek.zip" "$TMP"

if [ ! -d "$TMP/$APP" ]; then
    echo "The archive does not contain $APP" >&2
    exit 1
fi

SUDO=""
if [ ! -w "$DEST" ] || { [ -e "$DEST/$APP" ] && [ ! -w "$DEST/$APP" ]; }; then
    SUDO="sudo"
    echo "==> $DEST needs administrator rights"
fi

osascript -e 'tell application id "com.markpeek.app" to quit' >/dev/null 2>&1 || true

echo "==> Installing to $DEST/$APP"
$SUDO rm -rf "$DEST/$APP"
$SUDO ditto "$TMP/$APP" "$DEST/$APP"
$SUDO xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

qlmanage -r >/dev/null 2>&1 || true

echo ""
echo "MarkPeek is installed. Launch it once from Applications; it updates itself from then on."
echo "If Finder previews still show raw text, enable MarkPeek under"
echo "System Settings > General > Login Items & Extensions > Quick Look."
