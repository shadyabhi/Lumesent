import AppKit
import Combine
import SwiftUI
private class HistoryEntryBox: NSObject {
    let entry: HistoryEntry
    init(_ entry: HistoryEntry) { self.entry = entry }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private var globalSettingsHotkeyMonitor: Any?
    private var iconFlashTimer: Timer?

    private var dedupKey: String?
    private var dedupTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ruleStore = RuleStore()
        appSettings = AppSettings()
        notificationHistory = NotificationHistory()
        filterEngine = FilterEngine(rules: ruleStore.rules)
        permissionChecker = PermissionChecker()

        permissionObservation = permissionChecker.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuBarIcon() }
        }

        permissionChecker.$hasAccessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.registerGlobalSettingsHotkey() }
            .store(in: &cancellables)

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

        notificationServer = NotificationServer { [weak self] ext in
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

        appSettings.$openSettingsHotkey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerGlobalSettingsHotkey()
            }
            .store(in: &cancellables)

        appSettings.$alertPresentation
            .dropFirst()
            .sink { [weak self] _ in self?.appSettings.save() }
            .store(in: &cancellables)

        registerGlobalSettingsHotkey()
        updateMenuBarIcon()

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
        NSApp.setActivationPolicy(appSettings.showInDock ? .regular : .accessory)
    }

    /// Keeps onboarding/settings above other apps until FDA + Accessibility are granted.
    private func syncPermissionGatedWindowLevels() {
        let level: NSWindow.Level = permissionChecker.allGranted ? .normal : .floating
        settingsWindow?.level = level
        onboardingWindow?.level = level
    }

    private func registerGlobalSettingsHotkey() {
        if let monitor = globalSettingsHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalSettingsHotkeyMonitor = nil
        }
        let axOpts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(axOpts) else { return }
        guard let shortcut = appSettings.openSettingsHotkey else { return }
        globalSettingsHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard shortcut.matches(keyCode: event.keyCode, modifierFlags: UInt(event.modifierFlags.rawValue)) else { return }
            DispatchQueue.main.async { self?.openSettings() }
        }
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

    private func presentAlert(for record: NotificationRecord, displayMode: AlertDisplayMode) {
        FullScreenAlertWindow.show(
            notification: record,
            displayMode: displayMode,
            dismissKey: appSettings.dismissKey,
            presentation: appSettings.alertPresentation
        )
        flashMenuBarIcon()
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
        AppLog.shared.info("external notification: \(record.title, privacy: .public)")
        notificationHistory.record(record, matched: true, matchedRuleId: nil)
        guard !appSettings.isPauseActive else { return }
        presentAlert(for: record, displayMode: ext.resolvedDisplayMode)
    }

    private func handleNewNotification(_ record: NotificationRecord) {
        let matchedRule = filterEngine.matchingRule(for: record)
        notificationHistory.record(record, matched: matchedRule != nil, matchedRuleId: matchedRule?.id)

        guard let rule = matchedRule else {
            AppLog.shared.debug("notification did not match: \(record.title, privacy: .public)")
            return
        }
        guard !appSettings.isPauseActive else {
            AppLog.shared.debug("skipped alert (paused): \(record.title, privacy: .public)")
            return
        }
        if shouldSuppressDuplicate(record) {
            AppLog.shared.debug("dedup skip: \(record.title, privacy: .public)")
            return
        }

        AppLog.shared.info("MATCH — showing alert: \(record.title, privacy: .public)")
        presentAlert(for: record, displayMode: rule.displayMode)
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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
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
    }

    private func testRule(_ rule: FilterRule) {
        let record = rule.previewNotificationRecord()
        presentAlert(for: record, displayMode: rule.displayMode)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
