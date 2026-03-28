import AppKit
import os
import QuartzCore
import SwiftUI

final class AlertGridModel: ObservableObject {
    struct CardItem: Identifiable {
        let id = UUID()
        let notification: NotificationRecord
        let displayMode: AlertDisplayMode
        let focusSourceOnDismiss: Bool
        let sourceContext: SourceContext?
        let appIdentifier: String?
        var timer: Timer?
        var pushoverTimer: Timer?
    }

    @Published var cards: [CardItem] = []
}

final class FullScreenAlertWindow {
    private struct Managed {
        let window: NSWindow
        let layout: AlertLayout
    }

    static let gridModel = AlertGridModel()
    private static var managed: [Managed] = []
    private static var keyMonitor: Any?
    private static var activationObserver: Any?
    private static var screenChangeObserver: Any?
    private static var currentDismissKey: DismissKeyShortcut?
    private static var currentLayout: AlertLayout = .fullScreen
    private static var currentScreenMode: AlertScreens = .main

    static func show(
        notification: NotificationRecord,
        displayMode: AlertDisplayMode = .defaultTimed,
        dismissKey: DismissKeyShortcut? = nil,
        presentation: AlertPresentation = .default,
        focusSourceOnDismiss: Bool = true,
        pushoverUnattendedAfterSeconds: Double? = nil,
        onPushoverUnattended: (() -> Void)? = nil
    ) {
        let needsOverlay = managed.isEmpty

        if needsOverlay {
            let screens = screens(for: presentation.screens)
            guard !screens.isEmpty else {
                AppLog.shared.notice("alert show skipped — no screens available for mode=\(String(describing: presentation.screens), privacy: .public)")
                return
            }
            currentLayout = presentation.layout
            currentScreenMode = presentation.screens
            currentDismissKey = dismissKey
            createOverlay(screens: screens, layout: presentation.layout, dismissKey: dismissKey)
        }

        AppLog.shared.info("showing alert: title=\(notification.title, privacy: .public) layout=\(String(describing: presentation.layout), privacy: .public) displayMode=\(String(describing: displayMode), privacy: .public) gridCount=\(gridModel.cards.count + 1, privacy: .public)")
        NSSound.beep()

        var card = AlertGridModel.CardItem(
            notification: notification,
            displayMode: displayMode,
            focusSourceOnDismiss: focusSourceOnDismiss,
            sourceContext: notification.sourceContext,
            appIdentifier: notification.appIdentifier
        )

        let cardId = card.id
        let cardIdShort = String(cardId.uuidString.prefix(8))

        if let timeout = displayMode.timeoutSeconds {
            card.timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                AppLog.shared.info("alert: auto-dismiss timer fired card=\(cardIdShort, privacy: .public) after \(timeout, privacy: .public)s")
                dismissCard(id: cardId, reason: "auto-dismiss")
            }
        } else {
            AppLog.shared.debug("alert: no auto-dismiss (sticky) card=\(cardIdShort, privacy: .public)")
        }

