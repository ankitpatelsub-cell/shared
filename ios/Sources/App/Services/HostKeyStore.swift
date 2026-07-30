import Foundation

/// Trust-on-first-use (TOFU) host key store, the same model OpenSSH's
/// `known_hosts` uses: the fingerprint seen on the *first* successful
/// connection to a given host:port is pinned, and every later connection
/// is checked against it. A mismatch means the host key changed — either a
/// legitimate re-key or a MITM — and must surface as a blocking prompt, not
/// a silent pass-through.
///
/// This store only tracks the trust decision. Wiring it into a live
/// connection means bridging it to Citadel's host-key verification
/// extension point in `SSHSessionManager`; verify that surface against the
/// exact Citadel version SwiftPM resolves (`Package.resolved`), since it has
/// shifted across releases.
final class HostKeyStore {
    static let shared = HostKeyStore()

    enum Verdict {
        case trustedNew
        case trustedMatch
        case mismatch(previous: String)
    }

    private let defaults: UserDefaults
    private let prefix = "dev.termvault.hostkey."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(host: String, port: Int) -> String {
        "\(prefix)\(host):\(port)"
    }

    func knownFingerprint(host: String, port: Int) -> String? {
        defaults.string(forKey: key(host: host, port: port))
    }

    /// Call on every connection attempt. Returns whether the fingerprint is
    /// new (needs a one-time "trust this host?" prompt), matches what's
    /// pinned (silently proceed), or mismatches (must block and warn).
    func evaluate(fingerprint: String, host: String, port: Int) -> Verdict {
        guard let known = knownFingerprint(host: host, port: port) else {
            return .trustedNew
        }
        return known == fingerprint ? .trustedMatch : .mismatch(previous: known)
    }

    func trust(fingerprint: String, host: String, port: Int) {
        defaults.set(fingerprint, forKey: key(host: host, port: port))
    }

    func forget(host: String, port: Int) {
        defaults.removeObject(forKey: key(host: host, port: port))
    }
}
