import AppKit
import os
import QuartzCore
import SwiftUI

final class FullScreenAlertWindow {
    private struct Managed {
        let window: NSWindow
        let layout: AlertLayout
        let finalFrame: NSRect
    }

    private struct QueuedAlert {
        let notification: NotificationRecord
        let displayMode: AlertDisplayMode
        let dismissKey: DismissKeyShortcut?
        let presentation: AlertPresentation
        let focusSourceOnDismiss: Bool
    }

    private static var managed: [Managed] = []
    private static var alertQueue: [QueuedAlert] = []
    private static var dismissTimer: Timer?
    private static var keyMonitor: Any?
    private static var currentSourceContext: SourceContext?
    private static var currentAppIdentifier: String?
    private static var shouldFocusSourceOnDismiss: Bool = true

    static func show(
        notification: NotificationRecord,
        displayMode: AlertDisplayMode = .defaultTimed,
        dismissKey: DismissKeyShortcut? = nil,
        presentation: AlertPresentation = .default,
        focusSourceOnDismiss: Bool = true
    ) {
        if !managed.isEmpty || !alertQueue.isEmpty {
            alertQueue.append(
                QueuedAlert(
                    notification: notification,
                    displayMode: displayMode,
                    dismissKey: dismissKey,
                    presentation: presentation,
                    focusSourceOnDismiss: focusSourceOnDismiss
                )
            )
            AppLog.shared.info(
                "alert queued (depth=\(alertQueue.count, privacy: .public)): title=\(notification.title, privacy: .public)"
            )
            return
        }
        showNow(
            notification: notification,
            displayMode: displayMode,
            dismissKey: dismissKey,
            presentation: presentation,
            focusSourceOnDismiss: focusSourceOnDismiss
        )
    }

    private static func stripDetachedMonitors() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private static func showNow(
        notification: NotificationRecord,
        displayMode: AlertDisplayMode,
        dismissKey: DismissKeyShortcut?,
        presentation: AlertPresentation,
        focusSourceOnDismiss: Bool
    ) {
        stripDetachedMonitors()

        let screens = screens(for: presentation.screens)
        guard !screens.isEmpty else {
            AppLog.shared.notice("alert show skipped — no screens available for mode=\(String(describing: presentation.screens), privacy: .public)")
            DispatchQueue.main.async { processQueueIfNeeded() }
            return
        }

        AppLog.shared.info("showing alert: title=\(notification.title, privacy: .public) layout=\(String(describing: presentation.layout), privacy: .public) screens=\(screens.count, privacy: .public) displayMode=\(String(describing: displayMode), privacy: .public)")
        NSSound.beep()

        shouldFocusSourceOnDismiss = focusSourceOnDismiss
        currentSourceContext = notification.sourceContext
        currentAppIdentifier = notification.appIdentifier
        let layout = presentation.layout
        for screen in screens {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = layout != .fullScreen
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false

            let isSticky = displayMode.isSticky
            let alertView = FullScreenAlertView(
                notification: notification,
                isSticky: isSticky,
                layout: layout,
                onDismiss: { dismiss() }
            )
            window.contentView = NSHostingView(rootView: alertView)

            let finalFrame = frame(for: layout, on: screen)
            window.setFrame(finalFrame, display: false)

            if layout == .banner {
                var start = finalFrame
                start.origin.y += start.height + 40
                window.alphaValue = 0
                window.setFrame(start, display: false)
                window.orderFrontRegardless()
                managed.append(Managed(window: window, layout: layout, finalFrame: finalFrame))
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.32
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(finalFrame, display: true)
                    window.animator().alphaValue = 1
                }
            } else {
                window.alphaValue = 1
                window.orderFrontRegardless()
                managed.append(Managed(window: window, layout: layout, finalFrame: finalFrame))
            }
        }

        managed.first?.window.makeKey()

