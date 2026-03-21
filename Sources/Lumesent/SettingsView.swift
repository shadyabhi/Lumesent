import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings sidebar / General tab scroll targets

enum SettingsGeneralSection: Hashable {
    case alerts
    case application
    case keyboard
    case login

    var title: String {
        switch self {
        case .alerts: return "Alerts"
        case .application: return "Application"
        case .keyboard: return "Keyboard"
        case .login: return "Login"
        }
    }
}

// MARK: - Settings View (sidebar + detail, Xcode-style)

private enum SettingsChromeLayout {
    /// Matches `navigationSplitViewColumnWidth` ideal so the app name lines up with the sidebar column.
    static let sidebarIdealWidth: CGFloat = 200
    static let sidebarContentLeadingPadding: CGFloat = 12
    static let detailContentHorizontalPadding: CGFloat = 24
}

struct SettingsView: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var history: NotificationHistory
    @ObservedObject var permissionChecker: PermissionChecker
    let onRulesChanged: ([FilterRule]) -> Void
    let onTestRule: (FilterRule) -> Void

    @State private var selectedSidebarItem: SettingsSidebarItem = .rulesActive
    @Environment(\.colorScheme) private var colorScheme

    enum SettingsSidebarItem: Hashable {
        case rulesActive
        case unmatched
        case general(SettingsGeneralSection)

        var detailTitle: String {
            switch self {
            case .rulesActive: return "Active"
            case .unmatched: return "Unmatched"
            case .general(let section): return section.title
            }
        }
    }

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
                        SettingsSidebarGroup(title: "Rules", colorScheme: colorScheme) {
                            settingsSidebarRow(
                                title: "Active",
                                systemImage: "checkmark.circle",
                                item: .rulesActive
                            )
                            settingsSidebarRow(
                                title: "Unmatched",
                                systemImage: "bell.slash",
                                item: .unmatched
                            )
                        }
                        SettingsSidebarGroup(title: "Settings", colorScheme: colorScheme) {
                            settingsSidebarRow(
                                title: SettingsGeneralSection.alerts.title,
                                systemImage: "bell.badge",
                                item: .general(.alerts)
                            )
                            settingsSidebarRow(
                                title: SettingsGeneralSection.application.title,
                                systemImage: "app",
                                item: .general(.application)
                            )
                            settingsSidebarRow(
                                title: SettingsGeneralSection.keyboard.title,
                                systemImage: "keyboard",
                                item: .general(.keyboard)
                            )
                            settingsSidebarRow(
                                title: SettingsGeneralSection.login.title,
                                systemImage: "power",
                                item: .general(.login)
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
                        case .unmatched:
                            UnmatchedTab(history: history, ruleStore: ruleStore, onRulesChanged: onRulesChanged)
                        case .general(let section):
                            GeneralTab(appSettings: appSettings, scrollFocus: section)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea(edges: .top)
                .toolbar(.hidden)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
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
    var colorScheme: ColorScheme
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(sidebarBoxFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                }
        }
    }

    private var sidebarBoxFill: Color {
        if colorScheme == .dark {
            return Color(white: 0.11)
        }
        return Color(nsColor: .controlBackgroundColor)
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
        .buttonStyle(.plain)
        .help("Permission status — click to check")
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                PermissionStatusRow(label: "Full Disk Access", ok: permissionChecker.hasFullDiskAccess)
                PermissionStatusRow(label: "Accessibility", ok: permissionChecker.hasAccessibility)
                PermissionStatusRow(label: "Notifications", ok: permissionChecker.hasNotifications)
            }
            .padding(12)
            .frame(width: 200)
        }
    }
}

struct PermissionStatusRow: View {
    let label: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(ok ? .green : .red)
            Text(label)
                .font(.system(size: 12))
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
                        description: "Optional — allows Lumesent to send native macOS notifications via the --send --alert-type notification CLI command. Without this, only full-screen and banner alerts work.",
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

