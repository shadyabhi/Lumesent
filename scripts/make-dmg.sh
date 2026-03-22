#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/Lumesent.app"
VERSION="${VERSION:-$(cd "$REPO_ROOT" && git describe --always --dirty 2>/dev/null || echo 'unknown')}"
DMG_NAME="Lumesent-${VERSION}"
DMG_DIR="$REPO_ROOT/.build/dmg"
DMG_TEMP="$REPO_ROOT/.build/$DMG_NAME-temp.dmg"
DMG_PATH="$REPO_ROOT/$DMG_NAME.dmg"
VOL_NAME="Lumesent"

if [ ! -d "$APP" ]; then
    echo "Error: Lumesent.app not found. Run 'make build' first."
    exit 1
fi

# Clean previous artifacts
rm -rf "$DMG_DIR" "$DMG_TEMP" "$DMG_PATH"
mkdir -p "$DMG_DIR"

# Copy app into staging directory
cp -R "$APP" "$DMG_DIR/Lumesent.app"

# Create a Finder alias to /Applications (preserves the proper folder icon,
# unlike a Unix symlink which shows a generic icon in DMGs)
osascript <<EOF
tell application "Finder"
    set appFolder to POSIX file "/Applications" as alias
    make new alias file at (POSIX file "$DMG_DIR" as alias) to appFolder
    set name of result to "Applications"
end tell
EOF

# Create a read-write DMG first so we can customize the Finder view
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDRW \
    "$DMG_TEMP"

# Mount without Finder auto-opening the volume (-noautoopen). Otherwise macOS opens
# one window on attach and our AppleScript opens another, leaving two windows.
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" | head -1 | awk '{print $1}')
MOUNT_DIR="/Volumes/$VOL_NAME"
# Give Finder time to notice the volume
sleep 2

# Use AppleScript to set icon size, window size, and icon positions
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 640, 400}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "Lumesent.app" of container window to {140, 150}
        set position of item "Applications" of container window to {400, 150}
        close
        open
        update without registering applications
    end tell
end tell
APPLESCRIPT

# Make sure writes are flushed
sync
sleep 2

# Unmount
hdiutil detach "$DEVICE" -quiet

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" -format UDZO -o "$DMG_PATH"

rm -f "$DMG_TEMP"
rm -rf "$DMG_DIR"

echo "Created $DMG_PATH"
