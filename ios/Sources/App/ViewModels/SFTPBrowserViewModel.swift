import Foundation
import Citadel

@MainActor
final class SFTPBrowserViewModel: ObservableObject {
    let host: Host
    private let connectionID: UUID
    private let sshClient: SSHClient

    @Published var currentPath: String = "/"
    @Published var entries: [SFTPEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var transferProgressText: String?

    init(host: Host, connectionID: UUID, sshClient: SSHClient) {
        self.host = host
        self.connectionID = connectionID
        self.sshClient = sshClient
    }

    func load(path: String? = nil) async {
        if let path { currentPath = path }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await SFTPService.shared.listDirectory(hostID: connectionID, sshClient: sshClient, path: currentPath)
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
            try await SFTPService.shared.download(hostID: connectionID, sshClient: sshClient, remotePath: entry.path, to: destination)
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
            try await SFTPService.shared.upload(hostID: connectionID, sshClient: sshClient, localURL: localURL, remotePath: remotePath)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFolder(named name: String) async {
        let path = (currentPath as NSString).appendingPathComponent(name)
        do {
            try await SFTPService.shared.createDirectory(hostID: connectionID, sshClient: sshClient, path: path)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ entry: SFTPEntry, to newName: String) async {
        let newPath = (currentPath as NSString).appendingPathComponent(newName)
        do {
            try await SFTPService.shared.rename(hostID: connectionID, sshClient: sshClient, from: entry.path, to: newPath)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: SFTPEntry) async {
        do {
            try await SFTPService.shared.delete(hostID: connectionID, sshClient: sshClient, path: entry.path, isDirectory: entry.isDirectory)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copy(_ entry: SFTPEntry, to destination: String) async {
        await runFileCommand("cp -R -- \(ProjectDashboardViewModel.quote(entry.path)) \(ProjectDashboardViewModel.quote(destination))")
    }

    func move(_ entry: SFTPEntry, to destination: String) async {
        await runFileCommand("mv -- \(ProjectDashboardViewModel.quote(entry.path)) \(ProjectDashboardViewModel.quote(destination))")
    }

    func changePermissions(_ entry: SFTPEntry, mode: String) async {
        guard mode.count == 3 || mode.count == 4, mode.allSatisfy({ "01234567".contains($0) }) else {
            errorMessage = "Permissions must be an octal mode such as 644 or 0755."
            return
        }
        await runFileCommand("chmod \(mode) -- \(ProjectDashboardViewModel.quote(entry.path))")
    }

    private func runFileCommand(_ command: String) async {
        do {
            _ = try await RemoteCommandService.shared.run(hostID: host.id, command: command)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}
