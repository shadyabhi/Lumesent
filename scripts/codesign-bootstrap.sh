#!/bin/bash
# macOS ties Full Disk Access and Accessibility to a stable code-signing identity.
# Ad-hoc signing (`codesign -s -`) embeds the binary hash, so every rebuild looks like a new app.
# This script checks for a usable identity and prints how to create a free Apple Development cert.
set -euo pipefail

list_identities() {
  security find-identity -v -p codesigning 2>/dev/null || true
}

if list_identities | grep -qE '^[[:space:]]+[0-9]+\)[[:space:]]+[0-9A-Fa-f]+[[:space:]]+"'; then
  echo "Code signing identities available (bundle.sh will use one automatically):"
  list_identities
  exit 0
fi

# Cert + key exist but chain is untrusted → "1 identities" / "0 valid" in `security find-identity -v`.
if security find-identity -v 2>/dev/null | grep -q 'CSSMERR_TP_NOT_TRUSTED'; then
  echo "Apple Development certificate is installed but not trusted (CSSMERR_TP_NOT_TRUSTED)." >&2
  echo "That is why \`security find-identity -v -p codesigning\` shows 0 valid identities and bundle.sh uses ad-hoc signing." >&2
  echo "" >&2
  echo "Fix (try in order):" >&2
  echo "  1. Use full Xcode as the active developer directory (not only Command Line Tools):" >&2
  echo "       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  echo "     Open Xcode once; accept license if prompted." >&2
  echo "  2. Keychain Access → login → search \"Worldwide Developer\"." >&2
  echo "     Ensure Apple’s WWDR intermediate (e.g. G4) is present and trusted." >&2
  echo "     If missing: https://www.apple.com/certificateauthority/ — install the" >&2
  echo "     \"Worldwide Developer Relations\" / WWDR intermediate, then retry." >&2
  echo "  3. Re-run: security find-identity -v -p codesigning" >&2
  echo "     (You want a numbered line with no CSSMERR_ error in parentheses.)" >&2
  echo "" >&2
  security find-identity -v 2>/dev/null | grep -E 'Apple Development|CSSMERR_|valid identities' || true
  exit 0
fi

echo "No valid code signing identities found." >&2
echo "" >&2
echo "Without an Apple Development (or Developer ID) certificate, scripts/bundle.sh uses ad-hoc" >&2
echo "signing. macOS then treats each rebuild as a different app, so Full Disk Access and" >&2
echo "Accessibility must be granted again after every \`make build\` / \`make run\`." >&2
echo "" >&2
echo "One-time fix (free Apple ID):" >&2
echo "  1. Install Xcode from the App Store (or Xcode command line tools + full Xcode for certs)." >&2
echo "  2. Open Xcode → Settings → Accounts → \"+\" → sign in with your Apple ID." >&2
echo "  3. Select your team → Manage Certificates → \"+\" → Apple Development." >&2
echo "  4. Run: security find-identity -v -p codesigning" >&2
echo "     You should see a line like: \"Apple Development: you@example.com (TEAMID)\"" >&2
echo "  5. Run \`make build\` again (no need to set CODESIGN_IDENTITY unless you have several identities)." >&2
echo "" >&2
echo "Optional: export CODESIGN_IDENTITY='Apple Development: …' to pin a specific identity." >&2
exit 0
