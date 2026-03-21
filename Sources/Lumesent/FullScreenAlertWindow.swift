import AppKit
import SwiftUI

final class FullScreenAlertWindow {
    private static var currentWindow: NSWindow?
    private static var dismissTimer: Timer?
    private static var keyMonitor: Any?

    static func show(notification: NotificationRecord, displayMode: AlertDisplayMode = .defaultTimed, dismissKey: DismissKeyShortcut? = nil) {
        dismiss()

        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
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

        let isSticky = displayMode.isSicky
        let alertView = FullScreenAlertView(
            notification: notification,
            isSticky: isSticky,
            onDismiss: { dismiss() }
        )
        window.contentView = NSHostingView(rootView: alertView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        currentWindow = window

        // Auto-dismiss only for timed mode
        if let timeout = displayMode.timeoutSeconds {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                dismiss()
            }
        }

        // Dismiss only on configured shortcut key (if set)
        if let dismissKey = dismissKey {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mask: UInt = 0x00F_E0000
                if dismissKey.matches(keyCode: event.keyCode, modifierFlags: UInt(event.modifierFlags.rawValue) & mask) {
                    dismiss()
                }
                return event
            }
        }
    }

    static func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        currentWindow?.orderOut(nil)
        currentWindow = nil
    }
}
