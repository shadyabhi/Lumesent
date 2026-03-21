import SwiftUI

struct FullScreenAlertView: View {
    let notification: NotificationRecord
    let isSticky: Bool
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSticky { onDismiss() }
                }

            VStack(spacing: 20) {
                Text(notification.appName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(notification.title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.top, 10)
            }
            .padding(60)
            .frame(maxWidth: 700)
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }
}
