# AppleScript and external alerts

Lumesent exposes a **Cocoa Scripting** command so other tools can show an alert without using filter rules. Use **AppleScript** (`Script Editor`, `osascript`) or **JavaScript for Automation** (`osascript -l JavaScript`).

The scripting interface is defined in [`Resources/Lumesent.sdef`](Resources/Lumesent.sdef) and handled in code by [`SendExternalAlertScriptCommand`](Sources/Lumesent/SendExternalAlertScriptCommand.swift).

## Requirements

1. **Lumesent must already be running** (menu bar app from the `.app` bundle). Apple events are delivered to the live process.
2. Use the **bundled app** (`Lumesent.app`) for a stable experience; scripting targets the app by name **"Lumesent"** (see `CFBundleName` in `Info.plist`).
3. **Automation (Privacy & Security)**  
   The app that *sends* the script (Terminal, iTerm, `osascript` invoked from another app, Shortcuts, etc.) may need permission to control Lumesent. macOS prompts the first time; if delivery fails, check **System Settings → Privacy & Security → Automation**.

## Command: `send external alert`

AppleScript form:

```applescript
tell application "Lumesent" to send external alert «title»
```

`«title»` is the **direct parameter** (required): the alert title as text.

### Optional labeled parameters

Add any combination of these after the title (order does not matter in AppleScript):

| Parameter | Type | Meaning |
|-----------|------|---------|
| `body text` | text | Secondary body line. |
| `application name` | text | Label shown as the app/source name (default in app logic: `"External"`). |
| `display mode` | text | `"sticky"` keeps the alert until dismissed; anything else (including omitting) uses the normal timed/banner behavior. |
| `alert type` | text | `"fullscreen"` (default) or `"notification"` (Notification Center; still needs notification permission in System Settings). |
| `focus source terminal` | boolean | Passed through to the same focus logic as in-app alerts. Defaults to **true** when omitted. Scripts do not populate tmux/iTerm **source context**, so this flag usually has no visible effect for pure `osascript` / AppleScript calls. |

### Behavior

- External alerts **ignore filter rules** and are shown whenever Lumesent is **not paused**.
- If Lumesent is **paused**, the command succeeds but no alert is shown (same as other external paths).

## Examples (AppleScript)

Minimal title only:

```applescript
tell application "Lumesent" to send external alert "Deploy finished"
```

Title and body:

```applescript
tell application "Lumesent" to send external alert "Build failed" body text "exit code 1"
```

CI-style label and sticky fullscreen alert:

```applescript
tell application "Lumesent" to send external alert "Done" application name "CI" display mode "sticky"
```

Native Notification Center instead of fullscreen:

```applescript
tell application "Lumesent" to send external alert "Heads up" body text "From automation" alert type "notification"
```

Do not try to refocus a source terminal after dismiss:

```applescript
tell application "Lumesent" to send external alert "Log line" focus source terminal false
```

## Examples (`osascript`)

Single line from a shell (quote carefully):

```bash
osascript -e 'tell application "Lumesent" to send external alert "Hello" body text "From Terminal"'
```

Multi-line script file:

```bash
osascript /path/to/alert.scpt
```

## JavaScript for Automation (JXA)

```javascript
Application('Lumesent').sendExternalAlert('Hello', {
  bodyText: 'From JXA',
  applicationName: 'Scripts',
  displayMode: 'timed',
  alertType: 'fullscreen',
  focusSourceTerminal: true
});
```

Run with:

```bash
osascript -l JavaScript -e "Application('Lumesent').sendExternalAlert('Hi', { bodyText: 'JXA' })"
```

Parameter names in JXA follow the usual **camelCase** mapping of the scripting definition (e.g. `body text` → `bodyText`). If a call fails, open **Script Editor → File → Open Dictionary… → Lumesent** to see the exact terminology your macOS version exposes.

## Script Editor dictionary

To browse commands and types: **Script Editor** → **File** → **Open Dictionary…** → choose **Lumesent**.

## See also

- `Lumesent --help` — short reminder and one example.
- [`CLAUDE.md`](CLAUDE.md) — how external alerts fit into the rest of the app.
