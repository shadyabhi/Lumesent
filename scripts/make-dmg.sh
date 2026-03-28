#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/Lumesent.app"
VERSION="${VERSION:-$(cd "$REPO_ROOT" && echo "$(date +%Y%m%d)-$(git describe --always --dirty 2>/dev/null || echo 'unknown')")}"
DMG_NAME="Lumesent-${DMG_SUFFIX:-${VERSION}}"
DMG_DIR="$REPO_ROOT/.build/dmg"
DMG_RW="$REPO_ROOT/.build/dmg-rw.dmg"
DMG_PATH="$REPO_ROOT/$DMG_NAME.dmg"
VOL_NAME="Lumesent"

if [ ! -d "$APP" ]; then
    echo "Error: Lumesent.app not found. Run 'make build' first."
    exit 1
fi

# Clean previous artifacts
rm -rf "$DMG_DIR" "$DMG_RW" "$DMG_PATH"
mkdir -p "$DMG_DIR"

# Copy app into staging directory
cp -R "$APP" "$DMG_DIR/Lumesent.app"

# Symlink to /Applications for drag-to-install
ln -s /Applications "$DMG_DIR/Applications"

# Create a read-write DMG so we can customise the Finder view
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDRW \
    "$DMG_RW"

rm -rf "$DMG_DIR"

# Mount the read-write DMG
MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen | grep "/Volumes/$VOL_NAME" | awk '{print $NF}')
# Handle volume name with spaces — take everything after the last tab
MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen | grep "/Volumes/" | sed 's/.*\t//')

echo "Mounted at: $MOUNT_DIR"

# Configure Finder view via AppleScript
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 200, 900, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set text size of theViewOptions to 14
        set background color of theViewOptions to {60138, 60138, 60138}
        set position of item "Lumesent.app" of container window to {125, 140}
        set position of item "Applications" of container window to {375, 140}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Make sure .DS_Store is flushed
sync

# Detach
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force

# Convert to compressed read-only DMG
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

rm -f "$DMG_RW"

echo "Created $DMG_PATH"
