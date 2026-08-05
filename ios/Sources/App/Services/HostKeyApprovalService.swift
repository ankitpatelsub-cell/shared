import Foundation

/// Manages host key approval decisions
final class HostKeyApprovalService {
    static let shared = HostKeyApprovalService()

    enum ApprovalDecision {
        case trustAlways
        case trustOnce
        case reject
    }

    struct PendingApproval {
        let host: String
        let port: Int
        let fingerprint: String
        let keyType: String
    }

    private let defaults: UserDefaults
    private let sessionTrustedKeysKey = "dev.termvault.sessionTrustedKeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Check if key was already approved in this session
    func isSessionTrusted(host: String, port: Int, fingerprint: String) -> Bool {
        let sessionTrusted = defaults.stringArray(forKey: sessionTrustedKeysKey) ?? []
        let key = "\(host):\(port):\(fingerprint)"
        return sessionTrusted.contains(key)
    }

    /// Mark key as trusted for this session only
    func trustSessionOnly(host: String, port: Int, fingerprint: String) {
        var sessionTrusted = defaults.stringArray(forKey: sessionTrustedKeysKey) ?? []
        let key = "\(host):\(port):\(fingerprint)"
        if !sessionTrusted.contains(key) {
            sessionTrusted.append(key)
            defaults.set(sessionTrusted, forKey: sessionTrustedKeysKey)
        }
    }

    /// Clear session-only trusts (call on app termination)
    func clearSessionTrusts() {
        defaults.removeObject(forKey: sessionTrustedKeysKey)
    }
}
