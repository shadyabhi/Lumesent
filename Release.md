# Release Process

Lumesent uses a free Apple Development certificate for code signing. This gives releases a stable Team ID so users keep their TCC permissions (Full Disk Access, Accessibility) across upgrades. Users still need right-click → Open on first launch (no notarization without a paid Developer ID).

## One-Time Setup

### 1. Create a free Apple Development certificate

- Open Xcode → Settings → Accounts → add your Apple ID
- Select your team → Manage Certificates → "+" → Apple Development

### 2. Export the certificate as .p12

- Open Keychain Access → My Certificates
- Find "Apple Development: your@email.com (TEAMID)"
- Right-click → Export → save as `dev-cert.p12`, set a password

### 3. Add the certificate to GitHub

```bash
base64 -i dev-cert.p12 | pbcopy
```

Go to GitHub repo → Settings → Secrets and variables → Actions, and add:

| Secret | Value |
|---|---|
| `CERTIFICATE_P12` | Paste the base64 string from your clipboard |
| `CERTIFICATE_PASSWORD` | The password you set in step 2 |

Then delete the local `.p12` file:

```bash
rm dev-cert.p12
```

## Creating a Release

```bash
# Tag and push — version is derived from the tag name
git tag v0.2.0
git push origin v0.2.0
```

This triggers the GitHub Actions workflow which:
1. Imports the signing certificate into a temporary CI keychain
2. Runs `make dmg` (same command you use locally)
3. Creates a **draft** GitHub Release with the signed DMG attached

Review the draft release on GitHub, then publish when ready.

## Testing a Release Locally

The local `make dmg` uses the exact same code path as CI. Since your Apple Development cert is in your keychain, it produces an identically signed DMG:

```bash
make dmg
```

Verify the signing identity matches what CI would produce:

```bash
codesign -dvvv Lumesent.app 2>&1 | grep "Authority\|TeamIdentifier"
```

For a quick throwaway DMG (ad-hoc, permissions won't persist):

```bash
CODESIGN_IDENTITY="-" make dmg
```

## Certificate Renewal

Free Apple Development certificates expire after **1 year**. When it expires:

1. Xcode → Settings → Accounts → Manage Certificates → "+" → Apple Development
2. Re-export as `.p12` and base64-encode (steps 2-3 from setup)
3. Update the `CERTIFICATE_P12` and `CERTIFICATE_PASSWORD` secrets in GitHub

The new cert keeps the same Team ID, so users keep their permissions.

## How Signing Works

macOS TCC ties permissions to the app's code signing identity (Team ID + bundle ID). The signing identity is resolved by `scripts/bundle.sh` in this order:

1. `CODESIGN_IDENTITY` env var (if set)
2. `Apple Development:` certificate in keychain
3. Any other valid signing identity
4. Ad-hoc (`-`) as last resort — permissions reset on every install

A safeguard in `bundle.sh` blocks `Developer ID` and `Apple Distribution` certificates (which are for paid distribution) unless `ALLOW_DISTRIBUTION_SIGN=1` is explicitly set.
