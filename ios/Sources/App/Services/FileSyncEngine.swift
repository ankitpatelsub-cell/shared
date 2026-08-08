import Foundation
import Citadel

enum FileSyncError: Error, LocalizedError {
    case couldNotAccessLocalFolder
    case hostNotConnected

    var errorDescription: String? {
        switch self {
        case .couldNotAccessLocalFolder:
            return "Couldn't access the local folder. Try re-selecting it via Browse…"
        case .hostNotConnected:
            return "Couldn't connect to the host."
        }
    }
}

/// Minimal gitignore-style matcher: `*`/`?` glob wildcards, matched against
/// either the full relative path or any individual path component (so a
/// pattern like `node_modules` skips that directory anywhere in the tree).
enum FileSyncIgnore {
    static func isIgnored(_ relativePath: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let components = relativePath.split(separator: "/").map(String.init)
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if matches(relativePath, pattern: trimmed) { return true }
            if components.contains(where: { matches($0, pattern: trimmed) }) { return true }
        }
        return false
    }

    private static func matches(_ value: String, pattern rawPattern: String) -> Bool {
        var pattern = rawPattern
        if pattern.hasSuffix("/") { pattern.removeLast() }
        guard pattern.contains("*") || pattern.contains("?") else { return value == pattern }
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}

private struct LocalFile {
    let url: URL
    let modifiedAt: Date
}

private struct RemoteFile {
    let path: String
    let modifiedAt: Date
}

extension FileSyncService {
    func performSync(_ record: FileSyncRecord, host: Host, identity: Identity?) async throws {
        let localRoot = resolveLocalURL(for: record)
        let accessed = localRoot.startAccessingSecurityScopedResource()
        defer { if accessed { localRoot.stopAccessingSecurityScopedResource() } }

        let (sshClient, connectionID, ownsConnection) = try await connectSSH(host: host, identity: identity)
        defer {
            if ownsConnection {
                Task { await SSHSessionManager.shared.disconnect(connectionID: connectionID) }
            }
        }

        let localFiles = try enumerateLocalFiles(root: localRoot, ignorePatterns: record.ignorePatterns)
        let remoteFiles = try await enumerateRemoteFiles(
            hostID: host.id,
            sshClient: sshClient,
            root: record.remotePath,
            ignorePatterns: record.ignorePatterns
        )

        switch record.direction {
        case .localToRemote:
            try await pushLocalToRemote(
                localFiles: localFiles, remoteFiles: remoteFiles,
                remoteRoot: record.remotePath, hostID: host.id, sshClient: sshClient
            )
        case .remoteToLocal:
            try await pullRemoteToLocal(
                localFiles: localFiles, remoteFiles: remoteFiles,
                localRoot: localRoot, hostID: host.id, sshClient: sshClient
            )
        case .bidirectional:
            try await pushLocalToRemote(
                localFiles: localFiles, remoteFiles: remoteFiles,
                remoteRoot: record.remotePath, hostID: host.id, sshClient: sshClient
            )
            try await pullRemoteToLocal(
                localFiles: localFiles, remoteFiles: remoteFiles,
                localRoot: localRoot, hostID: host.id, sshClient: sshClient
            )
        }
    }

    private func resolveLocalURL(for record: FileSyncRecord) -> URL {
        if let bookmarkData = record.localBookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return URL(fileURLWithPath: record.localPath, isDirectory: true)
    }

    private func connectSSH(host: Host, identity: Identity?) async throws -> (SSHClient, UUID, Bool) {
        if let existing = await SSHSessionManager.shared.session(forHostID: host.id) {
            return (existing, UUID(), false)
        }
        let connectionID = UUID()
        try await SSHSessionManager.shared.connect(
            connectionID: connectionID,
            host: host,
            identity: identity,
            onOutput: { _ in },
            onClose: { }
        )
        guard let client = await SSHSessionManager.shared.session(for: connectionID) else {
            throw FileSyncError.hostNotConnected
        }
        return (client, connectionID, true)
    }

