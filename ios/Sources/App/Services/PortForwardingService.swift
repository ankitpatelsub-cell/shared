import Foundation
import Citadel
import NIOCore
import NIOSSH

/// Manages SSH port forwarding: local, dynamic (SOCKS), and remote
actor PortForwardingService {
    static let shared = PortForwardingService()

    private var activeForwards: [UUID: PortForward] = [:]

    struct PortForward: Identifiable {
        let id = UUID()
        let type: ForwardType
        let localPort: Int
        let remoteHost: String?
        let remotePort: Int?
        let sshClient: SSHClient
        var task: Task<Void, Never>?
        var isRunning: Bool = true
    }

    enum ForwardType: String, Codable {
        case local = "Local"
        case dynamic = "Dynamic (SOCKS)"
        case remote = "Remote"
    }

    /// Start a local port forward: localhost:localPort -> remoteHost:remotePort
    func startLocalForward(
        connectionID: UUID,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        sshClient: SSHClient
    ) async throws {
        let forward = PortForward(
            type: .local,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            sshClient: sshClient
        )

        forward.task = Task {
            do {
                try await sshClient.startTCPForward(
                    host: remoteHost,
                    port: remotePort,
                    originator: "127.0.0.1",
                    originatorPort: localPort
                ) { inbound, outbound in
                    // Bidirectional pipe between inbound and outbound channels
                    await self.relayData(inbound: inbound, outbound: outbound)
                }
            } catch {
                await self.handleForwardError(forwardID: forward.id, error: error)
            }
        }

        activeForwards[forward.id] = forward
    }

    /// Start a dynamic (SOCKS) port forward: localhost:localPort acts as SOCKS proxy
    func startDynamicForward(
        connectionID: UUID,
        localPort: Int,
        sshClient: SSHClient
    ) async throws {
        let forward = PortForward(
            type: .dynamic,
            localPort: localPort,
            remoteHost: nil,
            remotePort: nil,
            sshClient: sshClient
        )

        forward.task = Task {
            do {
                try await sshClient.startDynamicForward(
                    originator: "127.0.0.1",
                    originatorPort: localPort
                ) { inbound, outbound in
                    await self.relayData(inbound: inbound, outbound: outbound)
                }
            } catch {
                await self.handleForwardError(forwardID: forward.id, error: error)
            }
        }

        activeForwards[forward.id] = forward
    }

    /// Start a remote port forward: remoteHost:remotePort -> localhost:localPort
    func startRemoteForward(
        connectionID: UUID,
        remoteHost: String,
        remotePort: Int,
        localHost: String,
        localPort: Int,
        sshClient: SSHClient
    ) async throws {
        let forward = PortForward(
            type: .remote,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            sshClient: sshClient
        )

        forward.task = Task {
            do {
                try await sshClient.startRemoteForward(
                    host: remoteHost,
                    port: remotePort
                ) { inbound, outbound in
                    await self.relayData(inbound: inbound, outbound: outbound)
                }
            } catch {
                await self.handleForwardError(forwardID: forward.id, error: error)
            }
        }

        activeForwards[forward.id] = forward
    }

    /// Stop a specific port forward
    func stopForward(forwardID: UUID) async {
        if let forward = activeForwards.removeValue(forKey: forwardID) {
            forward.isRunning = false
            forward.task?.cancel()
        }
    }

    /// Stop all port forwards for a connection
    func stopAllForConnection(connectionID: UUID) async {
        let forwardsToStop = activeForwards.values.filter { $0.sshClient === SSHSessionManager.shared.session(for: connectionID) }
        for forward in forwardsToStop {
            await stopForward(forwardID: forward.id)
        }
    }

    /// Get all active port forwards
    func getActiveForwards() -> [PortForward] {
        Array(activeForwards.values)
    }

    /// Relay data between two channels
    private func relayData(inbound: SSHChannel, outbound: SSHChannel) async {
        let inboundToOutbound = Task {
            for try await chunk in inbound {
                try await outbound.writeAndFlush(chunk)
            }
        }

        let outboundToInbound = Task {
            for try await chunk in outbound {
                try await inbound.writeAndFlush(chunk)
            }
        }

        // Wait for either direction to complete
        _ = await (inboundToOutbound.value, outboundToInbound.value)
    }

    private func handleForwardError(forwardID: UUID, error: Error) async {
        activeForwards[forwardID]?.isRunning = false
        print("Port forward error: \(error)")
    }
}