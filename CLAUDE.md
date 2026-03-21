# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build                  # Release build + bundle .app
make run                    # Build, kill any running instance, and open .app
make clean                  # Remove .build/ and Lumesent.app/
swift build                 # Quick debug build (no .app bundle)
swift run                   # Run from source (dev, no .app bundle)
```

The .app bundle (`make build` / `make run`) is required for stable permission grants and the optional launchd login service.

No tests, no linter. **Sparkle** is the only third-party dependency (SPM); `scripts/bundle.sh` copies `Sparkle.framework` into the `.app`. Links against system `sqlite3`. Logging uses `os.Logger` via `AppLog`.

## Architecture

Lumesent is a macOS menu bar app that monitors system notifications, filters them by user-defined rules, and shows full-screen alerts for matches (whitelist mode).

**Pipeline:** NotificationMonitor → AppDelegate → FilterEngine → FullScreenAlertWindow

- **NotificationMonitor** — Hybrid detection: AXObserver watches `com.apple.notificationcenterui` for real-time triggers, plus a 5s fallback poll timer. Reads `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (SQLite, read-only, WAL mode). Parses binary plist blobs from the `record` table (`req.titl`, `req.body`).
- **FilterEngine** — Rules use AND logic within a rule (all non-empty fields must match), OR across rules (any rule match triggers alert). Case-insensitive substring matching.
- **FullScreenAlertWindow** — Borderless `NSWindow` at `.screenSaver` level. Auto-dismisses after 8s or on any keypress/click.
- **RuleStore** — JSON persistence at `~/Library/Application Support/Lumesent/rules.json`.
- **AppDelegate** — Orchestrator. Owns the menu bar (`NSStatusItem`), wires monitor→filter→alert, hosts SettingsView in an NSWindow.

UI uses SwiftUI views hosted in AppKit windows via `NSHostingView`. App bootstraps `NSApplication` directly in `main.swift` (no storyboards/xibs).

## Permissions

The app requires **Full Disk Access** (notification DB) and **Accessibility** (AXObserver). Missing permissions are detected at startup with user-facing dialogs.
