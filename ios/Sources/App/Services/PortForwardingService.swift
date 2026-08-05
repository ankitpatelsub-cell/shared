import Foundation
import Citadel
import NIOCore

/// Port forwarding stub - Citadel doesn't currently expose port forwarding APIs.
/// This service compiles but doesn't actually create tunnels.
/// Future enhancement: Implement via raw SSH channel operations if Citadel adds support.
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
    /// Currently a stub - Citadel doesn't expose this API
    func startLocalForward(
        connectionID: UUID,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        sshClient: SSHClient
    ) async throws {
        throw PortForwardingError.notSupported
    }

    /// Start a dynamic (SOCKS) port forward: localhost:localPort acts as SOCKS proxy
    /// Currently a stub - Citadel doesn't expose this API
    func startDynamicForward(
        connectionID: UUID,
        localPort: Int,
        sshClient: SSHClient
    ) async throws {
        throw PortForwardingError.notSupported
    }

    /// Start a remote port forward: remoteHost:remotePort -> localhost:localPort
    /// Currently a stub - Citadel doesn't expose this API
    func startRemoteForward(
        connectionID: UUID,
        remoteHost: String,
        remotePort: Int,
        localHost: String,
        localPort: Int,
        sshClient: SSHClient
    ) async throws {
        throw PortForwardingError.notSupported
    }

    /// Stop a specific port forward
    func stopForward(forwardID: UUID) async {
        if let forward = activeForwards.removeValue(forKey: forwardID) {
            forward.task?.cancel()
        }
    }

    /// Stop all port forwards for a connection
    func stopAllForConnection(connectionID: UUID) async {
        // Stub - no actual forwards to stop
    }

    /// Get all active port forwards
    func getActiveForwards() -> [PortForward] {
        Array(activeForwards.values)
    }
}

enum PortForwardingError: Error, LocalizedError {
    case notSupported
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Port forwarding not yet supported by Citadel SSH library"
        case .connectionFailed:
            return "Failed to establish port forward"
        }
    }
}