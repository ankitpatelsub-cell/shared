import Foundation
import LocalAuthentication

/// App-level lock, mirroring Termius' behavior: Face ID / Touch ID (falling
/// back to device passcode) gates the whole UI, independent of any
/// per-connection auth.
@MainActor
final class BiometricLockService: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var isBiometricLockEnabled: Bool {
        didSet { UserDefaults.standard.set(isBiometricLockEnabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "dev.termvault.settings.biometricLockEnabled"

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        self.isBiometricLockEnabled = stored ?? true
    }

    func authenticateIfNeeded() async {
        guard isBiometricLockEnabled else {
            isUnlocked = true
            return
        }
        await authenticate()
    }

    func authenticate() async {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics/passcode configured on this device/simulator —
            // don't lock the user out of an app they have no way to unlock.
            isUnlocked = true
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock TermVault"
            )
            isUnlocked = success
        } catch {
            isUnlocked = false
        }
    }

    func lock() {
        guard isBiometricLockEnabled else { return }
        isUnlocked = false
    }
}
