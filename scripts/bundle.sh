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

# Safety: refuse to sign with a Developer ID or Distribution cert unless explicitly acknowledged.
# These certs are for publishing to other users — not for local dev builds.
if [[ "$SIGN_ID" != "-" ]] && { [[ "$SIGN_ID" == *"Developer ID"* ]] || [[ "$SIGN_ID" == *"Distribution"* ]]; }; then
  if [[ -z "${ALLOW_DISTRIBUTION_SIGN:-}" ]]; then
    echo "bundle.sh: ERROR: Refusing to sign with distribution cert: $SIGN_ID" >&2
    echo "bundle.sh: This cert is for publishing apps to other users." >&2
    echo "bundle.sh: For local dev, use 'Apple Development' (free). For DMGs, use ad-hoc (make dmg)." >&2
    echo "bundle.sh: To override, set ALLOW_DISTRIBUTION_SIGN=1" >&2
    exit 1
  fi
fi

if [[ "$SIGN_ID" == "-" ]]; then
  CS_EXTRA=()
else
  # Skip Apple's timestamp server — not needed without notarization
  CS_EXTRA=(--timestamp=none)
fi

echo "bundle.sh: Signing with: ${SIGN_ID}" >&2

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD_DIR/Lumesent" "$APP/Contents/MacOS/Lumesent"
sed "s/__VERSION__/$VERSION/g" "$REPO_ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
cp "$REPO_ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$REPO_ROOT/Resources/Lumesent.sdef" "$APP/Contents/Resources/Lumesent.sdef"

codesign --force --sign "$SIGN_ID" "${CS_EXTRA[@]}" "$APP/Contents/MacOS/Lumesent"
codesign --force --sign "$SIGN_ID" "${CS_EXTRA[@]}" "$APP"

echo "Built $APP"
