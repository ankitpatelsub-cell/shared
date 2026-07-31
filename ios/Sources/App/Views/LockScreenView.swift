import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var lockService: BiometricLockService

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.08, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 108, height: 108)
                        .blur(radius: 8)
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 84, height: 84)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 6) {
                    Text("TermVault")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Locked — unlock to view your hosts and keys")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await lockService.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.system(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 48)
            }
            .padding(24)
        }
        .task { await lockService.authenticateIfNeeded() }
    }
}
