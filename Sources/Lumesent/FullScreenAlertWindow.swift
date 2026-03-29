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
    /// Cards that have been dismissed but not yet removed from the grid.
    @Published var pendingDismissals: Set<UUID> = []

    var visibleCards: [CardItem] {
        cards.filter { !pendingDismissals.contains($0.id) }
    }
}

final class FullScreenAlertWindow {
    private struct Managed {
        let window: NSWindow
        let layout: AlertLayout
    }

    /// Seconds to wait after last dismissal before redrawing the grid.
    private static let gridRedrawDebounceSeconds: TimeInterval = 5

    static let gridModel = AlertGridModel()
    private static var managed: [Managed] = []
    private static var keyMonitor: Any?
    private static var activationObserver: Any?
    private static var screenChangeObserver: Any?
    private static var currentDismissKey: DismissKeyShortcut?
    private static var currentLayout: AlertLayout = .fullScreen
    private static var currentScreenMode: AlertScreens = .main
    private static var gridRedrawTimer: Timer?

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

        if let timeout = displayMode.timeoutSeconds {
            card.timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                dismissCard(id: cardId)
            }
        }

        if let seconds = pushoverUnattendedAfterSeconds, seconds > 0, let onPushover = onPushoverUnattended {
            card.pushoverTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                guard gridModel.cards.contains(where: { $0.id == cardId }) else { return }
                onPushover()
            }
        }

        gridModel.cards.append(card)
    }

    static func dismissCard(id: UUID) {
        guard let card = gridModel.cards.first(where: { $0.id == id }) else { return }
        guard !gridModel.pendingDismissals.contains(id) else { return }
        card.timer?.invalidate()
        card.pushoverTimer?.invalidate()
        gridModel.pendingDismissals.insert(id)
        AppLog.shared.debug("alert card pending dismiss, \(gridModel.visibleCards.count, privacy: .public) visible")

        if gridModel.visibleCards.isEmpty {
            // All cards dismissed — flush immediately and tear down.
            flushPendingDismissals()
            teardownOverlay(lastFocusSource: card.focusSourceOnDismiss, lastSourceContext: card.sourceContext, lastAppId: card.appIdentifier)
        } else {
            // Debounce grid redraw: reset timer on each dismissal.
            gridRedrawTimer?.invalidate()
            gridRedrawTimer = Timer.scheduledTimer(withTimeInterval: gridRedrawDebounceSeconds, repeats: false) { _ in
                flushPendingDismissals()
            }
        }
    }

    private static func flushPendingDismissals() {
        gridRedrawTimer?.invalidate()
        gridRedrawTimer = nil
        let dismissed = gridModel.pendingDismissals
        guard !dismissed.isEmpty else { return }
        gridModel.pendingDismissals.removeAll()
        gridModel.cards.removeAll { dismissed.contains($0.id) }
        AppLog.shared.debug("grid redraw flushed \(dismissed.count, privacy: .public) cards, \(gridModel.cards.count, privacy: .public) remaining")
    }

    static func dismiss() {
        AppLog.shared.debug("alert dismiss all, \(gridModel.cards.count, privacy: .public) cards")
        gridRedrawTimer?.invalidate()
        gridRedrawTimer = nil
        let lastCard = gridModel.cards.last
        for card in gridModel.cards {
            card.timer?.invalidate()
            card.pushoverTimer?.invalidate()
        }
        gridModel.pendingDismissals.removeAll()
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
                // Cmd+Q dismisses the alert
                if event.modifierFlags.contains(.command) && event.keyCode == 12 {
                    Self.dismiss()
                    return nil
                }
                // Block Cmd+Tab, Cmd+H while alert is showing
                if event.modifierFlags.contains(.command) {
                    let blocked: Set<UInt16> = [48, 4] // Tab, H
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

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.shadyabhi.Lumesent", category: "FocusSource")

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
