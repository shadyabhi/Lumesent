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
    private static var currentDismissKey: DismissKeyShortcut?
    private static var currentLayout: AlertLayout = .fullScreen

    static func show(
        notification: NotificationRecord,
        displayMode: AlertDisplayMode = .defaultTimed,
        dismissKey: DismissKeyShortcut? = nil,
        presentation: AlertPresentation = .default,
        focusSourceOnDismiss: Bool = true
    ) {
        let needsOverlay = managed.isEmpty

        if needsOverlay {
            let screens = screens(for: presentation.screens)
            guard !screens.isEmpty else {
                AppLog.shared.notice("alert show skipped — no screens available for mode=\(String(describing: presentation.screens), privacy: .public)")
                return
            }
            currentLayout = presentation.layout
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

        if let timeout = displayMode.timeoutSeconds {
            let cardId = card.id
            card.timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                dismissCard(id: cardId)
            }
        }

        gridModel.cards.append(card)
    }

    static func dismissCard(id: UUID) {
        guard let idx = gridModel.cards.firstIndex(where: { $0.id == id }) else { return }
        let card = gridModel.cards[idx]
        card.timer?.invalidate()
        gridModel.cards.remove(at: idx)
        AppLog.shared.debug("alert card dismissed, \(gridModel.cards.count, privacy: .public) remaining")

        if gridModel.cards.isEmpty {
            teardownOverlay(lastFocusSource: card.focusSourceOnDismiss, lastSourceContext: card.sourceContext, lastAppId: card.appIdentifier)
        }
    }

    static func dismiss() {
        AppLog.shared.debug("alert dismiss all called, \(gridModel.cards.count, privacy: .public) cards")
        let lastCard = gridModel.cards.last
        for card in gridModel.cards {
            card.timer?.invalidate()
        }
        gridModel.cards.removeAll()
        teardownOverlay(
            lastFocusSource: lastCard?.focusSourceOnDismiss ?? false,
            lastSourceContext: lastCard?.sourceContext,
            lastAppId: lastCard?.appIdentifier
        )
    }

    // MARK: - Overlay Management

    private static func createOverlay(screens: [NSScreen], layout: AlertLayout, dismissKey: DismissKeyShortcut?) {
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

            // Always use full screen frame so the grid can center itself
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 1
            window.orderFrontRegardless()
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

    private static func teardownOverlay(lastFocusSource: Bool, lastSourceContext: SourceContext?, lastAppId: String?) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
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