        if let seconds = pushoverUnattendedAfterSeconds, seconds > 0, let onPushover = onPushoverUnattended {
            card.pushoverTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                let stillThere = gridModel.cards.contains(where: { $0.id == cardId })
                if stillThere {
                    AppLog.shared.info("pushover: escalation timer fired card=\(cardIdShort, privacy: .public) after \(seconds, privacy: .public)s — invoking API")
                } else {
                    AppLog.shared.notice("pushover: escalation timer fired but card=\(cardIdShort, privacy: .public) already gone — skip (race or manual dismiss)")
                }
                guard stillThere else { return }
                onPushover()
            }
            AppLog.shared.info("pushover: escalation timer scheduled card=\(cardIdShort, privacy: .public) in \(seconds, privacy: .public)s")
        } else if onPushoverUnattended != nil {
            AppLog.shared.notice("pushover: onPushover set but delay nil or ≤0 — no timer")
        }

        gridModel.cards.append(card)
    }

    static func dismissCard(id: UUID, reason: String = "manual") {
        let idShort = String(id.uuidString.prefix(8))
        guard let idx = gridModel.cards.firstIndex(where: { $0.id == id }) else {
            AppLog.shared.debug("pushover: dismissCard id=\(idShort, privacy: .public) reason=\(reason, privacy: .public) — no such card")
            return
        }
        let card = gridModel.cards[idx]
        let hadPushoverPending = card.pushoverTimer != nil
        card.timer?.invalidate()
        card.pushoverTimer?.invalidate()
        gridModel.cards.remove(at: idx)
        if hadPushoverPending {
            AppLog.shared.info("pushover: escalation cancelled (card removed) id=\(idShort, privacy: .public) reason=\(reason, privacy: .public) remaining=\(gridModel.cards.count, privacy: .public)")
        }
        AppLog.shared.debug("alert card dismissed id=\(idShort, privacy: .public) reason=\(reason, privacy: .public) remaining=\(gridModel.cards.count, privacy: .public)")

        if gridModel.cards.isEmpty {
            teardownOverlay(lastFocusSource: card.focusSourceOnDismiss, lastSourceContext: card.sourceContext, lastAppId: card.appIdentifier)
        }
    }

    static func dismiss() {
        let n = gridModel.cards.count
        let hadPushover = gridModel.cards.contains { $0.pushoverTimer != nil }
        if hadPushover {
            AppLog.shared.info("pushover: escalation cancelled (dismiss all) cards=\(n, privacy: .public)")
        }
        AppLog.shared.debug("alert dismiss all called, \(gridModel.cards.count, privacy: .public) cards")
        let lastCard = gridModel.cards.last
        for card in gridModel.cards {
            card.timer?.invalidate()
            card.pushoverTimer?.invalidate()
        }
        gridModel.cards.removeAll()
        teardownOverlay(
            lastFocusSource: lastCard?.focusSourceOnDismiss ?? false,
            lastSourceContext: lastCard?.sourceContext,
            lastAppId: lastCard?.appIdentifier
        )
    }

    // MARK: - Overlay Management

    private static func makeOverlayWindow(screen: NSScreen, layout: AlertLayout) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        let gridView = AlertGridView(
            model: gridModel,
            layout: layout,
            onDismissCard: { cardId in dismissCard(id: cardId) },
            onDismissAll: { dismiss() }
        )
        window.contentView = NSHostingView(rootView: gridView)
        window.setFrame(screen.frame, display: false)
        window.alphaValue = 1
        window.orderFrontRegardless()
        return window
    }

    private static func createOverlay(screens: [NSScreen], layout: AlertLayout, dismissKey: DismissKeyShortcut?) {
        for screen in screens {
            let window = makeOverlayWindow(screen: screen, layout: layout)
            managed.append(Managed(window: window, layout: layout))
        }

        managed.first?.window.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard !managed.isEmpty else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            NSApp.activate(ignoringOtherApps: true)
            managed.first?.window.orderFrontRegardless()
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            resizeOverlayToCurrentScreens()
        }

        if let dismissKey {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if dismissKey.matches(keyCode: event.keyCode, modifierFlags: UInt(event.modifierFlags.rawValue)) {
                    Self.dismiss()
                }
                // Block Cmd+Tab, Cmd+H, Cmd+Q while alert is showing
                if event.modifierFlags.contains(.command) {
                    let blocked: Set<UInt16> = [48, 4, 12] // Tab, H, Q
                    if blocked.contains(event.keyCode) {
                        return nil
                    }
                }
                return event
            }
        }
    }

    private static func resizeOverlayToCurrentScreens() {
        guard !managed.isEmpty else { return }
        let newScreens = screens(for: currentScreenMode)
        AppLog.shared.notice("screen parameters changed — resizing \(managed.count, privacy: .public) overlay(s) to \(newScreens.count, privacy: .public) screen(s)")

        // Resize existing windows to match updated screen frames
        for (i, m) in managed.enumerated() {
            if i < newScreens.count {
                m.window.setFrame(newScreens[i].frame, display: true)
            }
        }

        // If screens were added, create new overlay windows
        if newScreens.count > managed.count {
            for screen in newScreens[managed.count...] {
                let window = makeOverlayWindow(screen: screen, layout: currentLayout)
                managed.append(Managed(window: window, layout: currentLayout))
            }
        }

        // If screens were removed, tear down extra windows
        if newScreens.count < managed.count {
            let extra = managed[newScreens.count...]
            for m in extra {
                m.window.orderOut(nil)
            }
            managed.removeSubrange(newScreens.count...)
        }
    }

    private static func teardownOverlay(lastFocusSource: Bool, lastSourceContext: SourceContext?, lastAppId: String?) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }

        let copies = managed
        managed.removeAll()

        for m in copies {
            m.window.orderOut(nil)
        }

        if lastFocusSource {
            if let ctx = lastSourceContext {
                focusSource(ctx)
            } else if let bundleId = lastAppId {
                activateApp(bundleId: bundleId)
            }
        }
    }

    // MARK: - Screen Helpers

    private static func screens(for mode: AlertScreens) -> [NSScreen] {
        switch mode {
        case .main:
            if let main = NSScreen.main { return [main] }
            return Array(NSScreen.screens.prefix(1))
        case .allScreens:
            return NSScreen.screens
        }
    }

    // MARK: - Focus Source

    private static let log = Logger(subsystem: "com.shadyabhi.Lumesent", category: "FocusSource")

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

    static func focusSource(_ ctx: SourceContext) {
        log.notice("focusSource: tmux=\(ctx.tmuxSession ?? "nil", privacy: .public):\(ctx.tmuxWindow ?? "nil", privacy: .public):\(ctx.tmuxPane ?? "nil", privacy: .public) terminal=\(ctx.terminalAppBundleId ?? "nil", privacy: .public)")

        DispatchQueue.global(qos: .userInitiated).async {
            if ctx.hasTmux, let session = ctx.tmuxSession, let window = ctx.tmuxWindow, let pane = ctx.tmuxPane {
                let cmd = "tmux select-window -t \(session):\(window) && tmux select-pane -t \(pane)"
                log.notice("focusSource: running: \(cmd, privacy: .public)")
                let status = SourceContext.shellRun(cmd)
                log.notice("focusSource: tmux exit code=\(status, privacy: .public)")
            }

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
}