    private var filteredRules: [FilterRule] {
        guard let label = selectedLabel else { return ruleStore.rules }
        return ruleStore.rules.filter { $0.label == label }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: label filter + add button
            HStack(spacing: 10) {
                // Label filter chips
                if !allLabels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            LabelChip(label: "All", isSelected: selectedLabel == nil) {
                                selectedLabel = nil
                            }
                            ForEach(allLabels, id: \.self) { label in
                                LabelChip(label: label, isSelected: selectedLabel == label) {
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
            .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
            .padding(.vertical, 12)

            Divider()

            // Rules list
            if ruleStore.rules.isEmpty {
                emptyState
            } else if filteredRules.isEmpty {
                VStack(spacing: 8) {
                    Text("No rules with this label")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedLabel == nil {
                List {
                    ForEach($ruleStore.rules) { $rule in
                        RuleCard(
                            rule: $rule,
                            isEditing: editingRule?.id == $rule.wrappedValue.id,
                            history: history,
                            allLabels: allLabels,
                            onToggleEdit: {
                                if editingRule?.id == $rule.wrappedValue.id {
                                    editingRule = nil
                                } else {
                                    editingRule = $rule.wrappedValue
                                }
                            },
                            onDelete: {
                                let id = $rule.wrappedValue.id
                                ruleStore.rules.removeAll { $0.id == id }
                                save()
                            },
                            onSave: {
                                editingRule = nil
                                save()
                            },
                            onTestRule: {
                                onTestRule($rule.wrappedValue)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { indices, newOffset in
                        ruleStore.rules.move(fromOffsets: indices, toOffset: newOffset)
                        save()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredRules) { rule in
                            if let index = ruleStore.rules.firstIndex(where: { $0.id == rule.id }) {
                                RuleCard(
                                    rule: $ruleStore.rules[index],
                                    isEditing: editingRule?.id == rule.id,
                                    history: history,
                                    allLabels: allLabels,
                                    onToggleEdit: {
                                        editingRule = (editingRule?.id == rule.id) ? nil : rule
                                    },
                                    onDelete: {
                                        ruleStore.rules.removeAll { $0.id == rule.id }
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
                            }
                        }
                    }
                    .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
                    .padding(.vertical, 12)
                }
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
        let rule = FilterRule()
        ruleStore.rules.append(rule)
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
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
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
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
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
    let onSave: () -> Void
    let onTestRule: () -> Void

    @State private var showingMatches = false

    private var matchedEntries: [HistoryEntry] {
        history.matchedEntries(for: rule.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: rule.isEnabled) { _, _ in onSave() }

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

                        if !matchedEntries.isEmpty {
                            Button(action: { showingMatches.toggle() }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 8))
                                    Text("\(matchedEntries.count)")
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
                        }
                    }

                    if !rule.isValid {
                        Text("Configure at least one filter field")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Button(action: onToggleEdit) {
                    Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
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
                        Text("\(matchedEntries.count) total")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(Array(matchedEntries.prefix(5))) { entry in
                        MatchedNotificationRow(entry: entry)
                    }

                    if matchedEntries.count > 5 {
                        Text("+ \(matchedEntries.count - 5) more")
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

                VStack(alignment: .leading, spacing: 8) {
                    SuggestingField("App ID:", text: $rule.appIdentifier, placeholder: "e.g. com.apple.mail or slack", history: history, field: .appIdentifier)
                    HStack(spacing: 4) {
                        SuggestingField("Title:", text: $rule.titleContains, placeholder: "e.g. urgent", history: history, field: .title)
                        Picker("", selection: $rule.titleOperator) {
                            ForEach(MatchOperator.allCases, id: \.self) { op in
                                Text(op.rawValue).tag(op)
                            }
                        }
                        .frame(width: 90)
                    }
                    HStack(spacing: 4) {
                        SuggestingField("Body:", text: $rule.bodyContains, placeholder: "e.g. deploy failed", history: history, field: .body)
                        Picker("", selection: $rule.bodyOperator) {
                            ForEach(MatchOperator.allCases, id: \.self) { op in
                                Text(op.rawValue).tag(op)
                            }
                        }
                        .frame(width: 90)
                    }

                    LabelSuggestingField(text: $rule.label, allLabels: allLabels)

                    DisplayModePicker(displayMode: $rule.displayMode)

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
                }
                .padding(14)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var ruleSummary: String {
        var parts: [String] = []
        if !rule.appIdentifier.isEmpty { parts.append("app: \(rule.appIdentifier)") }
        if !rule.titleContains.isEmpty { parts.append("title \(rule.titleOperator.rawValue) \"\(rule.titleContains)\"") }
        if !rule.bodyContains.isEmpty { parts.append("body \(rule.bodyOperator.rawValue) \"\(rule.bodyContains)\"") }
        return parts.isEmpty ? "New Rule (unconfigured)" : parts.joined(separator: " + ")
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
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Unmatched Notifications Tab

struct UnmatchedTab: View {
    @ObservedObject var history: NotificationHistory
    @ObservedObject var ruleStore: RuleStore
    let onRulesChanged: ([FilterRule]) -> Void

    private var unmatchedEntries: [HistoryEntry] {
        history.entries.filter { !$0.matched }.reversed()
    }

    var body: some View {
        if unmatchedEntries.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.green.opacity(0.5))
                Text("All caught up")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No unmatched notifications.\nNotifications that don't match any rule will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(unmatchedEntries) { entry in
                        UnmatchedRow(entry: entry, ruleStore: ruleStore, onRulesChanged: onRulesChanged)
                    }
                }
                .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Unmatched Notification Row

struct UnmatchedRow: View {
    let entry: HistoryEntry
    @ObservedObject var ruleStore: RuleStore
    let onRulesChanged: ([FilterRule]) -> Void

    @State private var showingCreateRule = false

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
                    Text(relativeTime(entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
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
            .popover(isPresented: $showingCreateRule, arrowEdge: .trailing) {
                QuickRuleCreator(entry: entry, ruleStore: ruleStore, onRulesChanged: onRulesChanged) {
                    showingCreateRule = false
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Quick Rule Creator (popover from unmatched notification)

struct QuickRuleCreator: View {
    let entry: HistoryEntry
    @ObservedObject var ruleStore: RuleStore
    let onRulesChanged: ([FilterRule]) -> Void
    let onDismiss: () -> Void

    @State private var useApp = true
    @State private var useTitle = false
    @State private var useBody = false
    @State private var label = ""

    private var allLabels: [String] {
        Set(ruleStore.rules.compactMap { $0.label.isEmpty ? nil : $0.label }).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Rule")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $useApp) {
                    HStack {
                        Text("App:")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 40, alignment: .trailing)
                        Text(entry.appIdentifier)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)

                if !entry.title.isEmpty {
                    Toggle(isOn: $useTitle) {
                        HStack {
                            Text("Title:")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 40, alignment: .trailing)
                            Text(entry.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                if !entry.body.isEmpty {
                    Toggle(isOn: $useBody) {
                        HStack {
                            Text("Body:")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 40, alignment: .trailing)
                            Text(entry.body)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            LabelSuggestingField(text: $label, allLabels: allLabels)

            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Create") { createRule() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!useApp && !useTitle && !useBody)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func createRule() {
        let rule = FilterRule(
            appIdentifier: useApp ? entry.appIdentifier : "",
            titleContains: useTitle ? entry.title : "",
            bodyContains: useBody ? entry.body : "",
            label: label
        )
        ruleStore.rules.append(rule)
        ruleStore.save()
        onRulesChanged(ruleStore.rules)
        onDismiss()
    }
}

// MARK: - Suggesting Field

struct SuggestingField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    @ObservedObject var history: NotificationHistory
    let field: SuggestionField

    @FocusState private var isFocused: Bool
    @State private var showSuggestions = false

    init(_ label: String, text: Binding<String>, placeholder: String, history: NotificationHistory, field: SuggestionField) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.history = history
        self.field = field
    }

    private var suggestions: [Suggestion] {
        history.suggestions(for: field, matching: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
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
                    Spacer().frame(width: 84)
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

// MARK: - General tab chrome (Preferences-style sections)

private struct SettingsSectionCaps: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .tracking(0.55)
            .padding(.leading, 2)
            .padding(.bottom, 6)
    }
}

private struct SettingsInsetGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var appSettings: AppSettings
    var scrollFocus: SettingsGeneralSection
    @State private var showingServiceStatus = false
    @State private var serviceStatusMessage = ""

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
            set: {
                appSettings.alertPresentation = AlertPresentation(
                    layout: appSettings.alertPresentation.layout,
                    screens: $0
                )
            }
        )
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionCaps(title: "Alerts")
                        SettingsInsetGroup {
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
                            }
                        }
                    }
                    .id(SettingsGeneralSection.alerts)

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionCaps(title: "Application")
                        SettingsInsetGroup {
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
                        }
                    }
                    .id(SettingsGeneralSection.application)

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionCaps(title: "Keyboard")
                        SettingsInsetGroup {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Dismiss alerts")
                                        .font(.system(size: 13, weight: .medium))
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
                                        }
                                    }
                                }

                                Divider()
                                    .opacity(0.45)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Open this window")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Global shortcut from any app. Uses the same Accessibility permission as notification detection.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(captionColor)
                                        .fixedSize(horizontal: false, vertical: true)

                                    HStack(spacing: 12) {
                                        KeyCaptureButton(shortcut: $appSettings.openSettingsHotkey)

                                        if appSettings.openSettingsHotkey != nil {
                                            Button("Clear") {
                                                appSettings.openSettingsHotkey = nil
                                                appSettings.save()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .id(SettingsGeneralSection.keyboard)

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionCaps(title: "Login")
                        SettingsInsetGroup {
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
                    }
                    .id(SettingsGeneralSection.login)
                }
                .padding(.horizontal, SettingsChromeLayout.detailContentHorizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, SettingsChromeLayout.detailContentHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: scrollFocus) { _, newSection in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(newSection, anchor: .top)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(scrollFocus, anchor: .top)
                }
            }
        }
        .onChange(of: appSettings.dismissKey) { _, _ in
            appSettings.save()
        }
        .onChange(of: appSettings.openSettingsHotkey) { _, _ in
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

    private var filteredLabels: [String] {
        if text.isEmpty {
            return allLabels
        }
        let q = text.lowercased()
        return allLabels.filter { $0.lowercased().contains(q) && $0 != text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Label:")
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("e.g. work, personal", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
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

            if showSuggestions && !filteredLabels.isEmpty {
                HStack(spacing: 0) {
                    Spacer().frame(width: 84)
                    HStack(spacing: 4) {
                        ForEach(filteredLabels, id: \.self) { label in
                            Button(action: {
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

// MARK: - Helpers

func relativeTime(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
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
