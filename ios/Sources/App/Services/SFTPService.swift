import Foundation
import Citadel
import NIOCore

struct SFTPEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let permissions: String
    let modifiedAt: Date?
}

enum SFTPError: Error, LocalizedError {
    case notConnected
    case transferCancelled

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to this host's SFTP subsystem."
        case .transferCancelled: return "Transfer cancelled."
        }
    }
}

/// Wraps Citadel's SFTP subsystem for the file browser. One client per
/// host, reusing the same `SSHClient` connection `SSHSessionManager` already
/// holds open — SFTP rides the existing SSH session rather than opening a
/// second connection.
///
/// As with `SSHSessionManager`, the exact Citadel SFTP API surface
/// (`openSFTP()`, listing/read/write method names) has moved across
/// releases; confirm the calls below against `Package.resolved` before
/// relying on them.
actor SFTPService {
    static let shared = SFTPService()

    private var clients: [UUID: SFTPClient] = [:]

    func client(for hostID: UUID, sshClient: SSHClient) async throws -> SFTPClient {
        if let existing = clients[hostID] {
            return existing
        }
        let sftp = try await sshClient.openSFTP()
        clients[hostID] = sftp
        return sftp
    }

    func listDirectory(hostID: UUID, sshClient: SSHClient, path: String) async throws -> [SFTPEntry] {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        let contents = try await sftp.listDirectory(atPath: path)
        return contents
            .filter { $0.filename != "." && $0.filename != ".." }
            .map { component in
                SFTPEntry(
                    name: component.filename,
                    path: (path as NSString).appendingPathComponent(component.filename),
                    isDirectory: component.attributes.isDirectory,
                    size: Int64(component.attributes.size ?? 0),
                    permissions: component.attributes.permissionsDescription ?? "—",
                    modifiedAt: component.attributes.modificationDate
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func download(hostID: UUID, sshClient: SSHClient, remotePath: String, to localURL: URL) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        let data = try await sftp.withFile(filePath: remotePath, flags: .read) { file in
            try await file.readAll()
        }
        try data.write(to: localURL)
    }

    func upload(hostID: UUID, sshClient: SSHClient, localURL: URL, remotePath: String) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        let data = try Data(contentsOf: localURL)
        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
            try await file.write(ByteBuffer(data: data))
        }
    }

    func createDirectory(hostID: UUID, sshClient: SSHClient, path: String) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        try await sftp.createDirectory(atPath: path)
    }

    func rename(hostID: UUID, sshClient: SSHClient, from: String, to: String) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        try await sftp.rename(at: from, to: to)
    }

    func delete(hostID: UUID, sshClient: SSHClient, path: String, isDirectory: Bool) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        if isDirectory {
            try await sftp.rmdir(atPath: path)
        } else {
            try await sftp.remove(atPath: path)
        }
    }

    func disconnect(hostID: UUID) {
        clients[hostID] = nil
    }
}
