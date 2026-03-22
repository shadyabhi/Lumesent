# Lumesent

A macOS menu bar app that monitors system notifications and shows full-screen alerts when they match user-defined rules. Think of it as a whitelist-mode notification filter — only the notifications you care about break through, and they do so unmissably.

## Install

### From DMG

Download `Lumesent-<version>.dmg` from the [latest release](https://github.com/shadyabhi/Lumesent/releases/latest), open it, and drag `Lumesent.app` to Applications.

### From source

```bash
git clone https://github.com/shadyabhi/Lumesent.git && cd Lumesent
make build        # builds and bundles Lumesent.app
open Lumesent.app
```

Use the `.app` bundle (not `swift run`) for stable permission grants.

**Requirements:** macOS 14 (Sonoma)+, Xcode Command Line Tools. No third-party dependencies.

## Permissions

On first launch Lumesent will prompt for two macOS permissions:

| Permission | Why |
|---|---|
| **Full Disk Access** | Read the system notification database |
| **Accessibility** | Observe notification center UI events in real time |

Grant both in **System Settings > Privacy & Security**. The app detects missing permissions at startup and shows a dialog.

## Usage

Lumesent lives in the menu bar. Click the icon to:

- **Add / edit rules** — each rule can match on app name, notification title, and/or body. Match operators: substring (case-insensitive), exact match, or regex. All non-empty fields in a rule must match (AND); any matching rule triggers the alert (OR).
- **View recent matches** — see which notifications triggered alerts.

When a notification matches a rule, a full-screen alert appears and auto-dismisses after 8 seconds (or on any keypress/click).

Rules are stored in `~/Library/Application Support/Lumesent/rules.json`.

## Development

```bash
make build    # Release build + bundle .app
make run      # Build, kill running instance, open .app
make dmg      # Build + create installer DMG
make clean    # Remove build artifacts
swift build   # Quick debug build (no .app bundle)
```
