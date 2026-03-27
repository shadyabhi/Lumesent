import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings View (sidebar + detail, Xcode-style)

private enum SettingsChromeLayout {
    /// Matches `navigationSplitViewColumnWidth` ideal so the app name lines up with the sidebar column.
    static let sidebarIdealWidth: CGFloat = 200
    static let sidebarContentLeadingPadding: CGFloat = 12
    static let detailContentHorizontalPadding: CGFloat = 24
}

enum SettingsSidebarItem: Hashable {
    case rulesActive
    case history
    case logs
    case settings

    var detailTitle: String {
        switch self {
        case .rulesActive: return "Active"
        case .history: return "History"
        case .logs: return "Logs"
        case .settings: return "Settings"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var history: NotificationHistory
    @ObservedObject var permissionChecker: PermissionChecker
    let onRulesChanged: ([FilterRule]) -> Void
    let onTestRule: (FilterRule) -> Void

    @State private var selectedSidebarItem: SettingsSidebarItem = .rulesActive
    @StateObject private var logStore = LogStore()

    init(
        ruleStore: RuleStore,
        appSettings: AppSettings,
        history: NotificationHistory,
        permissionChecker: PermissionChecker,
        onRulesChanged: @escaping ([FilterRule]) -> Void,
        onTestRule: @escaping (FilterRule) -> Void
    ) {
        self.ruleStore = ruleStore
        self.appSettings = appSettings
        self.history = history
        self.permissionChecker = permissionChecker
        self.onRulesChanged = onRulesChanged
        self.onTestRule = onTestRule
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text("Lumesent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsChromeLayout.sidebarIdealWidth, alignment: .leading)
                    .padding(.leading, SettingsChromeLayout.sidebarContentLeadingPadding)
                HStack(alignment: .center, spacing: 12) {
                    Text(selectedSidebarItem.detailTitle)
                        .font(.system(size: 20, weight: .semibold))
                    Spacer(minLength: 8)
                    if permissionChecker.allGranted {
                        PermissionOKIndicator(permissionChecker: permissionChecker)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, SettingsChromeLayout.detailContentHorizontalPadding)
                .padding(.trailing, SettingsChromeLayout.detailContentHorizontalPadding)
            }
            .padding(.top, 0)
            .padding(.bottom, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if !permissionChecker.allGranted {
                PermissionBanner(permissionChecker: permissionChecker)
            }
            if permissionChecker.allGranted && !permissionChecker.hasNotifications {
                NotificationPermissionBanner()
            }

            NavigationSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSidebarGroup(title: "Rules") {
                            settingsSidebarRow(
                                title: "Active",
                                systemImage: "checkmark.circle",
                                item: .rulesActive
                            )
                        }

                        SettingsSidebarGroup(title: "History") {
                            settingsSidebarRow(
                                title: "History",
                                systemImage: "clock.arrow.circlepath",
                                item: .history
                            )
                        }

                        SettingsSidebarGroup(title: "Logs") {
                            settingsSidebarRow(
                                title: "Logs",
                                systemImage: "doc.text",
                                item: .logs
                            )
                        }

                        SettingsSidebarGroup(title: "Settings") {
                            settingsSidebarRow(
                                title: "Settings",
                                systemImage: "gearshape",
                                item: .settings
                            )
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .navigationSplitViewColumnWidth(min: 176, ideal: 200, max: 260)
                .toolbar(.hidden)
            } detail: {
                VStack(spacing: 0) {
                    Group {
                        switch selectedSidebarItem {
                        case .rulesActive:
                            RulesTab(ruleStore: ruleStore, history: history, onRulesChanged: onRulesChanged, onTestRule: onTestRule)
                        case .history:
                            HistoryTab(history: history, ruleStore: ruleStore, appSettings: appSettings, onRulesChanged: onRulesChanged)
                        case .logs:
                            LogsTab(logStore: logStore)
                        case .settings:
                            SettingsTab(appSettings: appSettings, history: history)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea(edges: .top)
                .toolbar(.hidden)
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .lumesentNavigateToTab)) { notification in
            if let item = notification.object as? SettingsSidebarItem {
                selectedSidebarItem = item
            }
        }
    }

    private func settingsSidebarRow(title: String, systemImage: String, item: SettingsSidebarItem) -> some View {
        Button {
            selectedSidebarItem = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(selectedSidebarItem == item ? .primary : .secondary)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedSidebarItem == item ? Color.accentColor.opacity(0.28) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar grouped boxes (Rules / Settings)

private struct SettingsSidebarGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.42))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.primary.opacity(0.045), location: 0),
                                .init(color: Color.clear, location: 0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Permission OK Indicator (compact, top-right)

struct PermissionOKIndicator: View {
    @ObservedObject var permissionChecker: PermissionChecker
    @State private var showingDetail = false
    @State private var isChecking = false

    var body: some View {
        Button(action: {
            isChecking = true
            permissionChecker.check()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isChecking = false
                showingDetail = true
            }
        }) {
            Group {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else if !permissionChecker.hasNotifications {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
        .help("Permission status — click to check")
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                PermissionStatusRow(label: "Full Disk Access", ok: permissionChecker.hasFullDiskAccess, purpose: "Read the notification database")
                PermissionStatusRow(label: "Accessibility", ok: permissionChecker.hasAccessibility, purpose: "Real-time detection & hotkeys")
                PermissionStatusRow(label: "Notifications", ok: permissionChecker.hasNotifications, purpose: "Send native macOS alerts")
            }
            .padding(12)
            .frame(width: 240)
        }
    }
}

struct PermissionStatusRow: View {
    let label: String
    let ok: Bool
    let purpose: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(ok ? .green : .red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                Text(purpose)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

// MARK: - Permission Banner

struct PermissionBanner: View {
    @ObservedObject var permissionChecker: PermissionChecker

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                Text("Lumesent needs permissions to work")
                    .font(.system(size: 14, weight: .bold))
            }

            VStack(spacing: 8) {
                if !permissionChecker.hasFullDiskAccess {
                    PermissionRow(
                        title: "Full Disk Access",
                        description: "Lumesent reads macOS's notification database stored at ~/Library/Group Containers/group.com.apple.usernoted/db2/db to detect notifications from other apps. This folder is protected by macOS, and Full Disk Access is the narrowest permission Apple offers to read it. Lumesent only reads this single database file — it does not access any other files on your disk.",
                        learnMoreURL: "https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac",
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        }
                    )
                }

                if !permissionChecker.hasAccessibility {
                    PermissionRow(
                        title: "Accessibility",
                        description: "Lumesent uses the macOS Accessibility API (AXObserver) to watch the Notification Center UI for real-time notification detection. This lets it respond instantly when a notification appears, instead of relying only on periodic polling.",
                        learnMoreURL: "https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac",
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    )
                }

                if !permissionChecker.hasNotifications {
                    PermissionRow(
                        title: "Notifications",
                        description: "Optional — allows Lumesent to send native macOS notifications when an external script uses alert type \"notification\" (AppleScript: send external alert … alert type \"notification\"). Without this, only full-screen and banner alerts work.",
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    )
                }
            }

            Text("Grant permissions in System Settings, then return here. This banner disappears automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("Lumesent is open source — verify its behavior anytime:")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shadyabhi/lumesent")!)
                }) {
                    Text("View Source on GitHub")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.red, Color.orange],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .foregroundStyle(.white)
    }
}

struct NotificationPermissionBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notification permission not granted")
                    .font(.system(size: 12, weight: .semibold))
                Text("Native macOS notifications (--alert-type notification) won't work without this. Full-screen and banner alerts are unaffected.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    var learnMoreURL: String? = nil
    let action: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Text(isExpanded ? "Less" : "Why?")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button(action: action) {
                    Text("Open Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)

                if let urlString = learnMoreURL, let url = URL(string: urlString) {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                            Text("Apple Support: Learn more")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 24)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Rules Tab

struct RulesTab: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var history: NotificationHistory
    let onRulesChanged: ([FilterRule]) -> Void
    let onTestRule: (FilterRule) -> Void

    @State private var editingRule: FilterRule?
    @State private var selectedLabel: String? = nil
    @State private var importExportMessage = ""
    @State private var showingImportExportAlert = false

    private var allLabels: [String] {
        let labels = Set(ruleStore.rules.compactMap { $0.label.isEmpty ? nil : $0.label })
        return labels.sorted()
    }

    private var labelCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for rule in ruleStore.rules where !rule.label.isEmpty {
            counts[rule.label, default: 0] += 1
        }
        return counts
    }

    private var filteredRuleIndices: [Int] {
        guard let label = selectedLabel else {
            return Array(ruleStore.rules.indices)
        }
        return ruleStore.rules.indices.filter { ruleStore.rules[$0].label == label }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsDetailSectionCard(title: "Library") {
                HStack(spacing: 10) {
                    if !allLabels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                LabelChip(label: "All", count: ruleStore.rules.count, isSelected: selectedLabel == nil) {
                                    selectedLabel = nil
                                }
                                ForEach(allLabels, id: \.self) { label in
                                    LabelChip(label: label, count: labelCounts[label] ?? 0, isSelected: selectedLabel == label) {
                                        selectedLabel = selectedLabel == label ? nil : label
                                    }
                                }
                            }
                        }
                    }

                    Spacer()

                    Button(action: exportRules) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Export")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: importRules) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11))
                            Text("Import")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: addRule) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add Rule")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
            .padding(.vertical, 12)

            Divider()

            // Rules list
            if ruleStore.rules.isEmpty {
                emptyState
            } else if filteredRuleIndices.isEmpty {
                VStack(spacing: 8) {
                    Text("No rules with this label")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRuleIndices, id: \.self) { index in
                        RuleCard(
                            rule: $ruleStore.rules[index],
                            isEditing: editingRule?.id == ruleStore.rules[index].id,
                            history: history,
                            allLabels: allLabels,
                            onToggleEdit: {
                                if editingRule?.id == ruleStore.rules[index].id {
                                    editingRule = nil
                                } else {
                                    editingRule = ruleStore.rules[index]
                                }
                            },
                            onDelete: {
                                let id = ruleStore.rules[index].id
                                ruleStore.rules.removeAll { $0.id == id }
                                save()
                            },
                            onClone: {
                                let clone = ruleStore.rules[index].cloned()
                                ruleStore.rules.insert(clone, at: index + 1)
                                save()
                            },
                            onSave: {
                                editingRule = nil
                                save()
                            },
                            onTestRule: {
                                onTestRule(ruleStore.rules[index])
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove(perform: selectedLabel == nil ? { indices, newOffset in
                        ruleStore.rules.move(fromOffsets: indices, toOffset: newOffset)
                        save()
                    } : nil)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .alert("Rules", isPresented: $showingImportExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importExportMessage)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("No rules yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Add a rule to start filtering notifications.\nOnly matching notifications trigger full-screen alerts.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Add Your First Rule") { addRule() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addRule() {
        // Don't open another if we're already editing an empty/unsaved rule
        if let editing = editingRule,
           let existing = ruleStore.rules.first(where: { $0.id == editing.id }),
           existing.appIdentifier.isEmpty && existing.titleContains.isEmpty && existing.subtitleContains.isEmpty && existing.bodyContains.isEmpty {
            return
        }
        let rule = FilterRule()
        ruleStore.rules.insert(rule, at: 0)
        editingRule = rule
        save()
    }

    private func save() {
        ruleStore.save()
        onRulesChanged(ruleStore.rules)
    }

    private func exportRules() {
        do {
            let data = try ruleStore.exportRulesJSON()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "lumesent-rules.json"
            panel.begin { response in
                DispatchQueue.main.async {
                    guard response == .OK, let url = panel.url else { return }
                    do {
                        try data.write(to: url, options: .atomic)
                        importExportMessage = "Rules exported successfully."
                    } catch {
                        importExportMessage = "Export failed: \(error.localizedDescription)"
                    }
                    showingImportExportAlert = true
                }
            }
        } catch {
            importExportMessage = "Export failed: \(error.localizedDescription)"
            showingImportExportAlert = true
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else { return }
                do {
                    let data = try Data(contentsOf: url)
                    try ruleStore.importRules(from: data)
                    onRulesChanged(ruleStore.rules)
                    importExportMessage = "Rules imported successfully."
                } catch {
                    importExportMessage = "Import failed: \(error.localizedDescription)"
                }
                showingImportExportAlert = true
            }
        }
    }
}

// MARK: - Label Chip

struct LabelChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? Color.accentColor : .primary)
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundColor(isSelected ? Color.accentColor : Color.primary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .separatorColor).opacity(0.5))
                    )
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings detail section chrome (Rules, History, settings pane, rule editor, etc.)

private struct SettingsDetailSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.42))
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.primary.opacity(0.045), location: 0),
                                .init(color: Color.clear, location: 0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.5)
        )
    }
}

