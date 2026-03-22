import AppKit
import SwiftUI

struct AlertGridView: View {
    @ObservedObject var model: AlertGridModel
    let layout: AlertLayout
    let onDismissCard: (UUID) -> Void
    let onDismissAll: () -> Void

    private var cardWidth: CGFloat { layout == .banner ? 340 : 400 }
    private var cardHeight: CGFloat { layout == .banner ? 200 : 280 }
    private var maxColumns: Int { layout == .banner ? 2 : 3 }

    var body: some View {
        ZStack {
            Color.black.opacity(backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    let hasSticky = model.cards.contains { $0.displayMode.isSticky }
                    if !hasSticky { onDismissAll() }
                }

            let columns = max(1, min(model.cards.count, maxColumns))
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: 16), count: columns),
                spacing: 16
            ) {
                ForEach(model.cards) { card in
                    AlertCardView(
                        card: card,
                        layout: layout,
                        onDismiss: { onDismissCard(card.id) }
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.cards.map(\.id))
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: layout == .banner ? .top : .center)
            .padding(.top, layout == .banner ? 40 : 0)
        }
    }

    private var backgroundOpacity: Double {
        if model.cards.isEmpty { return 0 }
        if layout == .banner { return 0.3 }
        return min(0.85, 0.4 + Double(model.cards.count) * 0.15)
    }
}

struct AlertCardView: View {
    let card: AlertGridModel.CardItem
    let layout: AlertLayout
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    private var titleSize: CGFloat { layout == .banner ? 18 : 24 }
    private var bodySize: CGFloat { layout == .banner ? 13 : 16 }
    private var iconSize: CGFloat { layout == .banner ? 32 : 44 }

    var body: some View {
        VStack(spacing: layout == .banner ? 8 : 14) {
            appIconView
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)

            Text(card.notification.appName)
                .font(layout == .banner ? .caption : .subheadline)
                .foregroundStyle(.secondary)

            Text(card.notification.title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !card.notification.body.isEmpty {
                Text(card.notification.body)
                    .font(.system(size: bodySize))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Button("Dismiss") { onDismiss() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.small)
                .padding(.top, 2)
                .accessibilityLabel("Dismiss alert")
                .accessibilityHint("Dismiss this notification alert")

            Text(elapsedTimeString)
                .font(.system(size: layout == .banner ? 11 : 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 2)
        }
        .padding(layout == .banner ? 16 : 24)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.4))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .scaleEffect(appeared ? 1.0 : 0.85)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var elapsedTimeString: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private var appIcon: NSImage? {
        guard card.notification.appIdentifier != "external" else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: card.notification.appIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
