import AppKit
import SwiftUI

struct FullScreenAlertView: View {
    let notification: NotificationRecord
    let isSticky: Bool
    let layout: AlertLayout
    let onDismiss: () -> Void

    @State private var appeared = false

    private var titleSize: CGFloat { layout == .banner ? 22 : 36 }
    private var bodySize: CGFloat { layout == .banner ? 14 : 20 }
    private var verticalPadding: CGFloat { layout == .banner ? 20 : 60 }
    private var maxContentWidth: CGFloat { layout == .banner ? 640 : 700 }

    var body: some View {
        ZStack {
            Color.black.opacity(layout == .banner ? 0.55 : 0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSticky { onDismiss() }
                }

            VStack(spacing: layout == .banner ? 10 : 20) {
                appIconView
                    .frame(width: layout == .banner ? 40 : 56, height: layout == .banner ? 40 : 56)
                    .accessibilityHidden(true)

                Text(notification.appName)
                    .font(layout == .banner ? .subheadline : .headline)
                    .foregroundStyle(.secondary)

                Text(notification.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: bodySize))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(layout == .banner ? 4 : nil)
                }

                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.top, layout == .banner ? 4 : 10)
                    .controlSize(layout == .banner ? .small : .regular)
                    .accessibilityLabel("Dismiss alert")
                    .accessibilityHint("Dismiss this notification alert")
            }
            .padding(verticalPadding)
            .frame(maxWidth: maxContentWidth)
            .scaleEffect(appeared ? 1.0 : (layout == .banner ? 1.0 : 0.9))
            .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: layout == .banner ? 0.2 : 0.3)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var appIconView: some View {
        if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: layout == .banner ? 8 : 12))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var appIcon: NSImage? {
        guard notification.appIdentifier != "external" else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notification.appIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