// MARK: - Rule Card

struct RuleCard: View {
    @Binding var rule: FilterRule
    let isEditing: Bool
    @ObservedObject var history: NotificationHistory
    let allLabels: [String]
    let onToggleEdit: () -> Void
    let onDelete: () -> Void
    let onClone: () -> Void
    let onSave: () -> Void
    let onTestRule: () -> Void

    @State private var isHovering = false
    @State private var showingMatches = false
    @State private var historyPreviewExpanded = false

    private var matchedEntries: [HistoryEntry] {
        history.matchedEntries(for: rule.id)
    }

    /// Average matches per hour over the last 4 hours.
    private func matchesPerHour(_ entries: [HistoryEntry]) -> Double {
        let cutoff = Date().addingTimeInterval(-4 * 3600)
        let recentCount = entries.filter { $0.date >= cutoff }.count
        return Double(recentCount) / 4.0
    }

    var body: some View {
        let matched = matchedEntries
        let matchRate = matchesPerHour(matched)
        VStack(alignment: .leading, spacing: 0) {
            // Header row (tap icon / summary / spacer / chevron to expand; toggle + trash stay separate)
            HStack(spacing: 10) {
                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: rule.isEnabled) { _, _ in onSave() }

                HStack(spacing: 10) {
                    ruleAppIcon
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ruleSummary)
                                .font(.system(size: 13))
                                .lineLimit(1)

                            if !rule.label.isEmpty {
                                Text(rule.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }

                            if !matched.isEmpty {
                                Button(action: { showingMatches.toggle() }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "bell.fill")
                                            .font(.system(size: 8))
                                        Text("\(matched.count)")
                                            .font(.system(size: 10, weight: .medium))
                                        Text("·")
                                            .font(.system(size: 10))
                                        Text(String(format: "%.1f/hr", matchRate))
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("Show matched notifications")
                                .accessibilityLabel("\(matched.count) matched notifications")
                            }
                        }

                        if !rule.isValid {
                            Text("Configure at least one filter field")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onToggleEdit()
                }
                .accessibilityLabel(isEditing ? "Collapse rule" : "Expand rule")
                .accessibilityAddTraits(.isButton)

                Button(action: onClone) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clone this rule")
                .accessibilityLabel("Clone rule")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete rule")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Matched notifications panel
            if showingMatches {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Recent Matches")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(matched.count) total")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(Array(matched.prefix(5))) { entry in
                        MatchedNotificationRow(entry: entry)
                    }

                    if matched.count > 5 {
                        Text("+ \(matched.count - 5) more")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(14)
            }

            // Edit panel
            if isEditing {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 16) {
                    SettingsDetailSectionCard(title: "Match") {
                        VStack(alignment: .leading, spacing: 8) {
                            SuggestingField("App ID:", text: $rule.appIdentifier, placeholder: "e.g. com.apple.mail or slack", history: history, field: .appIdentifier, suggestionLeadingInset: 216) {
                                Picker("", selection: $rule.appOperator) {
                                    ForEach(MatchOperator.allCases, id: \.self) { op in
                                        Text(op.rawValue).tag(op)
                                    }
                                }
                                .frame(width: 120)
                            }
                            SuggestingField("Title:", text: $rule.titleContains, placeholder: "e.g. urgent", history: history, field: .title, suggestionLeadingInset: 216) {
                                Picker("", selection: $rule.titleOperator) {
                                    ForEach(MatchOperator.allCases, id: \.self) { op in
                                        Text(op.rawValue).tag(op)
                                    }
                                }
                                .frame(width: 120)
                            }
                            SuggestingField("Subtitle:", text: $rule.subtitleContains, placeholder: "e.g. channel name", history: history, field: .subtitle, suggestionLeadingInset: 216) {
                                Picker("", selection: $rule.subtitleOperator) {
                                    ForEach(MatchOperator.allCases, id: \.self) { op in
                                        Text(op.rawValue).tag(op)
                                    }
                                }
                                .frame(width: 120)
                            }
                            SuggestingField("Body:", text: $rule.bodyContains, placeholder: "e.g. deploy failed", history: history, field: .body, suggestionLeadingInset: 216) {
                                Picker("", selection: $rule.bodyOperator) {
                                    ForEach(MatchOperator.allCases, id: \.self) { op in
                                        Text(op.rawValue).tag(op)
                                    }
                                }
                                .frame(width: 120)
                            }
                        }
                    }

                    SettingsDetailSectionCard(title: "Alert") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Description:")
                                    .frame(width: 80, alignment: .trailing)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                TextField("Optional description for this rule", text: $rule.ruleDescription)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }

                            LabelSuggestingField(text: $rule.label, allLabels: allLabels)

                            DisplayModePicker(displayMode: $rule.displayMode)

                            HStack {
                                Text("Cooldown:")
                                    .frame(width: 80, alignment: .trailing)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                TextField("sec", value: $rule.cooldownSeconds, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .frame(width: 60)

                                Text("sec")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                Text("— suppress duplicate rule matches")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }

                            HStack {
                                Text("On dismiss:")
                                    .frame(width: 80, alignment: .trailing)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                Picker("", selection: $rule.focusSourceOnDismiss) {
                                    Text("Focus source").tag(true)
                                    Text("Nothing").tag(false)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                        }
                    }

                    if rule.isValid {
                        SettingsDetailSectionCard(title: "") {
                            ruleHistoryPreviewDisclosure
                        }
                    }
                }
                .padding(14)

                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Button("Test this rule") {
                            onTestRule()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!rule.isValid)

                        Spacer()
                        Button("Done") { onSave() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.38))
            }
        }
        .background(isHovering && !isEditing ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovering && !isEditing ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .onHover { hovering in isHovering = hovering }
    }

    private var ruleSummary: String {
        if !rule.ruleDescription.isEmpty { return rule.ruleDescription }
        var parts: [String] = []
        if !rule.appIdentifier.isEmpty {
            parts.append(AppNameCache.shared.name(for: rule.appIdentifier))
        }
        if !rule.titleContains.isEmpty { parts.append("title \(rule.titleOperator.rawValue) \"\(rule.titleContains)\"") }
        if !rule.subtitleContains.isEmpty { parts.append("subtitle \(rule.subtitleOperator.rawValue) \"\(rule.subtitleContains)\"") }
        if !rule.bodyContains.isEmpty { parts.append("body \(rule.bodyOperator.rawValue) \"\(rule.bodyContains)\"") }
        return parts.isEmpty ? "New Rule (unconfigured)" : parts.joined(separator: " + ")
    }

    /// History entries that would match the current filter fields (same AND logic as the engine).
    private var historyPreviewMatches: [HistoryEntry] {
        history.entries
            .filter { entry in
                let n = NotificationRecord(id: 0, appIdentifier: entry.appIdentifier, title: entry.title, subtitle: entry.subtitle, body: entry.body, deliveredDate: entry.date)
                return rule.matchesFields(of: n)
            }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var ruleHistoryPreviewDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                historyPreviewExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: historyPreviewExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .center)

                    Text("Matches in history")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(historyPreviewMatches.count) in last \(NotificationHistory.storedEntryLimit)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(historyPreviewExpanded ? "Hide history matches" : "Show history matches")

            if historyPreviewExpanded {
                ruleHistoryPreviewInner
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var ruleHistoryPreviewInner: some View {
        if historyPreviewMatches.isEmpty {
            Text("Nothing in your saved history matches these filters yet. New notifications will match if they fit.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(historyPreviewMatches.prefix(12))) { entry in
                        MatchedNotificationRow(entry: entry)
                    }
                }
            }
            .frame(maxHeight: 220)

            if historyPreviewMatches.count > 12 {
                Text("+ \(historyPreviewMatches.count - 12) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var ruleAppIcon: some View {
        if rule.appIdentifier.isEmpty {
            Image(systemName: "app.dashed")
                .resizable()
                .foregroundStyle(.secondary)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.appIdentifier),
                  let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Matched Notification Row

struct MatchedNotificationRow: View {
    let entry: HistoryEntry
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AppIconView(bundleIdentifier: entry.appIdentifier)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    if !entry.title.isEmpty {
                        Text(entry.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(relativeTime(entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
        .onHover { hovering in isHovering = hovering }
        .contentShape(Rectangle())
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    @ObservedObject var history: NotificationHistory
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var appSettings: AppSettings
    let onRulesChanged: ([FilterRule]) -> Void

    @State private var showMatchedOnly: Bool = false

    private var historyEntries: [HistoryEntry] {
        if showMatchedOnly {
            return history.entries.reversed().filter(\.isDisplayableMatch)
        }
        return Array(history.entries.reversed())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: !showMatchedOnly) { showMatchedOnly = false }
                FilterChip(label: "Matched", icon: "bell.fill", isSelected: showMatchedOnly) { showMatchedOnly = true }
                Spacer()
            }
            .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
            .padding(.vertical, 8)

            Divider()

            if historyEntries.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: showMatchedOnly ? "bell.slash" : "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(showMatchedOnly ? "No matched alerts yet" : "No notifications yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(showMatchedOnly ? "Alerts that trigger your rules will appear here." : "Notifications will appear here as they arrive.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    SettingsDetailSectionCard(title: showMatchedOnly ? "Matched notifications" : "Notification history") {
                        LazyVStack(spacing: 8) {
                            ForEach(historyEntries) { entry in
                                HistoryRow(entry: entry, ruleStore: ruleStore, appSettings: appSettings, onRulesChanged: onRulesChanged)
                            }
                        }
                    }
                    .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

// MARK: - History Notification Row

struct HistoryRow: View {
    let entry: HistoryEntry
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var appSettings: AppSettings
    let onRulesChanged: ([FilterRule]) -> Void

    @State private var showingCreateRule = false
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(bundleIdentifier: entry.appIdentifier)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.appName.isEmpty ? entry.appIdentifier : entry.appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if entry.sourceVisibleSuppressed {
                        StatusBadge(label: "fullscreen downgraded, active window", color: .blue)
                    } else if entry.cooldownSuppressed {
                        StatusBadge(label: "cooldown", color: .orange)
                    } else if entry.matched {
                        StatusBadge(label: "matched", color: .green)
                    }
                    Text(relativeTime(entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                }

                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Button(action: { showingCreateRule.toggle() }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Create rule from this notification")
            .accessibilityLabel("Create rule from this notification")
            .popover(isPresented: $showingCreateRule, arrowEdge: .trailing) {
                QuickRuleCreator(entry: entry, ruleStore: ruleStore, onRulesChanged: onRulesChanged) {
                    showingCreateRule = false
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .onHover { hovering in isHovering = hovering }
        .contentShape(Rectangle())
        .onTapGesture { previewAlert() }
        .help("Click to preview full-screen alert")
    }

    private func previewAlert() {
        let record = NotificationRecord(
            id: -1,
            appIdentifier: entry.appIdentifier,
            title: entry.title,
            subtitle: entry.subtitle,
            body: entry.body,
            deliveredDate: entry.date
        )
        FullScreenAlertWindow.show(
            notification: record,
            displayMode: .defaultTimed,
            dismissKey: appSettings.dismissKey,
            presentation: appSettings.alertPresentation
        )
    }
}

// MARK: - Quick Rule Creator (popover from history notification)

struct QuickRuleCreator: View {
    let entry: HistoryEntry
    @ObservedObject var ruleStore: RuleStore
    let onRulesChanged: ([FilterRule]) -> Void
    let onDismiss: () -> Void

    @State private var useApp = true
    @State private var useTitle = false
    @State private var useSubtitle = false
    @State private var useBody = false
    @State private var label = ""

    @State private var editApp: String
    @State private var editTitle: String
    @State private var editSubtitle: String
    @State private var editBody: String

    @State private var showingConfirmation = false

    init(entry: HistoryEntry, ruleStore: RuleStore, onRulesChanged: @escaping ([FilterRule]) -> Void, onDismiss: @escaping () -> Void) {
        self.entry = entry
        self.ruleStore = ruleStore
        self.onRulesChanged = onRulesChanged
        self.onDismiss = onDismiss
        self._editApp = State(initialValue: entry.appIdentifier)
        self._editTitle = State(initialValue: entry.title)
        self._editSubtitle = State(initialValue: entry.subtitle)
        self._editBody = State(initialValue: entry.body)
    }

    private var allLabels: [String] {
        Set(ruleStore.rules.compactMap { $0.label.isEmpty ? nil : $0.label }).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Rule")
                .font(.system(size: 13, weight: .semibold))

            SettingsDetailSectionCard(title: "Match") {
                VStack(alignment: .leading, spacing: 8) {
                    quickRuleField(label: "App:", isOn: $useApp, text: $editApp)

                    if !entry.title.isEmpty {
                        quickRuleField(label: "Title:", isOn: $useTitle, text: $editTitle)
                    }

                    if !entry.subtitle.isEmpty {
                        quickRuleField(label: "Subtitle:", isOn: $useSubtitle, text: $editSubtitle)
                    }

                    if !entry.body.isEmpty {
                        quickRuleField(label: "Body:", isOn: $useBody, text: $editBody)
                    }
                }
            }

            SettingsDetailSectionCard(title: "Label") {
                LabelSuggestingField(text: $label, allLabels: allLabels)
            }

            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel") { onDismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Create") { showingConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!useApp && !useTitle && !useSubtitle && !useBody)
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(width: 420)
        .alert("Create Rule?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Create") { createRule() }
        } message: {
            Text("This will create a rule matching:\n\(confirmationSummary)")
        }
    }

    @ViewBuilder
    private func quickRuleField(label: String, isOn: Binding<Bool>, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 52, alignment: .trailing)

            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .disabled(!isOn.wrappedValue)
                .opacity(isOn.wrappedValue ? 1.0 : 0.5)
        }
    }

    private var confirmationSummary: String {
        var parts: [String] = []
        if useApp { parts.append("App: \(editApp)") }
        if useTitle { parts.append("Title: \(editTitle)") }
        if useSubtitle { parts.append("Subtitle: \(editSubtitle)") }
        if useBody { parts.append("Body: \(editBody)") }
        return parts.joined(separator: "\n")
    }

    private func createRule() {
        let rule = FilterRule(
            appIdentifier: useApp ? editApp : "",
            titleContains: useTitle ? editTitle : "",
            subtitleContains: useSubtitle ? editSubtitle : "",
            bodyContains: useBody ? editBody : "",
            label: label
        )
        ruleStore.rules.append(rule)
        ruleStore.save()
        onRulesChanged(ruleStore.rules)
        onDismiss()
    }
}

// MARK: - Suggesting Field

struct SuggestingField<LabelAccessory: View>: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    @ObservedObject var history: NotificationHistory
    let field: SuggestionField
    /// Leading inset so suggestion popovers align with the text field (label 80 + spacing 8 + picker 120 + spacing 8 = 216).
    let suggestionLeadingInset: CGFloat
    @ViewBuilder let labelAccessory: () -> LabelAccessory

    @FocusState private var isFocused: Bool
    @State private var showSuggestions = false

    init(_ label: String, text: Binding<String>, placeholder: String, history: NotificationHistory, field: SuggestionField, suggestionLeadingInset: CGFloat = 88, @ViewBuilder labelAccessory: @escaping () -> LabelAccessory) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.history = history
        self.field = field
        self.suggestionLeadingInset = suggestionLeadingInset
        self.labelAccessory = labelAccessory
    }

    private var suggestions: [Suggestion] {
        history.suggestions(for: field, matching: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label)
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                labelAccessory()
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(minWidth: 280, maxWidth: .infinity)
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        if focused {
                            showSuggestions = true
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showSuggestions = false
                            }
                        }
                    }
                    .onChange(of: text) { _, _ in
                        showSuggestions = isFocused
                    }
            }

            if showSuggestions && !suggestions.isEmpty {
                HStack(spacing: 0) {
                    Spacer().frame(width: suggestionLeadingInset)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestions.prefix(5))) { suggestion in
                            SuggestionRow(suggestion: suggestion) {
                                text = suggestion.displayValue
                                showSuggestions = false
                            }
                            if suggestion.id != suggestions.prefix(5).last?.id {
                                Divider().padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
                .padding(.top, 2)
            }
        }
    }
}

extension SuggestingField where LabelAccessory == EmptyView {
    init(_ label: String, text: Binding<String>, placeholder: String, history: NotificationHistory, field: SuggestionField) {
        self.init(label, text: text, placeholder: placeholder, history: history, field: field, suggestionLeadingInset: 88, labelAccessory: { EmptyView() })
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let suggestion: Suggestion
    let onSelect: () -> Void

    @State private var showingPreview = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 0) {
                    Text(suggestion.displayValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(relativeTime(suggestion.entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { showingPreview.toggle() }) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview notification details")
            .popover(isPresented: $showingPreview, arrowEdge: .trailing) {
                NotificationPreview(entry: suggestion.entry)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Notification Preview

struct NotificationPreview: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(bundleIdentifier: entry.appIdentifier)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.appName.isEmpty ? entry.appIdentifier : entry.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(relativeTime(entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                }

                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Settings Tab (app preferences)

struct SettingsTab: View {
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var history: NotificationHistory
    @State private var showingServiceStatus = false
    @State private var serviceStatusMessage = ""
    @State private var showingClearHistoryConfirmation = false
    @State private var editingSocketPath: String = ""
    @State private var isEditingSocketPath: Bool = false

    /// AppKit label color: reliable on grouped controls; `.secondary` inside `Toggle` labels can render nearly invisible on macOS.
    private var captionColor: Color { Color(nsColor: .secondaryLabelColor) }

    private var layoutBinding: Binding<AlertLayout> {
        Binding(
            get: { appSettings.alertPresentation.layout },
            set: {
                appSettings.alertPresentation = AlertPresentation(
                    layout: $0,
                    screens: appSettings.alertPresentation.screens
                )
            }
        )
    }

    private var screensBinding: Binding<AlertScreens> {
        Binding(
            get: { appSettings.alertPresentation.screens },
            set: { newValue in
                appSettings.alertPresentation = AlertPresentation(
                    layout: appSettings.alertPresentation.layout,
                    screens: newValue
                )
                flashScreens(mode: newValue)
            }
        )
    }

    private func flashScreens(mode: AlertScreens) {
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        var windows: [NSWindow] = []

        for screen in NSScreen.screens {
            let isMain = (screen == mainScreen)
            let message: String
            switch mode {
            case .main:
                message = isMain ? "✓ This is your main display" : ""
            case .allScreens:
                message = "✓ Lumesent covers this display"
            }
            guard !message.isEmpty else { continue }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 28, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.sizeToFit()
            label.frame.origin = NSPoint(
                x: (screen.frame.width - label.frame.width) / 2,
                y: (screen.frame.height - label.frame.height) / 2
            )

            let container = NSView(frame: screen.frame)
            container.addSubview(label)
            window.contentView = container

            window.setFrame(screen.frame, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }

        guard !windows.isEmpty else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            for w in windows { w.animator().alphaValue = 1 }
        }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    for w in windows { w.animator().alphaValue = 0 }
                }) {
                    for w in windows { w.orderOut(nil) }
                }
            }
        }
    }

    private var loginServiceToggleBinding: Binding<Bool> {
        Binding(
            get: { ServiceManager.isInstalled },
            set: { newValue in
                do {
                    if newValue {
                        try ServiceManager.install()
                        serviceStatusMessage = "Lumesent will now start automatically on login and restart on crash."
                    } else {
                        try ServiceManager.uninstall()
                        serviceStatusMessage = "Login service removed."
                    }
                } catch {
                    serviceStatusMessage = "Error: \(error.localizedDescription)"
                }
                showingServiceStatus = true
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsDetailSectionCard(title: "Alerts") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Layout & screens")
                            .font(.system(size: 13, weight: .medium))

                        Picker("Alert layout", selection: layoutBinding) {
                            ForEach(AlertLayout.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Screens", selection: screensBinding) {
                            ForEach(AlertScreens.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)

                        Divider()

                        Text("When source window is active")
                            .font(.system(size: 13, weight: .medium))
                        Text("Controls what happens to full-screen alerts when the tmux pane that sent the notification is already active and its terminal app is frontmost.")
                            .font(.system(size: 11))
                            .foregroundStyle(captionColor)
                            .fixedSize(horizontal: false, vertical: true)
                        Picker("", selection: $appSettings.activeWindowBehavior) {
                            ForEach(ActiveWindowBehavior.allCases, id: \.self) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        .onChange(of: appSettings.activeWindowBehavior) { _, _ in
                            appSettings.save()
                        }

                        Divider()

                        Text("Sound")
                            .font(.system(size: 13, weight: .medium))

                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: $appSettings.soundEnabled)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("Play sound on alert")

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Play sound on alert")
                                    .font(.system(size: 13))
                                Text("Plays a sound each time a full-screen alert is shown.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(captionColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: appSettings.soundEnabled) { _, _ in
                            appSettings.save()
                        }

                        if appSettings.soundEnabled {
                            HStack(spacing: 8) {
                                Text("Sound:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(captionColor)

                                Picker("Sound", selection: $appSettings.alertSound) {
                                    Text("System default").tag(AlertSoundName?.none)
                                    ForEach(AlertSoundName.allCases, id: \.self) { sound in
                                        Text(sound.rawValue).tag(Optional(sound))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 180)
                                .onChange(of: appSettings.alertSound) { _, _ in
                                    appSettings.save()
                                    appSettings.playAlertSound()
                                }
                            }
                        }
                    }
                }

                SettingsDetailSectionCard(title: "Application") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: $appSettings.showInDock)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("Show icon in Dock")

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show icon in Dock")
                                    .font(.system(size: 13))
                                Text("Off keeps Lumesent as a menu bar–only app.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(captionColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: appSettings.showInDock) { _, _ in
                            appSettings.save()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Socket path")
                                .font(.system(size: 13, weight: .medium))
                            Text("Unix socket used for external notifications via the CLI.")
                                .font(.system(size: 11))
                                .foregroundStyle(captionColor)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                TextField("", text: $editingSocketPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                    .disabled(!isEditingSocketPath)
                                if isEditingSocketPath {
                                    if editingSocketPath != appSettings.socketPath {
                                        Button("Save") {
                                            appSettings.socketPath = editingSocketPath
                                            appSettings.save()
                                            isEditingSocketPath = false
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                } else {
                                    Button("Edit") {
                                        isEditingSocketPath = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                if editingSocketPath != FileLocations.defaultSocketPath {
                                    Button("Reset") {
                                        editingSocketPath = FileLocations.defaultSocketPath
                                        appSettings.socketPath = FileLocations.defaultSocketPath
                                        appSettings.save()
                                        isEditingSocketPath = false
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .onAppear { editingSocketPath = appSettings.socketPath }
                    }
                }

                SettingsDetailSectionCard(title: "Updates") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Update channel")
                                .font(.system(size: 13))
                            Picker("", selection: $appSettings.updateChannel) {
                                ForEach(UpdateChannel.allCases, id: \.self) { channel in
                                    Text(channel.displayName).tag(channel)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        Text("Stable tracks tagged releases. Head tracks the latest build from main.")
                            .font(.system(size: 11))
                            .foregroundStyle(captionColor)

                        HStack(spacing: 12) {
                            Text("Check interval")
                                .font(.system(size: 13))
                            Picker("", selection: $appSettings.updateCheckInterval) {
                                ForEach(UpdateCheckInterval.allCases, id: \.self) { interval in
                                    Text(interval.displayName).tag(interval)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    .onChange(of: appSettings.updateChannel) { _, _ in
                        appSettings.save()
                    }
                    .onChange(of: appSettings.updateCheckInterval) { _, newValue in
                        appSettings.save()
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.updaterController.updater.updateCheckInterval = TimeInterval(newValue.rawValue)
                        }
                    }
                }

                SettingsDetailSectionCard(title: "Dismiss alerts") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcut to dismiss the full-screen alert. Clicking still works.")
                            .font(.system(size: 11))
                            .foregroundStyle(captionColor)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            KeyCaptureButton(shortcut: $appSettings.dismissKey)

                            if appSettings.dismissKey != nil {
                                Button("Clear") {
                                    appSettings.dismissKey = nil
                                    appSettings.save()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Clear dismiss shortcut")
                            }
                        }
                    }
                }

                SettingsDetailSectionCard(title: "Login") {
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: loginServiceToggleBinding)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Start at Login")

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start at Login")
                                .font(.system(size: 13))
                            Text("Runs as a background service with crash recovery.")
                                .font(.system(size: 11))
                                .foregroundStyle(captionColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SettingsDetailSectionCard(title: "Data") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lumesent stores the last \(NotificationHistory.storedEntryLimit) notifications locally for rule-building suggestions.")
                            .font(.system(size: 11))
                            .foregroundStyle(captionColor)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Button("Clear History") {
                                showingClearHistoryConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(history.entries.isEmpty)

                            if !history.entries.isEmpty {
                                Text("\(history.entries.count) entries")
                                    .font(.system(size: 11))
                                    .foregroundStyle(captionColor)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, SettingsChromeLayout.detailContentHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: appSettings.dismissKey) { _, _ in
            appSettings.save()
        }
        .onChange(of: appSettings.alertPresentation) { _, _ in
            appSettings.save()
        }
        .alert("Login Service", isPresented: $showingServiceStatus) {
            Button("OK") {}
        } message: {
            Text(serviceStatusMessage)
        }
        .alert("Clear Notification History?", isPresented: $showingClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                history.clearAll()
            }
        } message: {
            Text("This will permanently delete all stored notification history. This cannot be undone.")
        }
    }
}

// MARK: - Key Capture Button

struct KeyCaptureButton: NSViewRepresentable {
    @Binding var shortcut: DismissKeyShortcut?

    func makeNSView(context: Context) -> KeyCaptureNSButton {
        let button = KeyCaptureNSButton()
        button.onKeyCapture = { event in
            shortcut = DismissKeyShortcut.from(event: event)
            // Find and save via the binding's parent
        }
        button.updateTitle(shortcut: shortcut)
        return button
    }

    func updateNSView(_ nsView: KeyCaptureNSButton, context: Context) {
        nsView.updateTitle(shortcut: shortcut)
    }
}

final class KeyCaptureNSButton: NSButton {
    var onKeyCapture: ((NSEventShim) -> Void)?
    private var isCapturing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startCapture)
        focusRingType = .exterior
    }

    func updateTitle(shortcut: DismissKeyShortcut?) {
        if isCapturing {
            title = "Press a key..."
        } else if let shortcut = shortcut {
            title = shortcut.displayName
        } else {
            title = "Click to set shortcut"
        }
        sizeToFit()
    }

    @objc private func startCapture() {
        isCapturing = true
        title = "Press a key..."
        sizeToFit()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        // Ignore bare modifier keys
        if event.keyCode == 56 || event.keyCode == 57 || event.keyCode == 58 ||
           event.keyCode == 59 || event.keyCode == 60 || event.keyCode == 61 ||
           event.keyCode == 62 || event.keyCode == 63 {
            return
        }

        isCapturing = false
        let displayName = Self.displayName(for: event)
        let shim = NSEventShim(
            keyCode: event.keyCode,
            modifierRawValue: UInt(event.modifierFlags.rawValue),
            displayName: displayName
        )
        onKeyCapture?(shim)
    }

    override func resignFirstResponder() -> Bool {
        if isCapturing {
            isCapturing = false
            updateTitle(shortcut: nil)
        }
        return super.resignFirstResponder()
    }

    private static func displayName(for event: NSEvent) -> String {
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("\u{2303}") }  // ⌃
        if flags.contains(.option) { parts.append("\u{2325}") }   // ⌥
        if flags.contains(.shift) { parts.append("\u{21E7}") }    // ⇧
        if flags.contains(.command) { parts.append("\u{2318}") }  // ⌘

        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            // Map special keys
            let special: [UInt16: String] = [
                36: "\u{21A9}", 48: "\u{21E5}", 49: "Space", 51: "\u{232B}",
                53: "\u{238B}", 123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
                76: "\u{21A9}", 117: "\u{2326}",
            ]
            if let s = special[event.keyCode] {
                parts.append(s)
            } else {
                parts.append(chars)
            }
        }

        return parts.joined()
    }
}

// MARK: - Label Suggesting Field

struct LabelSuggestingField: View {
    @Binding var text: String
    let allLabels: [String]

    @FocusState private var isFocused: Bool
    @State private var showSuggestions = false
    @State private var draft: String = ""

    private var filteredLabels: [String] {
        if draft.isEmpty {
            return allLabels
        }
        let q = draft.lowercased()
        return allLabels.filter { $0.lowercased().contains(q) && $0 != draft }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Label:")
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("e.g. work, personal", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(minWidth: 280, maxWidth: .infinity)
                    .focused($isFocused)
                    .onAppear { draft = text }
                    .onChange(of: text) { _, newValue in
                        if newValue != draft { draft = newValue }
                    }
                    .onSubmit { text = draft }
                    .onChange(of: isFocused) { _, focused in
                        if focused {
                            showSuggestions = true
                        } else {
                            text = draft
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showSuggestions = false
                            }
                        }
                    }
                    .onChange(of: draft) { _, newDraft in
                        text = newDraft
                        showSuggestions = isFocused
                    }
            }

            if showSuggestions && !filteredLabels.isEmpty {
                HStack(spacing: 0) {
                    Spacer().frame(width: 88)
                    HStack(spacing: 4) {
                        ForEach(filteredLabels, id: \.self) { label in
                            Button(action: {
                                draft = label
                                text = label
                                showSuggestions = false
                            }) {
                                Text(label)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Display Mode Picker

struct DisplayModePicker: View {
    @Binding var displayMode: AlertDisplayMode

    private var isSticky: Bool {
        displayMode.isSticky
    }

    private var timeoutText: String {
        if let seconds = displayMode.timeoutSeconds {
            // Show integer if whole number
            return seconds.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(seconds))"
                : "\(seconds)"
        }
        return "8"
    }

    var body: some View {
        HStack {
            Text("Display:")
                .frame(width: 80, alignment: .trailing)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { isSticky },
                set: { sticky in
                    if sticky {
                        displayMode = .sticky
                    } else {
                        displayMode = .defaultTimed
                    }
                }
            )) {
                Text("Auto-dismiss").tag(false)
                Text("Sticky").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            if !isSticky {
                TextField("sec", text: Binding(
                    get: { timeoutText },
                    set: { newVal in
                        if let seconds = Double(newVal), seconds > 0 {
                            displayMode = .timed(seconds: seconds)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 50)

                Text("sec")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Logs Tab

import OSLog

struct LogsTab: View {
    @ObservedObject var logStore: LogStore
    @State private var searchText = ""
    @State private var showErrorsOnly = false
    @State private var selectedTimeWindow: TimeInterval = 3600

    private static let timeWindowOptions: [(label: String, seconds: TimeInterval)] = [
        ("5m", 300),
        ("15m", 900),
        ("30m", 1800),
        ("1h", 3600),
        ("2h", 7200),
        ("6h", 21600),
    ]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var displayedEntries: [LogEntry] {
        var result = showErrorsOnly ? logStore.entries.filter(\.isError) : logStore.entries
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.message.lowercased().contains(q)
                || $0.levelLabel.lowercased().contains(q)
                || Self.timeFormatter.string(from: $0.date).contains(q)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Filter logs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

                Toggle("Errors only", isOn: $showErrorsOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Picker("Time", selection: $selectedTimeWindow) {
                    ForEach(Self.timeWindowOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
                .frame(width: 90)
                .onChange(of: selectedTimeWindow) { _, newValue in
                    logStore.timeWindow = newValue
                    logStore.fetch()
                }

                Spacer()

                Text("\(displayedEntries.count) entries")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button {
                    logStore.fetch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Refresh logs")
            }
            .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
            .padding(.vertical, 10)

            Divider()

            // Log entries
            if logStore.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading logs...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text(showErrorsOnly ? "No errors" : "No log entries")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(displayedEntries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        if let last = displayedEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: logStore.entries.count) { _, _ in
                        if let last = displayedEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .onAppear { logStore.start() }
        .onDisappear { logStore.stop() }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 85, alignment: .leading)

            Text(entry.levelLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 48, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.isError ? .red : .primary)
                .lineLimit(nil)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(entry.isError ? Color.red.opacity(0.06) : Color.clear)
    }

    private func levelColor(_ level: OSLogEntryLog.Level) -> Color {
        switch level {
        case .error, .fault: return .red
        case .notice: return .orange
        case .info: return .blue
        case .debug: return .secondary
        default: return .secondary
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Helpers

func relativeTime(_ date: Date) -> String {
    let seconds = max(0, Int(-date.timeIntervalSinceNow))
    if seconds < 60 { return "just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    if days < 7 { return "\(days)d ago" }
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    return formatter.string(from: date)
}
