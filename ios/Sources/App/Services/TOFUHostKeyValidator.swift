import Foundation
import Citadel
import NIOCore
import NIOSSH

/// Trust-on-first-use host key validation, wired into Citadel through
/// `SSHHostKeyValidator.custom(_:)`. Pins the fingerprint of the first key
/// seen for a given host:port (mirroring OpenSSH's `known_hosts`) and hard
/// -fails any later connection whose key doesn't match. This is the real
/// replacement for `.acceptAnything()` that spec section 6 says must never
/// ship — verified against Citadel's actual `NIOSSHClientServerAuthenticationDelegate`
/// hook and `String(openSSHPublicKey:)` (both confirmed present in the
/// `Wellz26/swift-nio-ssh` fork Citadel depends on).
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int
    private let store: HostKeyStore

    init(host: String, port: Int, store: HostKeyStore = .shared) {
        self.host = host
        self.port = port
        self.store = store
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let openSSHLine = String(openSSHPublicKey: hostKey)
        let parts = openSSHLine.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            validationCompletePromise.fail(InvalidHostKey())
            return
        }

        let fingerprint = SSHKeyFormat.fingerprint(publicKeyBlob: Array(blob))

        switch store.evaluate(fingerprint: fingerprint, host: host, port: port) {
        case .trustedNew:
            store.trust(fingerprint: fingerprint, host: host, port: port)
            validationCompletePromise.succeed(())
        case .trustedMatch:
            validationCompletePromise.succeed(())
        case .mismatch:
            // The host key changed since our last connection — exactly the
            // scenario TOFU exists to catch. Refuse rather than silently
            // reconnect. A real UI would surface this distinctly from a
            // plain connection failure (e.g. a blocking warning sheet); for
            // now it surfaces as a connection error via `InvalidHostKey`.
            validationCompletePromise.fail(InvalidHostKey())
        }
    }
}
