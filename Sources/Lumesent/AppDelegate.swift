import AppKit
import Combine
import Sparkle
import SwiftUI
import UserNotifications

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

    private var permissionObservation: Any?
    private var cancellables = Set<AnyCancellable>()
    private var iconFlashTimer: Timer?
    var updaterController: SPUStandardUpdaterController!

    private var lastDedup: (key: String, time: Date)?
    /// Tracks the last alert time per rule+content combination for cooldown suppression.
    private var ruleCooldowns: [String: Date] = [:]
    /// Maps native notification request IDs → source contexts for focus-on-click.
    private var nativeNotificationContexts: [String: (context: SourceContext, createdAt: Date)] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.shared.info("app launching, pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        ruleStore = RuleStore()
        appSettings = AppSettings()
        updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        updaterController.updater.updateCheckInterval = TimeInterval(appSettings.updateCheckInterval.rawValue)
        DispatchQueue.main.async { [weak self] in
            try? self?.updaterController.updater.start()
        }
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

        if !permissionChecker.allGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openSettings()
            }
        }
    }

    private func applyActivationPolicyFromSettings() {
        if appSettings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            // Use .regular when a window is visible so the menu bar (Cmd+W/Q) works;
            // fall back to .accessory when all windows are closed.
            let hasVisibleWindow = settingsWindow?.isVisible == true
            NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
        }
    }

    /// Keeps settings above other apps until FDA + Accessibility are granted.
    private func syncPermissionGatedWindowLevels() {
        let level: NSWindow.Level = permissionChecker.allGranted ? .normal : .floating
        settingsWindow?.level = level
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
        rulesItem.submenu = rulesMenu
        fileMenu.addItem(rulesItem)

        fileMenu.addItem(withTitle: "History", action: #selector(navigateToHistory), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Settings", action: #selector(navigateToSettings), keyEquivalent: ",")

        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func navigateToRulesActive() {
        openSettings()
        NotificationCenter.default.post(name: .lumesentNavigateToTab, object: SettingsSidebarItem.rulesActive)
    }

    @objc private func navigateToHistory() {
        openSettings()
        NotificationCenter.default.post(name: .lumesentNavigateToTab, object: SettingsSidebarItem.history)
    }

    @objc private func navigateToSettings() {
        openSettings()
        NotificationCenter.default.post(name: .lumesentNavigateToTab, object: SettingsSidebarItem.settings)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionItem = NSMenuItem(title: "Lumesent v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        let matchedCount = notificationHistory.entries.filter { $0.matched && !$0.cooldownSuppressed && !$0.sourceVisibleSuppressed }.count
        let historyLabel = matchedCount == 0 ? "View History" : "View History (\(matchedCount) matched)"
        let historyItem = NSMenuItem(title: historyLabel, action: #selector(navigateToHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

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

        let logsItem = NSMenuItem(title: "Logs...", action: #selector(openLogs), keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Lumesent", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openLogs() {
        openSettings()
        NotificationCenter.default.post(name: .lumesentNavigateToTab, object: SettingsSidebarItem.logs)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        // Menu bar apps (LSUIElement) need to temporarily become a regular app
        // so that Sparkle's update dialog appears in front of other windows.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(sender)

        // Revert to accessory (menu bar only) after a delay so the dialog has time to appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !self.appSettings.showInDock {
                NSApp.setActivationPolicy(.accessory)
            }
        }
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
        let key = "\(record.appIdentifier)|\(record.title)|\(record.subtitle)|\(record.body)"
        let now = Date()
        if let last = lastDedup, last.key == key, now.timeIntervalSince(last.time) < 5 {
            return true
        }
        lastDedup = (key: key, time: now)
        return false
    }

    private func handleExternalNotification(_ ext: ExternalNotification) {
        let record = NotificationRecord.fromExternal(ext)
        AppLog.shared.info("external notification: title=\(record.title, privacy: .public) app=\(record.appName, privacy: .public) alertType=\(ext.alertType ?? "fullscreen", privacy: .public) displayMode=\(String(describing: ext.displayMode), privacy: .public)")
        guard !appSettings.isPauseActive else {
            notificationHistory.record(record, matched: true, matchedRuleId: nil)
            AppLog.shared.debug("skipped external alert (paused)")
            return
        }
        let focus = ext.resolvedFocusSource

        let behavior = appSettings.activeWindowBehavior
        if behavior != .disabled, let ctx = record.sourceContext {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let visible = ctx.isSourcePaneVisible()
                DispatchQueue.main.async {
                    guard let self else { return }
                    if visible {
                        AppLog.shared.info("\(behavior == .suppress ? "suppressed" : "downgraded", privacy: .public) external alert (source pane visible): title=\(record.title, privacy: .public) pane=\(ctx.tmuxPane ?? "nil", privacy: .public) terminal=\(ctx.terminalAppBundleId ?? "nil", privacy: .public)")
                        self.notificationHistory.record(record, matched: true, matchedRuleId: nil, sourceVisibleSuppressed: true)
                        if behavior == .downgrade {
                            self.postNativeNotification(record, focusSourceOnDismiss: focus)
                        }
                        return
                    }
                    self.notificationHistory.record(record, matched: true, matchedRuleId: nil)
                    self.presentExternalAlert(ext, record: record, focusSource: focus)
                }
            }
        } else {
            notificationHistory.record(record, matched: true, matchedRuleId: nil)
            presentExternalAlert(ext, record: record, focusSource: focus)
        }
    }

    private func presentExternalAlert(_ ext: ExternalNotification, record: NotificationRecord, focusSource: Bool) {
        switch ext.resolvedAlertType {
        case .notification:
            postNativeNotification(record, focusSourceOnDismiss: focusSource)
        case .fullscreen:
            presentAlert(for: record, displayMode: ext.resolvedDisplayMode, focusSourceOnDismiss: focusSource)
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
            nativeNotificationContexts[requestId] = (context: ctx, createdAt: Date())
            pruneStaleNotificationContexts()
        }
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.shared.error("failed to post native notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes notification contexts older than 1 hour (auto-dismissed banners never trigger didReceive).
    private func pruneStaleNotificationContexts() {
        let cutoff = Date().addingTimeInterval(-3600)
        nativeNotificationContexts = nativeNotificationContexts.filter { $0.value.createdAt > cutoff }
    }

    /// Removes cooldown entries that have expired (older than 2x the max cooldown).
    private func pruneExpiredCooldowns() {
        let now = Date()
        ruleCooldowns = ruleCooldowns.filter { now.timeIntervalSince($0.value) < 7200 }
    }

    private func handleNewNotification(_ record: NotificationRecord) {
        AppLog.shared.info("handleNewNotification: app=\(record.appName, privacy: .public) (\(record.appIdentifier, privacy: .public)) title=\(record.title, privacy: .public) subtitle=\(record.subtitle, privacy: .public) body=\(record.body.prefix(80), privacy: .public) time=\(record.deliveredDate.description, privacy: .public)")
        let matchedRule = filterEngine.matchingRule(for: record)

        guard let rule = matchedRule else {
            notificationHistory.record(record, matched: false)
            AppLog.shared.debug("no rule matched for: app=\(record.appIdentifier, privacy: .public) title=\(record.title, privacy: .public)")
            return
        }
        AppLog.shared.info("rule matched: ruleId=\(rule.id.uuidString, privacy: .public) label=\(rule.label, privacy: .public) for app=\(record.appIdentifier, privacy: .public) title=\(record.title, privacy: .public)")
        guard !appSettings.isPauseActive else {
            notificationHistory.record(record, matched: true, matchedRuleId: rule.id)
            AppLog.shared.debug("skipped alert (paused until \(String(describing: self.appSettings.pauseAlertsUntil), privacy: .public)): \(record.title, privacy: .public)")
            return
        }
        if shouldSuppressDuplicate(record) {
            notificationHistory.record(record, matched: true, matchedRuleId: rule.id)
            AppLog.shared.debug("dedup skip: \(record.title, privacy: .public)")
            return
        }
        let cooldownKey = "\(rule.id)|\(record.appIdentifier)|\(record.title)|\(record.subtitle)|\(record.body)"
        if rule.cooldownSeconds > 0, let lastFired = ruleCooldowns[cooldownKey],
           Date().timeIntervalSince(lastFired) < rule.cooldownSeconds {
            notificationHistory.record(record, matched: true, matchedRuleId: rule.id, cooldownSuppressed: true)
            AppLog.shared.info("cooldown skip: ruleId=\(rule.id.uuidString, privacy: .public) title=\(record.title, privacy: .public) (cooldown \(rule.cooldownSeconds, privacy: .public)s)")
            return
        }

        notificationHistory.record(record, matched: true, matchedRuleId: rule.id)
        ruleCooldowns[cooldownKey] = Date()
        pruneExpiredCooldowns()
        AppLog.shared.info("MATCH — showing alert: title=\(record.title, privacy: .public) displayMode=\(String(describing: rule.displayMode), privacy: .public) focusSource=\(rule.focusSourceOnDismiss, privacy: .public)")
        presentAlert(for: record, displayMode: rule.displayMode, focusSourceOnDismiss: rule.focusSourceOnDismiss)
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
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
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
        if let entry = nativeNotificationContexts.removeValue(forKey: requestId) {
            FullScreenAlertWindow.focusSource(entry.context)
        }
        completionHandler()
    }
}

// MARK: - Sparkle updater delegate

extension AppDelegate: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        let url = appSettings.updateChannel.feedURL.absoluteString
        AppLog.shared.info("Sparkle feed URL: \(url, privacy: .public) (channel: \(self.appSettings.updateChannel.rawValue, privacy: .public))")
        return url
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        let items = appcast.items.map { $0.versionString }
        AppLog.shared.info("Sparkle loaded appcast with versions: \(items, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.noUpdateError.rawValue) {
            AppLog.shared.info("Sparkle: already up to date")
        } else {
            AppLog.shared.error("Sparkle update aborted: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Sparkle user driver delegate

extension AppDelegate: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        if !appSettings.showInDock {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
