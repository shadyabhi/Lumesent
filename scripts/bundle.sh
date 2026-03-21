#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/release"
APP="$REPO_ROOT/Lumesent.app"
VERSION="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"

# macOS privacy (Full Disk Access, Accessibility) follows the app’s signing identity. Ad-hoc (`-`)
# effectively changes identity every rebuild (new CDHash), so TCC no longer matches. Use any
# Apple-issued signing identity (Apple Development is free with an Apple ID in Xcode); see
# `make codesign-bootstrap` if `security find-identity -v -p codesigning` is empty.
find_identity_matching() {
  local pattern="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' -v pat="$pattern" 'index($2, pat) == 1 { print $2; exit }'
}

# First " 1) HEX "Name"" line from security find-identity (any valid signing identity).
first_listed_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^[[:space:]]*[0-9][0-9]*)[[:space:]][0-9A-Fa-f]*[[:space:]]"\([^"]*\)".*/\1/p' \
    | head -n 1
}

resolve_sign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return
  fi
  local id=""
  # Prefer common Apple labels, then any valid identity (e.g. enterprise / custom names).
  id=$(find_identity_matching "Apple Development:")
  [[ -z "$id" ]] && id=$(find_identity_matching "Developer ID Application:")
  [[ -z "$id" ]] && id=$(find_identity_matching "Mac Developer:")
  [[ -z "$id" ]] && id=$(find_identity_matching "Apple Distribution:")
  [[ -z "$id" ]] && id="$(first_listed_signing_identity)"
  if [[ -n "$id" ]]; then
    printf '%s' "$id"
    return
  fi
  echo "bundle.sh: warning: No code signing identity in your keychain; using ad-hoc sign." >&2
  echo "bundle.sh: Full Disk Access & Accessibility reset after each rebuild. Run: make codesign-bootstrap" >&2
  printf '%s' '-'
}

SIGN_ID="$(resolve_sign_identity)"
if [[ "$SIGN_ID" == "-" ]]; then
  CS_EXTRA=()
else
  # Avoid requiring Apple's timestamp server for local iteration
  CS_EXTRA=(--timestamp=none)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD_DIR/Lumesent" "$APP/Contents/MacOS/Lumesent"
sed "s/__VERSION__/$VERSION/g" "$REPO_ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

codesign --force --sign "$SIGN_ID" "${CS_EXTRA[@]}" "$APP/Contents/MacOS/Lumesent"
codesign --force --sign "$SIGN_ID" "${CS_EXTRA[@]}" "$APP"

echo "Built $APP"
