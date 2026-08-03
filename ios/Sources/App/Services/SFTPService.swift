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
/// second connection. Verified against Citadel 0.12.1's actual
/// `SFTPClient`/`SFTPFile` source.
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
        // `listDirectory` returns one `SFTPMessage.Name` per readdir round
        // trip, each batching multiple entries in `.components` — flatten
        // before mapping to our own model.
        let components = try await sftp.listDirectory(atPath: path).flatMap(\.components)
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

    func download(hostID: UUID, sshClient: SSHClient, remotePath: String, to localURL: URL, progressHandler: ((Double) -> Void)? = nil) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        let buffer = try await sftp.withFile(filePath: remotePath, flags: .read) { file in
            try await file.readAll()
        }
        
        // Get total size from the buffer
        let totalSize = Int64(buffer.readableBytes)
        var bytesRead: Int64 = 0
        
        let outputStream = OutputStream(url: localURL, append: false)!
        outputStream.open()
        defer { outputStream.close() }
        
        let bufferSize = 64 * 1024 // 64KB chunks
        var readBuffer = ByteBufferAllocator().buffer(capacity: bufferSize)
        
        // Since we have all data in memory, write in chunks for progress
        var offset = 0
        while offset < buffer.readableBytes {
            let chunkSize = min(bufferSize, buffer.readableBytes - offset)
            let chunk = buffer.getSlice(at: offset, length: chunkSize)!
            offset += chunkSize
            
            let data = chunk.readBytes(length: chunk.readableBytes)!
            data.withUnsafeBytes { rawBuffer in
                _ = outputStream.write(rawBuffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: chunk.readableBytes)
            }
            
            bytesRead += Int64(chunkSize)
            if totalSize > 0 {
                progressHandler?(Double(bytesRead) / Double(totalSize))
            }
        }
        
        try Data(buffer.readableBytesView).write(to: localURL)
    }
    
    func upload(hostID: UUID, sshClient: SSHClient, localURL: URL, remotePath: String, progressHandler: ((Double) -> Void)? = nil) async throws {
        let sftp = try await client(for: hostID, sshClient: sshClient)
        let data = try Data(contentsOf: localURL)
        let totalSize = Int64(data.count)
        var bytesWritten: Int64 = 0
        
        let chunkSize = 64 * 1024
        var offset = 0
        
        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
            while offset < data.count {
                let chunkEnd = min(offset + chunkSize, data.count)
                let chunk = data[offset..<chunkEnd]
                var buffer = ByteBufferAllocator().buffer(capacity: chunk.count)
                buffer.writeBytes(chunk)
                
                try await file.write(buffer)
                
                offset = chunkEnd
                bytesWritten += Int64(chunk.count)
                if totalSize > 0 {
                    progressHandler?(Double(bytesWritten) / Double(totalSize))
                }
            }
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
            try await sftp.rmdir(at: path)
        } else {
            try await sftp.remove(at: path)
        }
    }

    func disconnect(hostID: UUID) {
        clients[hostID] = nil
    }
}
