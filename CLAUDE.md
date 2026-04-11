# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build                  # Release build + bundle .app
make run                    # Build, kill any running instance, and open .app
make dmg                    # Build + create installer DMG (version from git)
make clean                  # Remove .build/ and Lumesent.app/
swift build                 # Quick debug build (no .app bundle)
```

**After every code change, run `make run` to restart the app and verify.**

The .app bundle (`make build` / `make run`) is required for stable permission grants, hotkey registration, and the launchd login service. `swift run` works for quick iteration but permissions will not persist.

No tests, no linter, no third-party dependencies. Links against system `sqlite3` (via Package.swift). Logging uses `os.Logger` via `AppLog`. Targets macOS 14+.

View app logs: `Lumesent logs` (or `/usr/bin/log show --predicate 'subsystem == "com.shadyabhi.Lumesent"' --last 1h --info`). Do not use `process == "logger"` — that matches nothing useful for this app.

## Architecture

Lumesent is a macOS menu bar app that monitors system notifications, filters them by user-defined rules, and shows full-screen or banner alerts for matches (whitelist mode).

### Core Pipeline

```
NotificationMonitor → AppDelegate.handleNewNotification → FilterEngine.matchingRule → FullScreenAlertWindow
```

- **NotificationMonitor** — Hybrid detection: AXObserver watches `com.apple.notificationcenterui` for real-time triggers (staggered burst reads on each AX event to beat commit/dismiss races), plus a 1s fallback poll timer. Reads the system notification SQLite DB (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`, read-only WAL mode). Parses binary plist blobs from the `record` table (`req.titl`, `req.body`). If a burst finds no row while the DB is open, History may record a `speedy_dismiss` placeholder.
- **FilterEngine** — AND logic within a rule (all non-empty fields must match), OR across rules (any rule match triggers alert). Match operators: `.contains` (case-insensitive substring), `.equals` (case-insensitive full), `.regex` (NSRegularExpression).
- **FullScreenAlertWindow** — Borderless `NSWindow` at `.screenSaver` level. Two layouts: full-screen or banner (top of screen). Auto-dismisses after configurable timeout (default 8s) or on keypress/click. Supports multi-display and sticky mode.
- **AppDelegate** — Orchestrator. Owns the menu bar (`NSStatusItem`), wires monitor→filter→alert, hosts SettingsView/OnboardingView in NSWindows. Handles single-instance detection, permission watching, and hotkey registration.

### Persistence (all JSON in `~/Library/Application Support/Lumesent/`)

- **RuleStore** — `rules.json`. Import/export support.
- **AppSettings** — `settings.json`. Dismiss key, hotkeys, alert presentation, pause state, dock visibility.
- **NotificationHistory** — `history.json`. Up to 1000 entries (matched and unmatched). Powers rule-building suggestions in the UI.
- **FileLocations** — Centralizes all paths; creates directories on first access.

### External Notifications

CLI: `Lumesent send --title "…" [--subtitle "…"] [--body "…"] [--app-name "…"] [--display-mode sticky|timed] [--alert-type fullscreen|notification] [--source-app <bundle-id>] [--no-focus-source]`. Connects to the running app via a Unix domain socket (`notify.sock` in Application Support). Implemented via [`NotificationServer`](Sources/Lumesent/NotificationServer.swift) (server) and the `send` subcommand in [`main.swift`](Sources/Lumesent/main.swift) (client). Bypasses filter rules — always shows an alert (unless paused). Auto-detects tmux/iTerm source context for focus-on-dismiss.

### UI

SwiftUI views hosted in AppKit windows via `NSHostingView`. No storyboards/xibs. `main.swift` bootstraps `NSApplication` directly and enforces single-instance via `DistributedNotificationCenter`.

SettingsView is the largest file (~1900 lines): sidebar-based rules editor, unmatched notification history browser, and general settings.

### Key Behaviors

- **Deduplication**: 5-second window blocks duplicate notifications (same app+title+body).
- **Menu bar icon**: Reflects permission state (`bell.slash`, `bell.badge.clock`, etc.). Flashes `bell.fill` for 3s on match.
- **Permission-gated windows**: Settings/onboarding float at `.floating` level until both permissions granted, then revert to `.normal`.

## Permissions

The app requires **Full Disk Access** (notification DB readability) and **Accessibility** (AXObserver + hotkeys). `PermissionChecker` polls every 1s until both are granted. Missing permissions trigger onboarding dialogs at startup.

## Development Guidelines

- **JSON resilience**: The app must never crash due to invalid or incomplete JSON in persisted files (`rules.json`, `settings.json`, `history.json`). All `Codable` decoders use `decodeIfPresent` with sensible defaults for every field except true identifiers (`id`). Array loads use lossy per-element decoding so one corrupt entry doesn't discard the entire file. All file loads fall back to empty/default state on failure.
- **Sensible defaults**: When adding new persisted fields, always make them optional in the `Codable` struct and provide a default via `decodeIfPresent(...) ?? defaultValue`. This ensures existing user data files load correctly after upgrades.

## Commit Format

```
<component>: <describe feature>

<why we did it, what we did>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

Component is a short label for the area of the codebase (e.g. `monitor`, `filter`, `alerts`, `settings`, `cli`, `build`, `history`). The first line is a concise summary; the body explains motivation and approach.

## Build & Signing

`scripts/bundle.sh` creates the .app structure and resolves signing identity (prefers Apple Development > Developer ID > ad-hoc). Version comes from the git hash (locally) or the tag name (CI), substituted into Info.plist at build time.
