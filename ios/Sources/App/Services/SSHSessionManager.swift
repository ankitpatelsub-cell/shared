import Foundation
import Citadel
import NIOCore
import NIOSSH

enum SSHConnectionError: Error, LocalizedError {
    case noAuthenticationConfigured
    case rsaPrivateKeyAuthUnsupported
    case notConnected
    case terminalSetupTimedOut

    var errorDescription: String? {
        switch self {
        case .noAuthenticationConfigured:
            return "This host has no password or SSH key configured."
        case .rsaPrivateKeyAuthUnsupported:
            return "RSA key auth isn't supported: Citadel's Insecure.RSA.PrivateKey has no PEM/DER import initializer in its public API (only a raw-BoringSSL-BIGNUM constructor and an internal generator). Use an Ed25519 identity instead — Citadel supports that fully via .ed25519(username:privateKey:)."
        case .notConnected:
            return "Not connected."
        case .terminalSetupTimedOut:
            return "Terminal setup timed out. Tap reconnect to try again."
        }
    }
}

/// Represents a hop in a multi-hop SSH connection chain
struct SSHJumpHop {
    let host: Host
    let identity: Identity?
}

/// Owns every live SSH connection, keyed by host ID, so switching between
/// terminal tabs never reconnects — mirrors Termius' tab-switching model.
///
/// Built on Citadel's real client API (verified against the actual
/// `orlandos-nl/Citadel` source, tag 0.12.1): connect via `SSHClientSettings`
/// + `SSHClient.connect(to:)`, and get an interactive shell via
/// `client.withPTY(_:perform:)`, whose `perform` closure only returns once
/// the session ends — so `connect()` runs it inside a long-lived `Task` and
/// stashes the `TTYStdinWriter` it hands back for later `send(_:hostID:)` calls.
actor SSHSessionManager {
    static let shared = SSHSessionManager()

    private var clients: [UUID: SSHClient] = [:]
    private var jumpClients: [UUID: [SSHClient]] = [:] // Support multiple jump hops
    private var hostIDs: [UUID: UUID] = [:]
    private var writers: [UUID: TTYStdinWriter] = [:]
    // SwiftTerm commonly reports its real viewport before `withPTY` has
    // finished creating the remote writer. Retain that early resize so the
    // shell (and an attached tmux client) never stays at the 80x24 fallback.
    private var pendingTerminalSizes: [UUID: (cols: Int, rows: Int)] = [:]
    private var sessionTasks: [UUID: Task<Void, Never>] = [:]

    func isConnected(connectionID: UUID) -> Bool {
        clients[connectionID] != nil
    }

    func session(for connectionID: UUID) -> SSHClient? {
        clients[connectionID]
    }

    func session(forHostID hostID: UUID) -> SSHClient? {
        guard let connectionID = hostIDs.first(where: { $0.value == hostID })?.key else { return nil }
        return clients[connectionID]
    }

    func connect(
        connectionID: UUID,
        host: Host,
        identity: Identity?,
        jumpHosts: [SSHJumpHop] = [], // Support multiple jump hosts
        onOutput: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable () -> Void
    ) async throws {
        if clients[connectionID] != nil { return }

        let authMethod = try makeAuthenticationMethod(host: host, identity: identity)
        let settings = SSHClientSettings(
            host: host.address,
            port: host.port,
            authenticationMethod: { authMethod },
            hostKeyValidator: .custom(TOFUHostKeyValidator(host: host.address, port: host.port))
        )

        var finalClient: SSHClient
        var jumpClientChain: [SSHClient] = []

        if !jumpHosts.isEmpty {
            // Build chain of jump hosts
            var currentClient: SSHClient?
            
            for (_, hop) in jumpHosts.enumerated() {
                let hopAuthMethod = try makeAuthenticationMethod(host: hop.host, identity: hop.identity)
                let hopSettings = SSHClientSettings(
                    host: hop.host.address,
                    port: hop.host.port,
                    authenticationMethod: { hopAuthMethod },
                    hostKeyValidator: .custom(TOFUHostKeyValidator(host: hop.host.address, port: hop.host.port))
                )
                
                let hopClient: SSHClient
                if let previousClient = currentClient {
                    hopClient = try await previousClient.jump(to: hopSettings)
                } else {
                    hopClient = try await SSHClient.connect(to: hopSettings)
                }
                
                jumpClientChain.append(hopClient)
                currentClient = hopClient
            }
            
            // Connect to final target through the last jump host
            finalClient = try await currentClient!.jump(to: settings)
        } else {
            finalClient = try await SSHClient.connect(to: settings)
        }

        clients[connectionID] = finalClient
        if !jumpClientChain.isEmpty {
            jumpClients[connectionID] = jumpClientChain
        }
        hostIDs[connectionID] = host.id

        sessionTasks[connectionID] = Task {
            do {
                try await finalClient.withPTY(
                    SSHChannelRequestEvent.PseudoTerminalRequest(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: 80,
                        terminalRowHeight: 24,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: SSHTerminalModes([:])
                    )
                ) { inbound, outbound in
                    await self.storeWriter(outbound, forConnectionID: connectionID)
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buffer), .stderr(let buffer):
                            onOutput(Data(buffer.readableBytesView))
                        }
                    }
                }
            } catch {
                // Falls through to teardown below regardless of whether the
                // session ended cleanly (remote closed) or with an error.
            }
            await self.disconnect(connectionID: connectionID)
            onClose()
        }

        // A TCP/SSH connection is not yet an interactive terminal. Do not
        // return (and let the UI advertise "Connected") until withPTY has
        // supplied the writer that can actually accept keystrokes.
        let setupDeadline = Date().addingTimeInterval(15)
        while writers[connectionID] == nil, clients[connectionID] != nil, Date() < setupDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        if writers[connectionID] == nil, clients[connectionID] != nil {
            await disconnect(connectionID: connectionID)
            throw SSHConnectionError.terminalSetupTimedOut
        }
        guard writers[connectionID] != nil else { throw SSHConnectionError.notConnected }
    }

    private func storeWriter(_ writer: TTYStdinWriter, forConnectionID connectionID: UUID) async {
        writers[connectionID] = writer
        if let size = pendingTerminalSizes[connectionID] {
            try? await writer.changeSize(
                cols: size.cols,
                rows: size.rows,
                pixelWidth: 0,
                pixelHeight: 0
            )
        }
    }

    func send(_ text: String, connectionID: UUID) async throws {
        try await send(Array(text.utf8), connectionID: connectionID)
    }

    func send(_ bytes: [UInt8], connectionID: UUID) async throws {
        guard let writer = writers[connectionID] else { throw SSHConnectionError.notConnected }
        try await writer.write(ByteBuffer(bytes: bytes))
    }

    func resize(connectionID: UUID, cols: Int, rows: Int) async throws {
        guard cols > 0, rows > 0 else { return }
        pendingTerminalSizes[connectionID] = (cols, rows)
        // A layout pass can arrive before the PTY writer. `storeWriter` will
        // apply the retained dimensions as soon as the shell is ready.
        guard let writer = writers[connectionID] else { return }
        try await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }

    func disconnect(connectionID: UUID) async {
        sessionTasks[connectionID]?.cancel()
        sessionTasks[connectionID] = nil
        writers[connectionID] = nil
        pendingTerminalSizes[connectionID] = nil
        hostIDs[connectionID] = nil
        if let client = clients[connectionID] {
            clients[connectionID] = nil
            try? await client.close()
        }
        // Close all jump clients in reverse order
        if let jumpChain = jumpClients.removeValue(forKey: connectionID) {
            for jumpClient in jumpChain.reversed() {
                try? await jumpClient.close()
            }
        }
    }

    func disconnectAll() async {
        for id in Array(clients.keys) {
            await disconnect(connectionID: id)
        }
    }

    private func makeAuthenticationMethod(host: Host, identity: Identity?) throws -> SSHAuthenticationMethod {
        switch host.authMethod {
        case .password:
            let password = try KeychainService.password(for: host)
            return .passwordBased(username: host.username, password: password)
        case .privateKey:
            guard let identity else { throw SSHConnectionError.noAuthenticationConfigured }
            switch identity.keyType {
            case .ed25519:
                let pem = try KeychainService.privateKeyPEM(for: identity)
                let privateKey = try IdentityKeyGenerator.parseEd25519PrivateKey(pem: pem)
                return .ed25519(username: host.username, privateKey: privateKey)
            case .rsa4096:
                throw SSHConnectionError.rsaPrivateKeyAuthUnsupported
            }
        case .none:
            throw SSHConnectionError.noAuthenticationConfigured
        }
    }
}
