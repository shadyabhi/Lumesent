import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissionChecker: PermissionChecker
    let onFinish: () -> Void

    @State private var step = 0

    private let pages: [(title: String, detail: String, systemImage: String)] = [
        (
            "Welcome to Lumesent",
            "Lumesent watches your Mac’s notifications and shows a prominent alert when one matches a rule you define. You stay in control of what breaks through the noise.",
            "bell.badge.fill"
        ),
        (
            "Grant permissions",
            "Full Disk Access lets Lumesent read Apple’s notification database. Accessibility lets it react instantly when Notification Center updates. Both are required. Notification permission is optional — it enables native macOS notifications via the CLI.",
            "lock.shield.fill"
        ),
        (
            "Add your first rule",
            "Open Settings from the menu bar icon. Add a rule with an app ID, title, or body pattern. Only notifications that match a rule trigger the big alert.",
            "list.bullet.rectangle.portrait.fill"
        ),
        (
            "What alerts look like",
            "Matching notifications can fill the screen or appear as a top banner—your choice in Settings. Dismiss with a click, the shortcut you configure, or wait for auto-dismiss.",
            "rectangle.inset.filled.and.person.filled"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lumesent")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            TabView(selection: $step) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(index: i)
                        .tag(i)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 280)

            if step == 1 && !permissionChecker.allGranted {
                PermissionMiniBanner(permissionChecker: permissionChecker)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step < pages.count - 1 {
                    Button("Next") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get started") { finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func pageView(index: Int) -> some View {
        let p = pages[index]
        VStack(spacing: 16) {
            Image(systemName: p.systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)
            Text(p.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(p.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finish() {
        OnboardingState.markCompleted()
        onFinish()
    }
}

enum OnboardingState {
    private static let completedKey = "Lumesent.onboarding.v1.completed"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}

private struct PermissionMiniBanner: View {
    @ObservedObject var permissionChecker: PermissionChecker

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Permissions still needed")
                    .font(.system(size: 11, weight: .semibold))
                Text("Use System Settings to grant access, then return here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
