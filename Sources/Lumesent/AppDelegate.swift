import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: NotificationMonitor!
    private var filterEngine: FilterEngine!
    private var ruleStore: RuleStore!
    private var appSettings: AppSettings!
    private var notificationHistory: NotificationHistory!
    private var permissionChecker: PermissionChecker!
    private var settingsWindow: NSWindow?
    private var permissionObservation: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        ruleStore = RuleStore()
        appSettings = AppSettings()
        notificationHistory = NotificationHistory()
        filterEngine = FilterEngine(rules: ruleStore.rules)
        permissionChecker = PermissionChecker()

        // Update menu bar icon when permissions change
        permissionObservation = permissionChecker.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuBarIcon() }
        }
        updateMenuBarIcon()

        monitor = NotificationMonitor { [weak self] record in
            self?.handleNewNotification(record)
        }
        monitor.start()

        // Auto-open settings if permissions are missing on first launch
        if !permissionChecker.allGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openSettings()
            }
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let iconName: String
        if permissionChecker.allGranted {
            iconName = "bell.badge"
        } else if permissionChecker.hasFullDiskAccess {
            iconName = "bell.badge.exclamationmark"  // degraded — missing accessibility
        } else {
            iconName = "bell.slash"  // broken — can't read DB
        }
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Lumesent")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Lumesent")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lumesent", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func handleNewNotification(_ record: NotificationRecord) {
        let matchedRule = filterEngine.matchingRule(for: record)
        notificationHistory.record(record, matched: matchedRule != nil, matchedRuleId: matchedRule?.id)

        guard let rule = matchedRule else {
            NSLog("Lumesent: notification did NOT match any rule: %@", record.title)
            return
        }
        NSLog("Lumesent: MATCH! Showing full-screen alert for: %@ — %@", record.title, record.body)
        FullScreenAlertWindow.show(notification: record, displayMode: rule.displayMode, dismissKey: appSettings.dismissKey)
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(ruleStore: ruleStore, appSettings: appSettings, history: notificationHistory, permissionChecker: permissionChecker) { [weak self] updatedRules in
            self?.filterEngine.rules = updatedRules
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lumesent Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
