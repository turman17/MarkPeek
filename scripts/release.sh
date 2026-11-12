#!/bin/bash
# Cut a release: stamp the version, build and install, package the DMG and
# zip, print the cask sha256, and (with gh installed) publish a GitHub
# release. The in-app updater reads GitHub Releases, so publishing here is
# what makes "Check for Updates…" find the new version.
#
# Usage: scripts/release.sh 1.0.0
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version, e.g. 1.0.0>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is not clean. Commit or stash first." >&2
    exit 1
fi

echo "==> Stamping version $VERSION"
BUILD="$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' MarkPeek.xcodeproj/project.pbxproj | head -1) + 1 ))"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" MarkPeek.xcodeproj/project.pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD;/g" MarkPeek.xcodeproj/project.pbxproj
sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/" packaging/homebrew/markpeek.rb

echo "==> Building and installing"
bash scripts/build-and-install.sh

echo "==> Packaging"
OUT_DIR="$ROOT/.local/release" VERSION="$VERSION" bash scripts/create-dmg.sh
ZIP="$ROOT/.local/release/MarkPeek-v$VERSION.zip"
DMG="$ROOT/.local/release/MarkPeek-v$VERSION.dmg"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
sed -i '' "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" packaging/homebrew/markpeek.rb

echo ""
echo "Artifacts:  $ZIP"
echo "            $DMG"
echo "sha256:     $SHA256 (written to packaging/homebrew/markpeek.rb)"
echo ""

git add MarkPeek.xcodeproj/project.pbxproj packaging/homebrew/markpeek.rb
git commit -q -m "chore(release): $VERSION"
git tag "v$VERSION"
echo "Committed and tagged v$VERSION. Push with: git push && git push --tags"

if command -v gh >/dev/null 2>&1; then
    read -r -p "Create GitHub release v$VERSION and upload the zip and DMG? [y/N] " REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        git push && git push --tags
        gh release create "v$VERSION" "$ZIP" "$DMG" \
            --title "MarkPeek $VERSION" \
            --generate-notes
        echo "Release published. Copy packaging/homebrew/markpeek.rb into your homebrew-tap as Casks/markpeek.rb."
    fi
else
    echo "gh CLI not found — create the GitHub release manually and attach the zip and DMG."
fi