    private func enumerateLocalFiles(root: URL, ignorePatterns: [String]) throws -> [String: LocalFile] {
        var result: [String: LocalFile] = [:]
        guard FileManager.default.fileExists(atPath: root.path) else { return result }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values.isDirectory != true else { continue }
            let relativePath = fileURL.path
                .dropFirst(root.path.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty, !FileSyncIgnore.isIgnored(relativePath, patterns: ignorePatterns) else { continue }
            result[relativePath] = LocalFile(url: fileURL, modifiedAt: values.contentModificationDate ?? .distantPast)
        }
        return result
    }

    private func enumerateRemoteFiles(
        hostID: UUID,
        sshClient: SSHClient,
        root: String,
        ignorePatterns: [String]
    ) async throws -> [String: RemoteFile] {
        var result: [String: RemoteFile] = [:]
        await walkRemote(hostID: hostID, sshClient: sshClient, path: root, root: root, ignorePatterns: ignorePatterns, into: &result)
        return result
    }

    private func walkRemote(
        hostID: UUID,
        sshClient: SSHClient,
        path: String,
        root: String,
        ignorePatterns: [String],
        into result: inout [String: RemoteFile]
    ) async {
        guard let entries = try? await SFTPService.shared.listDirectory(hostID: hostID, sshClient: sshClient, path: path) else {
            return // directory doesn't exist yet — nothing to pull, push side will create it
        }
        for entry in entries {
            let relativePath = relativeRemotePath(entry.path, root: root)
            guard !FileSyncIgnore.isIgnored(relativePath, patterns: ignorePatterns) else { continue }
            if entry.isDirectory {
                await walkRemote(hostID: hostID, sshClient: sshClient, path: entry.path, root: root, ignorePatterns: ignorePatterns, into: &result)
            } else {
                result[relativePath] = RemoteFile(path: entry.path, modifiedAt: entry.modifiedAt ?? .distantPast)
            }
        }
    }

    private func relativeRemotePath(_ path: String, root: String) -> String {
        var relative = path
        if relative.hasPrefix(root) {
            relative = String(relative.dropFirst(root.count))
        }
        return relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func pushLocalToRemote(
        localFiles: [String: LocalFile],
        remoteFiles: [String: RemoteFile],
        remoteRoot: String,
        hostID: UUID,
        sshClient: SSHClient
    ) async throws {
        var createdDirs = Set<String>()
        for (relativePath, local) in localFiles {
            if let remote = remoteFiles[relativePath], remote.modifiedAt >= local.modifiedAt { continue }
            let remotePath = (remoteRoot as NSString).appendingPathComponent(relativePath)
            let remoteDir = (remotePath as NSString).deletingLastPathComponent
            try await ensureRemoteDirectory(remoteDir, root: remoteRoot, hostID: hostID, sshClient: sshClient, created: &createdDirs)
            try await SFTPService.shared.upload(hostID: hostID, sshClient: sshClient, localURL: local.url, remotePath: remotePath)
        }
    }

    private func ensureRemoteDirectory(
        _ path: String,
        root: String,
        hostID: UUID,
        sshClient: SSHClient,
        created: inout Set<String>
    ) async throws {
        guard path != root, path != "/", !path.isEmpty, !created.contains(path) else { return }
        let parent = (path as NSString).deletingLastPathComponent
        try await ensureRemoteDirectory(parent, root: root, hostID: hostID, sshClient: sshClient, created: &created)
        try? await SFTPService.shared.createDirectory(hostID: hostID, sshClient: sshClient, path: path)
        created.insert(path)
    }

    private func pullRemoteToLocal(
        localFiles: [String: LocalFile],
        remoteFiles: [String: RemoteFile],
        localRoot: URL,
        hostID: UUID,
        sshClient: SSHClient
    ) async throws {
        for (relativePath, remote) in remoteFiles {
            if let local = localFiles[relativePath], local.modifiedAt >= remote.modifiedAt { continue }
            let localURL = localRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await SFTPService.shared.download(hostID: hostID, sshClient: sshClient, remotePath: remote.path, to: localURL)
        }
    }
}
