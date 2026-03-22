import AppKit
import Combine
import SwiftUI
import UserNotifications
private class HistoryEntryBox: NSObject {
    let entry: HistoryEntry
    init(_ entry: HistoryEntry) { self.entry = entry }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: NotificationMonitor!
    private var filterEngine: FilterEngine!
    private var ruleStore: RuleStore!
    private var appSettings: AppSettings!
    private var notificationHistory: NotificationHistory!
    private var permissionChecker: PermissionChecker!
    private var notificationServer: NotificationServer!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var permissionObservation: Any?
    private var cancellables = Set<AnyCancellable>()
    private var iconFlashTimer: Timer?

    private var dedupKey: String?
    private var dedupTime: Date?
    /// Maps native notification request IDs → source contexts for focus-on-click.
    private var nativeNotificationContexts: [String: SourceContext] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.shared.info("app launching, pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        ruleStore = RuleStore()
        appSettings = AppSettings()
        notificationHistory = NotificationHistory()
        filterEngine = FilterEngine(rules: ruleStore.rules)
        permissionChecker = PermissionChecker()
        AppLog.shared.info("loaded \(self.ruleStore.rules.count, privacy: .public) rules (\(self.ruleStore.rules.filter(\.isEnabled).count, privacy: .public) enabled), \(self.notificationHistory.entries.count, privacy: .public) history entries")

        permissionObservation = permissionChecker.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuBarIcon() }
        }

        Publishers.CombineLatest(permissionChecker.$hasFullDiskAccess, permissionChecker.$hasAccessibility)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.syncPermissionGatedWindowLevels() }
            .store(in: &cancellables)

        monitor = NotificationMonitor { [weak self] record in
            self?.handleNewNotification(record)
        }
        monitor.start()

        monitor.$databaseStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        applyActivationPolicyFromSettings()
        setupMenuBar()
        setupMainMenu()

        notificationServer = NotificationServer(socketPath: appSettings.socketPath) { [weak self] ext in
            self?.handleExternalNotification(ext)
        }
        notificationServer.start()

        appSettings.$showInDock
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyActivationPolicyFromSettings()
            }
            .store(in: &cancellables)

        appSettings.$socketPath
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPath in
                self?.notificationServer.restart(socketPath: newPath)
            }
            .store(in: &cancellables)

        appSettings.$alertPresentation
            .dropFirst()
            .sink { [weak self] _ in self?.appSettings.save() }
            .store(in: &cancellables)

        updateMenuBarIcon()

        AppLog.shared.info("app startup complete — FDA=\(self.permissionChecker.hasFullDiskAccess, privacy: .public) AX=\(self.permissionChecker.hasAccessibility, privacy: .public) paused=\(self.appSettings.isPauseActive, privacy: .public)")

        // Request notification permission early so the system prompt appears
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            AppLog.shared.info("notification authorization: granted=\(granted, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)")
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettings),
            name: .lumesentOpenSettings,
            object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            if !OnboardingState.hasCompleted {
                if self.permissionChecker.allGranted {
                    OnboardingState.markCompleted()
                } else {
                    self.presentOnboardingIfNeeded()
                }
            } else if !self.permissionChecker.allGranted {
                self.openSettings()
            }
        }
    }

    private func applyActivationPolicyFromSettings() {
        if appSettings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            // Use .regular when a window is visible so the menu bar (Cmd+W/Q) works;
            // fall back to .accessory when all windows are closed.
            let hasVisibleWindow = (settingsWindow?.isVisible == true) || (onboardingWindow?.isVisible == true)
            NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
        }
    }

    /// Keeps onboarding/settings above other apps until FDA + Accessibility are granted.
    private func syncPermissionGatedWindowLevels() {
        let level: NSWindow.Level = permissionChecker.allGranted ? .normal : .floating
        settingsWindow?.level = level
        onboardingWindow?.level = level
    }

    private func presentOnboardingIfNeeded() {
        guard onboardingWindow == nil, !OnboardingState.hasCompleted, !permissionChecker.allGranted else { return }
        let view = OnboardingView(permissionChecker: permissionChecker) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            if self?.permissionChecker.allGranted == false {
                self?.openSettings()
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        syncPermissionGatedWindowLevels()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyActivationPolicyFromSettings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window)
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let iconName: String
        if !permissionChecker.hasFullDiskAccess {
            iconName = "bell.slash"
        } else if monitor?.databaseStatus == .temporarilyUnavailable {
            iconName = "bell.badge.clock"
        } else if !permissionChecker.hasAccessibility {
            iconName = "bell.badge.exclamationmark"
        } else {
            iconName = "bell.badge"
        }
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Lumesent")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lumesent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")

        // Rules submenu
        let rulesItem = NSMenuItem(title: "Rules", action: nil, keyEquivalent: "")
        let rulesMenu = NSMenu(title: "Rules")
        rulesMenu.addItem(withTitle: "Active", action: #selector(navigateToRulesActive), keyEquivalent: "")
        rulesMenu.addItem(withTitle: "Unmatched", action: #selector(navigateToUnmatched), keyEquivalent: "")
        rulesItem.submenu = rulesMenu
        fileMenu.addItem(rulesItem)

        fileMenu.addItem(withTitle: "Settings", action: #selector(navigateToSettings), keyEquivalent: ",")

        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func navigateToRulesActive() {
        openSettings()
        NotificationCenter.default.post(name: .lumesentNavigateToTab, object: "rulesActive")
    }

    @objc private func navigateToUnmatched() {
        openSettings()
        NotificationCenter.default.post(name: .lumesentNavigateToTab, object: "unmatched")
    }

    @objc private func navigateToSettings() {
        openSettings()
        NotificationCenter.default.post(name: .lumesentNavigateToTab, object: "settings")
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    /// Compact row; full title and body appear in a submenu (opens on hover).
    private func recentMatchMenuItem(for entry: HistoryEntry) -> NSMenuItem {
        let headlineSource = entry.title.isEmpty ? entry.appName : entry.title
        let truncatedHeadline: String
        if headlineSource.count > 56 {
            truncatedHeadline = String(headlineSource.prefix(53)) + "…"
        } else {
            truncatedHeadline = headlineSource
        }
        let when = relativeTime(entry.date)
        let headline = "\(truncatedHeadline)  —  \(when)"

        let parent = NSMenuItem(title: headline, action: #selector(replayHistoryEntry(_:)), keyEquivalent: "")
        parent.target = self
        parent.representedObject = HistoryEntryBox(entry)
        parent.isEnabled = true

        let sub = NSMenu(title: "")
        populateNotificationDetailSubmenu(sub, entry: entry)
        parent.submenu = sub
        return parent
    }

    private func populateNotificationDetailSubmenu(_ menu: NSMenu, entry: HistoryEntry) {
        func addDisabled(_ title: String) {
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }

        addDisabled(entry.appName)
        let titleText = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyText = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)

        if !titleText.isEmpty {
            menu.addItem(.separator())
            for line in splitTextForMenuLines(titleText) {
                addDisabled(line)
            }
        }
        if !bodyText.isEmpty {
            menu.addItem(.separator())
            for line in splitTextForMenuLines(bodyText) {
                addDisabled(line)
            }
        }
    }

    /// Wraps text into short lines suitable for menu item titles (single-line items).
    private func splitTextForMenuLines(_ text: String, maxLen: Int = 56, maxLines: Int = 20) -> [String] {
        var result: [String] = []
        outer: for para in text.components(separatedBy: "\n") {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            var remaining = trimmed[...]
            while !remaining.isEmpty {
                if result.count >= maxLines - 1 {
                    result.append("…")
                    break outer
                }
                if remaining.count <= maxLen {
                    result.append(String(remaining))
                    break
                }
                let endIdx = remaining.index(remaining.startIndex, offsetBy: maxLen)
                let window = remaining[..<endIdx]
                if let spaceIdx = window.lastIndex(of: " ") {
                    result.append(String(remaining[..<spaceIdx]))
                    var after = remaining[remaining.index(after: spaceIdx)...]
                    while after.first == " " { after = after.dropFirst() }
                    remaining = after
                } else {
                    result.append(String(window))
                    var after = remaining[endIdx...]
                    while after.first == " " { after = after.dropFirst() }
                    remaining = after
                }
            }
        }
        return result
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionItem = NSMenuItem(title: "Lumesent v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        let recent = notificationHistory.recentMatches(count: 5)
        if recent.isEmpty {
            let item = NSMenuItem(title: "No recent matches yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for entry in recent {
                menu.addItem(recentMatchMenuItem(for: entry))
            }
        }

        menu.addItem(.separator())

        if appSettings.isPauseActive, let until = appSettings.pauseAlertsUntil {
            let item = NSMenuItem(
                title: "Alerts paused (\(relativeTime(until)))",
                action: nil,
                keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let resume = NSMenuItem(title: "Resume alerts now", action: #selector(resumeAlerts), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        } else {
            let p1 = NSMenuItem(title: "Pause alerts for 1 hour", action: #selector(pauseOneHour), keyEquivalent: "")
            p1.target = self
            menu.addItem(p1)
            let p2 = NSMenuItem(title: "Pause alerts until tomorrow", action: #selector(pauseUntilTomorrow), keyEquivalent: "")
            p2.target = self
            menu.addItem(p2)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Lumesent", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func pauseOneHour() {
        appSettings.pauseAlertsUntil = Date().addingTimeInterval(3600)
        appSettings.save()
    }

    @objc private func pauseUntilTomorrow() {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let start = cal.startOfDay(for: Date().addingTimeInterval(86400))
        appSettings.pauseAlertsUntil = start
        appSettings.save()
    }

    @objc private func resumeAlerts() {
        appSettings.pauseAlertsUntil = nil
        appSettings.save()
    }

    private func flashMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Lumesent alert")
        iconFlashTimer?.invalidate()
        iconFlashTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.updateMenuBarIcon()
        }
    }

    private func presentAlert(for record: NotificationRecord, displayMode: AlertDisplayMode, focusSourceOnDismiss: Bool = true) {
        flashMenuBarIcon()
        FullScreenAlertWindow.show(
            notification: record,
            displayMode: displayMode,
            dismissKey: appSettings.dismissKey,
            presentation: appSettings.alertPresentation,
            focusSourceOnDismiss: focusSourceOnDismiss
        )
    }

    private func shouldSuppressDuplicate(_ record: NotificationRecord) -> Bool {
        let key = "\(record.appIdentifier)|\(record.title)|\(record.body)"
        let now = Date()
        if let dk = dedupKey, dk == key, let t = dedupTime, now.timeIntervalSince(t) < 5 {
            return true
        }
        dedupKey = key
        dedupTime = now
        return false
    }

    private func handleExternalNotification(_ ext: ExternalNotification) {
        let record = NotificationRecord.fromExternal(ext)
        AppLog.shared.info("external notification: title=\(record.title, privacy: .public) app=\(record.appName, privacy: .public) alertType=\(ext.alertType ?? "fullscreen", privacy: .public) displayMode=\(String(describing: ext.displayMode), privacy: .public)")
        notificationHistory.record(record, matched: true, matchedRuleId: nil)
        guard !appSettings.isPauseActive else {
            AppLog.shared.debug("skipped external alert (paused)")
            return
        }
        let focus = ext.resolvedFocusSource
        switch ext.resolvedAlertType {
        case .notification:
            postNativeNotification(record, focusSourceOnDismiss: focus)
        case .fullscreen:
            presentAlert(for: record, displayMode: ext.resolvedDisplayMode, focusSourceOnDismiss: focus)
        }
    }

    private func postNativeNotification(_ record: NotificationRecord, focusSourceOnDismiss: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = record.title
        if !record.body.isEmpty {
            content.body = record.body
        }
        content.sound = .default
        let requestId = UUID().uuidString
        if focusSourceOnDismiss, let ctx = record.sourceContext {
            nativeNotificationContexts[requestId] = ctx
        }
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.shared.error("failed to post native notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleNewNotification(_ record: NotificationRecord) {
        AppLog.shared.debug("handleNewNotification: app=\(record.appIdentifier, privacy: .public) title=\(record.title, privacy: .public) body=\(record.body.prefix(80), privacy: .public)")
        let matchedRule = filterEngine.matchingRule(for: record)
        notificationHistory.record(record, matched: matchedRule != nil, matchedRuleId: matchedRule?.id)

        guard let rule = matchedRule else {
            AppLog.shared.debug("no rule matched for: app=\(record.appIdentifier, privacy: .public) title=\(record.title, privacy: .public)")
            return
        }
        AppLog.shared.info("rule matched: ruleId=\(rule.id.uuidString, privacy: .public) label=\(rule.label, privacy: .public) for app=\(record.appIdentifier, privacy: .public) title=\(record.title, privacy: .public)")
        guard !appSettings.isPauseActive else {
            AppLog.shared.debug("skipped alert (paused until \(String(describing: self.appSettings.pauseAlertsUntil), privacy: .public)): \(record.title, privacy: .public)")
            return
        }
        if shouldSuppressDuplicate(record) {
            AppLog.shared.debug("dedup skip: \(record.title, privacy: .public)")
            return
        }

        AppLog.shared.info("MATCH — showing alert: title=\(record.title, privacy: .public) displayMode=\(String(describing: rule.displayMode), privacy: .public) focusSource=\(rule.focusSourceOnDismiss, privacy: .public)")
        presentAlert(for: record, displayMode: rule.displayMode, focusSourceOnDismiss: rule.focusSourceOnDismiss)
    }

    @objc private func replayHistoryEntry(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? HistoryEntryBox else { return }
        let entry = box.entry
        let record = NotificationRecord(
            id: -1,
            appIdentifier: entry.appIdentifier,
            title: entry.title,
            body: entry.body,
            deliveredDate: entry.date
        )
        // Look up the original rule's display mode, fall back to default timed
        let displayMode: AlertDisplayMode
        if let ruleId = entry.matchedRuleId,
           let rule = ruleStore.rules.first(where: { $0.id == ruleId }) {
            displayMode = rule.displayMode
        } else {
            displayMode = .defaultTimed
        }
        presentAlert(for: record, displayMode: displayMode)
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            syncPermissionGatedWindowLevels()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            ruleStore: ruleStore,
            appSettings: appSettings,
            history: notificationHistory,
            permissionChecker: permissionChecker,
            onRulesChanged: { [weak self] updatedRules in
                self?.filterEngine.rules = updatedRules
            },
            onTestRule: { [weak self] rule in
                self?.testRule(rule)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Lumesent"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        syncPermissionGatedWindowLevels()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyActivationPolicyFromSettings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window)
    }

    private func testRule(_ rule: FilterRule) {
        let record = rule.previewNotificationRecord()
        presentAlert(for: record, displayMode: rule.displayMode)
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        if window === settingsWindow { settingsWindow = nil }
        if window === onboardingWindow { onboardingWindow = nil }
        applyActivationPolicyFromSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show native notifications even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Focus the source terminal when the user clicks a native notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let requestId = response.notification.request.identifier
        if let ctx = nativeNotificationContexts.removeValue(forKey: requestId) {
            FullScreenAlertWindow.focusSource(ctx)
        }
        completionHandler()
    }
}
