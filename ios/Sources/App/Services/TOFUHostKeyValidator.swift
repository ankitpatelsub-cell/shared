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
/// Citadel's own `InvalidHostKey` (`ClientSession.swift`) is a `public
/// struct` with no explicit `public init()`, so its compiler-synthesized
/// initializer is `internal`-only and can't be constructed from outside
/// the Citadel module — confirmed the hard way, via a real "inaccessible
/// due to 'internal' protection level" build error. This is our own
/// stand-in; any `Error` works for `EventLoopPromise<Void>.fail(_:)`.
struct TOFUHostKeyRejection: Error, LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int
    private let store: HostKeyStore
    private let autoApproveSettings: AutoApproveSettings

    init(host: String, port: Int, store: HostKeyStore = .shared, autoApproveSettings: AutoApproveSettings = .shared) {
        self.host = host
        self.port = port
        self.store = store
        self.autoApproveSettings = autoApproveSettings
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let openSSHLine = String(openSSHPublicKey: hostKey)
        let parts = openSSHLine.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            validationCompletePromise.fail(TOFUHostKeyRejection(reason: "Could not parse the host key presented by \(host):\(port)."))
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
            // now it surfaces as a connection error with a clear message.
            validationCompletePromise.fail(TOFUHostKeyRejection(
                reason: "Host key for \(host):\(port) changed since the last connection — refusing to connect. This could mean the server was re-keyed, or someone is intercepting the connection."
            ))
        }
    }
}
