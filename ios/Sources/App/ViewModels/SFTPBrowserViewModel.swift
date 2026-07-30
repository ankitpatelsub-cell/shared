import Foundation
import Citadel

@MainActor
final class SFTPBrowserViewModel: ObservableObject {
    let host: Host
    private let sshClient: SSHClient

    @Published var currentPath: String = "/"
    @Published var entries: [SFTPEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var transferProgressText: String?

    init(host: Host, sshClient: SSHClient) {
        self.host = host
        self.sshClient = sshClient
    }

    func load(path: String? = nil) async {
        if let path { currentPath = path }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await SFTPService.shared.listDirectory(hostID: host.id, sshClient: sshClient, path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ entry: SFTPEntry) async {
        guard entry.isDirectory else { return }
        await load(path: entry.path)
    }

    func goUp() async {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        await load(path: parent.isEmpty ? "/" : parent)
    }

    func download(_ entry: SFTPEntry) async -> URL? {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
        transferProgressText = "Downloading \(entry.name)…"
        defer { transferProgressText = nil }
        do {
            try await SFTPService.shared.download(hostID: host.id, sshClient: sshClient, remotePath: entry.path, to: destination)
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func upload(localURL: URL) async {
        let remotePath = (currentPath as NSString).appendingPathComponent(localURL.lastPathComponent)
        transferProgressText = "Uploading \(localURL.lastPathComponent)…"
        defer { transferProgressText = nil }
        do {
            try await SFTPService.shared.upload(hostID: host.id, sshClient: sshClient, localURL: localURL, remotePath: remotePath)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFolder(named name: String) async {
        let path = (currentPath as NSString).appendingPathComponent(name)
        do {
            try await SFTPService.shared.createDirectory(hostID: host.id, sshClient: sshClient, path: path)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ entry: SFTPEntry, to newName: String) async {
        let newPath = (currentPath as NSString).appendingPathComponent(newName)
        do {
            try await SFTPService.shared.rename(hostID: host.id, sshClient: sshClient, from: entry.path, to: newPath)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: SFTPEntry) async {
        do {
            try await SFTPService.shared.delete(hostID: host.id, sshClient: sshClient, path: entry.path, isDirectory: entry.isDirectory)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
