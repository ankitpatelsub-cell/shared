import SwiftUI

struct ReconnectionStatusView: View {
    @ObservedObject var recoveryManager: SessionRecoveryManager

    var body: some View {
        Group {
            switch recoveryManager.recoveryState {
            case .idle:
                EmptyView()

            case .reconnecting(let attempt, let maxAttempts):
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reconnecting...")
                                .font(.caption.weight(.semibold))
                            Text("Attempt \(attempt) of \(maxAttempts)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: { recoveryManager.cancelRecovery() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15))
                    .cornerRadius(8)

                    ProgressView(value: Double(attempt) / Double(maxAttempts))
                        .tint(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .transition(.move(edge: .top).combined(with: .opacity))

            case .failed(let error):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connection Failed")
                                .font(.caption.weight(.semibold))
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: { recoveryManager.cancelRecovery() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.15))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .transition(.move(edge: .top).combined(with: .opacity))

            case .recovered:
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text("Connection Restored")
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Button(action: { recoveryManager.cancelRecovery() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.15))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

#Preview {
    VStack {
        ReconnectionStatusView(
            recoveryManager: {
                let manager = SessionRecoveryManager()
                manager.recoveryState = .reconnecting(attempt: 2, maxAttempts: 5)
                return manager
            }()
        )
        Spacer()
    }
    .padding()
}
