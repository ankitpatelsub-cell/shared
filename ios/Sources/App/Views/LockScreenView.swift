import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var lockService: BiometricLockService

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("TermVault Locked")
                    .font(.title2.bold())
                Button("Unlock") {
                    Task { await lockService.authenticate() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task { await lockService.authenticateIfNeeded() }
    }
}
