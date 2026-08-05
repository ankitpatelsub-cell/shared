import Foundation

/// Manages automatic session recovery and reconnection logic
@MainActor
final class SessionRecoveryManager: ObservableObject {
    enum RecoveryState {
        case idle
        case reconnecting(attempt: Int, maxAttempts: Int)
        case failed(error: String)
        case recovered
    }

    @Published var recoveryState: RecoveryState = .idle
    @Published var statusMessage: String = ""

    private let maxReconnectAttempts = 5
    private var reconnectTask: Task<Void, Error>?

    private func exponentialBackoffDelay(attempt: Int) -> TimeInterval {
        let maxDelay: TimeInterval = 30.0
        let delay = pow(2.0, Double(attempt - 1))
        return min(delay * 2, maxDelay)
    }

    func startRecovery(reconnectAction: @escaping () async throws -> Void) {
        reconnectTask?.cancel()

        reconnectTask = Task {
            for attempt in 1...maxReconnectAttempts {
                self.recoveryState = .reconnecting(attempt: attempt, maxAttempts: self.maxReconnectAttempts)
                self.statusMessage = "Attempting to reconnect... (\(attempt)/\(self.maxReconnectAttempts))"

                do {
                    try await reconnectAction()
                    self.recoveryState = .recovered
                    self.statusMessage = "Reconnected successfully"
                    return
                } catch {
                    if attempt < self.maxReconnectAttempts {
                        let delay = self.exponentialBackoffDelay(attempt: attempt)
                        self.statusMessage = "Reconnecting in \(Int(delay))s... (\(attempt)/\(self.maxReconnectAttempts))"
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }

            self.recoveryState = .failed(error: "Failed to reconnect after \(self.maxReconnectAttempts) attempts")
            self.statusMessage = "Reconnection failed"
        }
    }

    func cancelRecovery() {
        reconnectTask?.cancel()
        recoveryState = .idle
        statusMessage = ""
    }

    func isRecovering() -> Bool {
        if case .reconnecting = recoveryState {
            return true
        }
        return false
    }
}