        if let timeout = displayMode.timeoutSeconds {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                dismiss()
            }
        }

        if let dismissKey {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if dismissKey.matches(keyCode: event.keyCode, modifierFlags: UInt(event.modifierFlags.rawValue)) {
                    dismiss()
                }
                return event
            }
        }
    }

    private static func processQueueIfNeeded() {
        guard managed.isEmpty, let next = alertQueue.first else { return }
        alertQueue.removeFirst()
        showNow(
            notification: next.notification,
            displayMode: next.displayMode,
            dismissKey: next.dismissKey,
            presentation: next.presentation,
            focusSourceOnDismiss: next.focusSourceOnDismiss
        )
    }

    private static func screens(for mode: AlertScreens) -> [NSScreen] {
        switch mode {
        case .main:
            if let main = NSScreen.main { return [main] }
            return Array(NSScreen.screens.prefix(1))
        case .allScreens:
            return NSScreen.screens
        }
    }

    private static func frame(for layout: AlertLayout, on screen: NSScreen) -> NSRect {
        switch layout {
        case .fullScreen:
            return screen.frame
        case .banner:
            let vf = screen.visibleFrame
            let margin: CGFloat = 16
            let panelHeight: CGFloat = 220
            let w = min(720, vf.width - margin * 2)
            let x = vf.midX - w / 2
            let y = vf.maxY - panelHeight - 10
            return NSRect(x: x, y: y, width: w, height: panelHeight)
        }
    }

    private static let log = Logger(subsystem: "com.shadyabhi.Lumesent", category: "FocusSource")

    /// Activate an app by bundle identifier (used for system notifications).
    private static func activateApp(bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            log.notice("activateApp: no app found for \(bundleId, privacy: .public)")
            return
        }
        log.notice("activateApp: activating \(bundleId, privacy: .public)")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    /// Activate the terminal window/pane that sent the notification.
    static func focusSource(_ ctx: SourceContext) {
        log.notice("focusSource: tmux=\(ctx.tmuxSession ?? "nil", privacy: .public):\(ctx.tmuxWindow ?? "nil", privacy: .public):\(ctx.tmuxPane ?? "nil", privacy: .public) terminal=\(ctx.terminalAppBundleId ?? "nil", privacy: .public)")

        // Run tmux + app activation off the main thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            // 1) Switch tmux to the source pane
            if ctx.hasTmux, let session = ctx.tmuxSession, let window = ctx.tmuxWindow, let pane = ctx.tmuxPane {
                let cmd = "tmux select-window -t \(session):\(window) && tmux select-pane -t \(pane)"
                log.notice("focusSource: running: \(cmd, privacy: .public)")
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/sh")
                proc.arguments = ["-c", cmd]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    log.notice("focusSource: tmux exit code=\(proc.terminationStatus, privacy: .public)")
                } catch {
                    log.notice("focusSource error: tmux failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            // 2) Bring the terminal app to the foreground (must be on main thread)
            if let bundleId = ctx.terminalAppBundleId,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                DispatchQueue.main.async {
                    log.notice("focusSource: activating \(bundleId, privacy: .public)")
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                }
            }
        }
    }

    static func dismiss() {
        AppLog.shared.debug("alert dismiss called, \(managed.count, privacy: .public) windows open")
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        let copies = managed
        managed.removeAll()

        // Grab and clear source context before closing windows
        let sourceCtx = currentSourceContext
        let appId = currentAppIdentifier
        currentSourceContext = nil
        currentAppIdentifier = nil
        let willPresentQueued = !alertQueue.isEmpty

        for m in copies {
            if m.layout == .banner {
                var exitFrame = m.window.frame
                exitFrame.origin.y += exitFrame.height + 50
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.22
                    m.window.animator().setFrame(exitFrame, display: true)
                    m.window.animator().alphaValue = 0
                }, completionHandler: {
                    m.window.orderOut(nil)
                })
            } else {
                m.window.orderOut(nil)
            }
        }

        // Focus source only when nothing else is queued (avoid stealing focus before the next alert)
        if shouldFocusSourceOnDismiss, !willPresentQueued {
            if let ctx = sourceCtx {
                focusSource(ctx)
            } else if let bundleId = appId {
                activateApp(bundleId: bundleId)
            }
        }
        shouldFocusSourceOnDismiss = true

        DispatchQueue.main.async {
            processQueueIfNeeded()
        }
    }
}
