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
    case couldNotOpenLocalFile(URL)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to this host's SFTP subsystem."
        case .transferCancelled: return "Transfer cancelled."
        case .couldNotOpenLocalFile(let url): return "Couldn't open \(url.lastPathComponent) for writing on this device."
        case .timedOut: return "The SFTP server stopped responding. The connection may have dropped — try again."
        }
    }
}

/// Wraps Citadel's SFTP subsystem for the file browser. One client per
/// host, reusing the same `SSHClient` connection `SSHSessionManager` already
/// holds open — SFTP rides the existing SSH session rather than opening a
/// second connection. Verified against Citadel 0.12.1's actual
/// `SFTPClient`/`SFTPFile` source.
actor SFTPService {
    static let shared = SFTPService()

    private var clients: [UUID: SFTPClient] = [:]

    /// How long a single SFTP round trip may take before we give up and
    /// surface an error instead of leaving the UI spinning forever.
    /// Generous — mobile networks and busy servers are slow, not just
    /// dead — but finite, unlike the old code's unlimited wait.
    private static let requestTimeout: TimeInterval = 20

    /// Races `operation` against a timeout. Needed because a half-dead SSH
    /// channel — the socket died silently (network change, backgrounding,
    /// sleep/wake) before NIO noticed — leaves `channel.isActive` `true`
    /// and any request awaiting a response hangs forever with no error,
    /// which is exactly what made SFTP look "stuck" instead of failing.
    // `static` (not actor-isolated) purely so it doesn't need to hop back
    // onto the actor to run — it only ever wraps calls on `SFTPClient`
    // (which Citadel marks `Sendable`), never on `SFTPFile` (which Citadel
    // deliberately does *not* mark `Sendable` — it has an unsynchronized
    // mutable `isActive` flag), so it's not used around the per-chunk
    // read/write calls in `download`/`upload` below.
    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval = SFTPService.requestTimeout,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SFTPError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw SFTPError.timedOut }
            return result
        }
    }

    func client(for hostID: UUID, sshClient: SSHClient) async throws -> SFTPClient {
        // A cached client whose channel already closed (cleanly, at least)
        // would otherwise be handed back and every request on it would
        // fail — or on a still-`isActive`-but-actually-dead channel, hang.
        // Reusing it at all was the bug: after any reconnect, every SFTP
        // open on that host silently kept using the dead one.
        if let existing = clients[hostID], existing.isActive {
            return existing
        }
        clients[hostID] = nil
        let sftp = try await withTimeout { try await sshClient.openSFTP() }
        clients[hostID] = sftp
        return sftp
    }

    func listDirectory(hostID: UUID, sshClient: SSHClient, path: String) async throws -> [SFTPEntry] {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        // `listDirectory` returns one `SFTPMessage.Name` per readdir round
        // trip, each batching multiple entries in `.components` — flatten
        // before mapping to our own model.
        let components = try await withTimeout { try await sftp.listDirectory(atPath: path).flatMap(\.components) }
        return components
            .filter { $0.filename != "." && $0.filename != ".." }
            .map { component in
                let mode = component.attributes.permissions ?? 0
                return SFTPEntry(
                    name: component.filename,
                    path: (path as NSString).appendingPathComponent(component.filename),
                    isDirectory: Self.isDirectory(posixMode: mode),
                    size: Int64(component.attributes.size ?? 0),
                    permissions: Self.permissionsString(posixMode: mode),
                    modifiedAt: component.attributes.accessModificationTime?.modificationTime
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func isDirectory(posixMode: UInt32) -> Bool {
        (posixMode & 0o170000) == 0o040000
    }

    private static func permissionsString(posixMode: UInt32) -> String {
        guard posixMode != 0 else { return "—" }
        let bits = posixMode & 0o777
        var result = ""
        for shift in stride(from: 6, through: 0, by: -3) {
            let triplet = (bits >> shift) & 0o7
            result += (triplet & 0b100) != 0 ? "r" : "-"
            result += (triplet & 0b010) != 0 ? "w" : "-"
            result += (triplet & 0b001) != 0 ? "x" : "-"
        }
        return result
    }

    /// Downloads by reading the file in bounded chunks over the SFTP
    /// protocol (`file.read(from:length:)`), instead of the old
    /// `file.readAll()` — which issues a *single* SFTP request for the
    /// entire file and only returns once every byte has arrived. That made
    /// `progressHandler` a lie: it sat at 0% for the whole transfer, then
    /// jumped to 100% once the network read (already complete) got
    /// re-chunked purely for the local write — so any transfer slower than
    /// instant looked identical to a hang. Reading in real chunks makes
    /// progress move as data actually arrives instead of sitting at 0%.
    func download(hostID: UUID, sshClient: SSHClient, remotePath: String, to localURL: URL, progressHandler: ((Double) -> Void)? = nil) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)

        // `OutputStream(url:append:)` is a failable initializer — it can
        // return nil under real, user-reachable conditions (parent
        // directory missing, container read-only, storage pressure, a
        // security-scoped URL whose access briefly lapsed), so force-
        // unwrapping it crashed the whole app on a download instead of
        // surfacing a normal "couldn't save file" error.
        guard let outputStream = OutputStream(url: localURL, append: false) else {
            throw SFTPError.couldNotOpenLocalFile(localURL)
        }
        outputStream.open()
        defer { outputStream.close() }

        let chunkSize: UInt32 = 256 * 1024

        try await sftp.withFile(filePath: remotePath, flags: .read) { file in
            let totalSize = Int64(try await file.readAttributes().size ?? 0)
            var offset: UInt64 = 0
            var bytesRead: Int64 = 0

            while true {
                var chunk = try await file.read(from: offset, length: chunkSize)
                let readableBytes = chunk.readableBytes
                guard readableBytes > 0 else { break }

                offset += UInt64(readableBytes)
                bytesRead += Int64(readableBytes)

                let bytes = chunk.readBytes(length: readableBytes) ?? []
                bytes.withUnsafeBytes { rawBuffer in
                    _ = outputStream.write(rawBuffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: bytes.count)
                }

                if totalSize > 0 {
                    progressHandler?(Double(bytesRead) / Double(totalSize))
                }

                if readableBytes < Int(chunkSize) { break } // short read == EOF
            }
        }
    }

    func upload(hostID: UUID, sshClient: SSHClient, localURL: URL, remotePath: String, progressHandler: ((Double) -> Void)? = nil) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        let data = try Data(contentsOf: localURL)
        let totalSize = Int64(data.count)
        var bytesWritten: Int64 = 0

        let chunkSize = 64 * 1024

        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
            var localOffset = 0
            while localOffset < data.count {
                let chunkEnd = min(localOffset + chunkSize, data.count)
                let chunk = data[localOffset..<chunkEnd]
                var buffer = ByteBufferAllocator().buffer(capacity: chunk.count)
                buffer.writeBytes(chunk)

                try await file.write(buffer)

                localOffset = chunkEnd
                bytesWritten += Int64(chunk.count)
                if totalSize > 0 {
                    progressHandler?(Double(bytesWritten) / Double(totalSize))
                }
            }
        }
    }

    func createDirectory(hostID: UUID, sshClient: SSHClient, path: String) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        try await Self.withTimeout { try await sftp.createDirectory(atPath: path) }
    }

    func rename(hostID: UUID, sshClient: SSHClient, from: String, to: String) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        try await Self.withTimeout { try await sftp.rename(at: from, to: to) }
    }

    func delete(hostID: UUID, sshClient: SSHClient, path: String, isDirectory: Bool) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        try await Self.withTimeout {
            if isDirectory {
                try await sftp.rmdir(at: path)
            } else {
                try await sftp.remove(at: path)
            }
        }
    }

    func disconnect(hostID: UUID) {
        clients[hostID] = nil
    }
}
