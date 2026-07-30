import Foundation
import Citadel
import NIOCore

enum SSHConnectionError: Error, LocalizedError {
    case noAuthenticationConfigured
    case privateKeyAuthNotYetWired
    case notConnected

    var errorDescription: String? {
        switch self {
        case .noAuthenticationConfigured:
            return "This host has no password or SSH key configured."
        case .privateKeyAuthNotYetWired:
            return "SSH key authentication needs Citadel's private-key parsing wired in for your resolved package version — see SSHSessionManager.makeAuthenticationMethod."
        case .notConnected:
            return "Not connected."
        }
    }
}

/// Owns every live SSH connection, keyed by host ID, so switching between
/// terminal tabs never reconnects — mirrors Termius' tab-switching model.
/// One actor, one source of truth for "what's currently connected."
actor SSHSessionManager {
    static let shared = SSHSessionManager()

    private var clients: [UUID: SSHClient] = [:]
    /// The live shell handle returned by `client.requestShell()`. Typed as
    /// `Any` deliberately: Citadel's exact return type for `requestShell()`
    /// has moved across releases, and this scaffold is written without a
    /// macOS/SwiftPM toolchain available to pin it down. Cast at the call
    /// site in `send(_:hostID:)` once you've confirmed the type against
    /// `Package.resolved`.
    private var shells: [UUID: Any] = [:]
    private var readers: [UUID: Task<Void, Never>] = [:]

    func isConnected(hostID: UUID) -> Bool {
        clients[hostID] != nil
    }

    func session(for hostID: UUID) -> SSHClient? {
        clients[hostID]
    }

    @discardableResult
    func connect(
        host: Host,
        identity: Identity?,
        onOutput: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable () -> Void
    ) async throws -> SSHClient {
        if let existing = clients[host.id] {
            return existing
        }

        let authMethod = try makeAuthenticationMethod(host: host, identity: identity)

        // `.acceptAnything()` is a placeholder — spec section 6 is explicit
        // this must never ship. Before release, replace it with a
        // validator that fingerprints the presented host key and runs it
        // through `HostKeyStore.evaluate(fingerprint:host:port:)`,
        // prompting the user on `.trustedNew` / `.mismatch` and only
        // proceeding silently on `.trustedMatch`.
        let client = try await SSHClient.connect(
            host: host.address,
            port: host.port,
            authenticationMethod: authMethod,
            hostKeyValidator: .acceptAnything()
        )

        clients[host.id] = client

        let shell = try await client.requestShell()
        shells[host.id] = shell

        let reader = Task { [weak self] in
            do {
                for try await chunk in shell.stdout {
                    onOutput(Data(chunk.readableBytesView))
                }
            } catch {
                // Stream ended (error or EOF) — fall through to teardown.
            }
            await self?.disconnect(hostID: host.id)
            onClose()
        }
        readers[host.id] = reader

        return client
    }

    /// Writes keystrokes from the terminal view into the remote shell's
    /// stdin. See the `shells` doc comment above re: confirming the real
    /// write method name/signature for your resolved Citadel version.
    func send(_ text: String, hostID: UUID) async throws {
        guard let shell = shells[hostID] as? SSHShellWriting else {
            throw SSHConnectionError.notConnected
        }
        var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        try await shell.write(buffer)
    }

    func resize(hostID: UUID, cols: Int, rows: Int) async throws {
        guard clients[hostID] != nil else { throw SSHConnectionError.notConnected }
        // TODO: forward a window-change request once wired against the
        // resolved Citadel API (e.g. `client.updatePTYSize(...)`).
    }

    func disconnect(hostID: UUID) async {
        readers[hostID]?.cancel()
        readers[hostID] = nil
        shells[hostID] = nil
        clients[hostID] = nil
    }

    func disconnectAll() async {
        for id in Array(clients.keys) {
            await disconnect(hostID: id)
        }
    }

    private func makeAuthenticationMethod(host: Host, identity: Identity?) throws -> SSHAuthenticationMethod {
        switch host.authMethod {
        case .password:
            let password = try KeychainService.password(for: host)
            return .password(username: host.username, password: password)
        case .privateKey:
            // Parsing the Keychain-stored PEM into the NIOSSHPrivateKey
            // variant Citadel's `.privateKey` case expects is
            // version-specific (RSA vs Ed25519 use different swift-crypto
            // wrapper types). Wire this up once against the exact Citadel
            // release resolved in Package.resolved, then remove this throw.
            throw SSHConnectionError.privateKeyAuthNotYetWired
        case .none:
            throw SSHConnectionError.noAuthenticationConfigured
        }
    }
}

/// Minimal protocol capturing the one method `send(_:hostID:)` needs from
/// whatever concrete shell-handle type Citadel returns. Conform the real
/// type (or wrap it) once confirmed — see the `shells` doc comment above.
protocol SSHShellWriting {
    func write(_ buffer: ByteBuffer) async throws
}
