#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/release"
APP="$REPO_ROOT/Lumesent.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD_DIR/Lumesent" "$APP/Contents/MacOS/Lumesent"
cp "$REPO_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo "Built $APP"
