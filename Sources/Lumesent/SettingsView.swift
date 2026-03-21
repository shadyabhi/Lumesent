import SwiftUI

// MARK: - Settings View (Tabbed)

struct SettingsView: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var history: NotificationHistory
    @ObservedObject var permissionChecker: PermissionChecker
    let onRulesChanged: ([FilterRule]) -> Void

    @State private var selectedTab: SettingsTab = .rules
    @State private var showingSettings = false

    enum SettingsTab: Hashable {
        case rules
        case unmatched
    }

    init(ruleStore: RuleStore, appSettings: AppSettings, history: NotificationHistory, permissionChecker: PermissionChecker, onRulesChanged: @escaping ([FilterRule]) -> Void) {
        self.ruleStore = ruleStore
        self.appSettings = appSettings
        self.history = history
        self.permissionChecker = permissionChecker
        self.onRulesChanged = onRulesChanged
    }

    var body: some View {
        VStack(spacing: 0) {
            // Permission banner when broken — unmissable, right at the top
            if !permissionChecker.allGranted {
                PermissionBanner(permissionChecker: permissionChecker)
            }

            // Tab bar
            HStack(spacing: 0) {
                TabButton(title: "Rules", systemImage: "list.bullet.rectangle.portrait", isSelected: selectedTab == .rules) {
                    selectedTab = .rules
                }
                TabButton(title: "Unmatched", systemImage: "bell.slash", isSelected: selectedTab == .unmatched) {
                    selectedTab = .unmatched
                }
                Spacer()

                if permissionChecker.allGranted {
                    PermissionOKIndicator(permissionChecker: permissionChecker)
                }

                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Divider()

            // Content
            switch selectedTab {
            case .rules:
                RulesTab(ruleStore: ruleStore, history: history, onRulesChanged: onRulesChanged)
            case .unmatched:
                UnmatchedTab(history: history, ruleStore: ruleStore, onRulesChanged: onRulesChanged)
            }
        }
        .frame(minWidth: 580, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingSettings) {
            GeneralTab(appSettings: appSettings)
                .frame(width: 400, height: 250)
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
                        description: "Required to read the notification database.",
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        }
                    )
                }

                if !permissionChecker.hasAccessibility {
                    PermissionRow(
                        title: "Accessibility",
                        description: "Required for real-time notification detection.",
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    )
                }
            }

            Text("Grant permissions in System Settings, then return here. This banner disappears automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
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

struct PermissionRow: View {
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rules Tab

struct RulesTab: View {
    @ObservedObject var ruleStore: RuleStore
    @ObservedObject var history: NotificationHistory
    let onRulesChanged: ([FilterRule]) -> Void

    @State private var editingRule: FilterRule?
    @State private var selectedLabel: String? = nil

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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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
                                    }
                                )
                            }
                        }
                    }
                    .padding(12)
                }
            }
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
                                Text(op.displayName).tag(op)
                            }
                        }
                        .frame(width: 90)
                    }
                    HStack(spacing: 4) {
                        SuggestingField("Body:", text: $rule.bodyContains, placeholder: "e.g. deploy failed", history: history, field: .body)
                        Picker("", selection: $rule.bodyOperator) {
                            ForEach(MatchOperator.allCases, id: \.self) { op in
                                Text(op.displayName).tag(op)
                            }
                        }
                        .frame(width: 90)
                    }

                    LabelSuggestingField(text: $rule.label, allLabels: allLabels)

                    DisplayModePicker(displayMode: $rule.displayMode)

                    HStack {
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
        if !rule.titleContains.isEmpty { parts.append("title \(rule.titleOperator.displayName) \"\(rule.titleContains)\"") }
        if !rule.bodyContains.isEmpty { parts.append("body \(rule.bodyOperator.displayName) \"\(rule.bodyContains)\"") }
        return parts.isEmpty ? "New Rule (unconfigured)" : parts.joined(separator: " + ")
    }
}

// MARK: - Matched Notification Row

struct MatchedNotificationRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            appIcon
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

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.appIdentifier),
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
                .padding(12)
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
            appIcon
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

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.appIdentifier),
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
            appIcon
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

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.appIdentifier),
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

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Dismiss Shortcut")
                    .font(.system(size: 14, weight: .semibold))

                Text("Alerts can always be dismissed by clicking. Optionally set a keyboard shortcut to dismiss alerts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: appSettings.dismissKey) { _, _ in
            appSettings.save()
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
        displayMode.isSicky
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

    @State private var editingTimeout: String = ""

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
