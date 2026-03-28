#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/release"
APP="$REPO_ROOT/Lumesent.app"
VERSION="${VERSION:-$(cd "$REPO_ROOT" && printf '%s-%s' "$(date +%Y%m%d)" "$(git describe --always --dirty 2>/dev/null || echo unknown)")}"

# macOS privacy (Full Disk Access, Accessibility) follows the app's signing identity. Ad-hoc (`-`)
# effectively changes identity every rebuild (new CDHash), so TCC no longer matches. Use any
# Apple-issued signing identity (Apple Development is free with an Apple ID in Xcode); see
# `make codesign-bootstrap` if `security find-identity -v -p codesigning` is empty.

resolve_sign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return
  fi
  local all_ids
  all_ids="$(security find-identity -v -p codesigning 2>/dev/null)"
  # Prefer common Apple labels, then any valid identity (e.g. enterprise / custom names).
  for pattern in "Apple Development:" "Developer ID Application:" "Mac Developer:" "Apple Distribution:"; do
    local id
    id="$(echo "$all_ids" | awk -F'"' -v pat="$pattern" 'index($2, pat) == 1 { print $2; exit }')"
    if [[ -n "$id" ]]; then
      printf '%s' "$id"
      return
    fi
  done
  # Fall back to first listed identity.
  local id
  id="$(echo "$all_ids" | sed -n 's/^[[:space:]]*[0-9][0-9]*)[[:space:]][0-9A-Fa-f]*[[:space:]]"\([^"]*\)".*/\1/p' | head -n 1)"
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

CS_EXTRA=()
if [[ "$SIGN_ID" != "-" ]]; then
  # Skip Apple's timestamp server — not needed without notarization
  CS_EXTRA=(--timestamp=none)
fi

sign() { codesign --force --options runtime --sign "$SIGN_ID" "${CS_EXTRA[@]}" "$@"; }

echo "bundle.sh: Signing with: ${SIGN_ID}" >&2

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/Lumesent" "$APP/Contents/MacOS/Lumesent"
sed "s/__VERSION__/$VERSION/g" "$REPO_ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
cp "$REPO_ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# ── Embed Sparkle.framework ──
SPARKLE_FW=$(find "$REPO_ROOT/.build/artifacts" -path "*/macos-*/Sparkle.framework" -type d | head -1)
if [[ -z "$SPARKLE_FW" ]]; then
    echo "bundle.sh: ERROR: Sparkle.framework not found in .build/artifacts" >&2
    exit 1
fi

mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

# Ensure executable has rpath to find embedded frameworks
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Lumesent" 2>/dev/null || true

# Sign Sparkle framework components inside-out (required for --deep --strict verification).
# --options runtime (in sign()) enables hardened runtime, required for XPC service validation.
SPARK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
find "$APP/Contents/Frameworks/Sparkle.framework" -name "*.xpc" -type d | while read -r xpc; do
    sign "$xpc"
done
[[ -d "$SPARK/Updater.app" ]] && sign "$SPARK/Updater.app"
[[ -f "$SPARK/Autoupdate" ]]  && sign "$SPARK/Autoupdate"
sign "$APP/Contents/Frameworks/Sparkle.framework"

sign "$APP/Contents/MacOS/Lumesent"
sign "$APP"

echo "Built $APP"
