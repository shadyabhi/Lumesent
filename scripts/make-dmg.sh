#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/Lumesent.app"
VERSION="${VERSION:-$(cd "$REPO_ROOT" && echo "$(date +%Y%m%d)-$(git describe --always --dirty 2>/dev/null || echo 'unknown')")}"
DMG_NAME="Lumesent-${VERSION}"
DMG_DIR="$REPO_ROOT/.build/dmg"
DMG_PATH="$REPO_ROOT/$DMG_NAME.dmg"
VOL_NAME="Lumesent"

if [ ! -d "$APP" ]; then
    echo "Error: Lumesent.app not found. Run 'make build' first."
    exit 1
fi

# Clean previous artifacts
rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"

# Copy app into staging directory
cp -R "$APP" "$DMG_DIR/Lumesent.app"

# Symlink to /Applications for drag-to-install
ln -s /Applications "$DMG_DIR/Applications"

# Create compressed DMG directly (no Finder window)
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_DIR"

echo "Created $DMG_PATH"
