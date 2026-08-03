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
    
    // Background transfer queue
    @Published var transfers: [TransferItem] = []
    private var activeTransfers: [UUID: Task<Void, Never>] = [:]

    init(host: Host, connectionID: UUID, sshClient: SSHClient) {
        self.host = host
        self.connectionID = connectionID
        self.sshClient = sshClient
    }
    
    struct TransferItem: Identifiable, Equatable {
        let id = UUID()
        let entry: SFTPEntry
        let isDownload: Bool
        var progress: Double = 0
        var status: TransferStatus = .pending
        var speed: String = ""
        var eta: String = ""
        var error: String?
        let startTime = Date()
        
        enum TransferStatus: Equatable {
            case pending, active, paused, completed, failed, cancelled
        }
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
    
    func download(_ entry: SFTPEntry) async -> URL? {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
        let transfer = TransferItem(entry: entry, isDownload: true)
        transfers.append(transfer)
        await runTransfer(transfer, destination: destination)
        return destination
    }
    
    func upload(localURL: URL) async {
        let remotePath = (currentPath as NSString).appendingPathComponent(localURL.lastPathComponent)
        let entry = SFTPEntry(name: localURL.lastPathComponent, path: remotePath, isDirectory: false, size: 0, permissions: "", modifiedAt: nil)
        let transfer = TransferItem(entry: entry, isDownload: false)
        transfers.append(transfer)
        await runUploadTransfer(transfer, localURL: localURL, remotePath: remotePath)
    }
    
    private func runTransfer(_ transfer: TransferItem, destination: URL) async {
        guard let index = transfers.firstIndex(where: { $0.id == transfer.id }) else { return }
        
        await MainActor.run {
            transfers[index].status = .active
        }
        
        let task = Task {
            do {
                try await SFTPService.shared.download(
                    hostID: connectionID,
                    sshClient: sshClient,
                    remotePath: transfer.entry.path,
                    to: destination,
                    progressHandler: { progress in
                        Task { @MainActor in
                            if let idx = self.transfers.firstIndex(where: { $0.id == transfer.id }) {
                                self.transfers[idx].progress = progress
                                self.updateSpeedAndETA(for: transfer, progress: progress)
                            }
                        }
                    }
                )
                await MainActor.run {
                    if let idx = self.transfers.firstIndex(where: { $0.id == transfer.id }) {
                        self.transfers[idx].status = .completed
                        self.transfers[idx].progress = 1.0
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = self.transfers.firstIndex(where: { $0.id == transfer.id }) {
                        self.transfers[idx].status = .failed
                        self.transfers[idx].error = error.localizedDescription
                    }
                }
            }
        }
        
        activeTransfers[transfer.id] = task
        await task.value
        activeTransfers.removeValue(forKey: transfer.id)
    }
    
    private func runUploadTransfer(_ transfer: TransferItem, localURL: URL, remotePath: String) async {
        guard let index = transfers.firstIndex(where: { $0.id == transfer.id }) else { return }
        
        await MainActor.run {
            transfers[index].status = .active
        }
        
        let task = Task {
            do {
                try await SFTPService.shared.upload(
                    hostID: connectionID,
                    sshClient: sshClient,
                    localURL: localURL,
                    remotePath: remotePath,
                    progressHandler: { progress in
                        Task { @MainActor in
                            if let idx = self.transfers.firstIndex(where: { $0.id == transfer.id }) {
                                self.transfers[idx].progress = progress
                                self.updateSpeedAndETA(for: transfer, progress: progress)
                            }
                        }
                    }
                )
                await MainActor.run {
                    if let idx = self.transfers.firstIndex(where: { $0.id == transfer.id }) {
                        self.transfers[idx].status = .completed
                        self.transfers[idx].progress = 1.0
                        Task { await self.load() }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = self.transfers.firstIndex(where: { $0.id == transfer.id }) {
                        self.transfers[idx].status = .failed
                        self.transfers[idx].error = error.localizedDescription
                    }
                }
            }
        }
        
        activeTransfers[transfer.id] = task
        await task.value
        activeTransfers.removeValue(forKey: transfer.id)
    }
    
    private func updateSpeedAndETA(for transfer: TransferItem, progress: Double) {
        let elapsed = Date().timeIntervalSince(transfer.startTime)
        if elapsed > 0 && progress > 0 {
            let bytesPerSecond = Double(transfer.entry.size) * progress / elapsed
            let speedStr = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
            let remainingBytes = Double(transfer.entry.size) * (1 - progress)
            let etaSeconds = bytesPerSecond > 0 ? remainingBytes / bytesPerSecond : 0
            let etaStr = etaSeconds > 0 ? formatETA(etaSeconds) : ""
            
            if let idx = transfers.firstIndex(where: { $0.id == transfer.id }) {
                transfers[idx].speed = speedStr
                transfers[idx].eta = etaStr
            }
        }
    }
    
    private func formatETA(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds/60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s" }
        return "\(Int(seconds/3600))h \(Int((seconds.truncatingRemainder(dividingBy: 3600))/60))m"
    }
    
    func pauseTransfer(_ transfer: TransferItem) {
        if let task = activeTransfers[transfer.id] {
            task.cancel()
            activeTransfers.removeValue(forKey: transfer.id)
            if let idx = transfers.firstIndex(where: { $0.id == transfer.id }) {
                transfers[idx].status = .paused
            }
        }
    }
    
    func resumeTransfer(_ transfer: TransferItem) {
        guard let idx = transfers.firstIndex(where: { $0.id == transfer.id }) else { return }
        if transfers[idx].status == .paused || transfers[idx].status == .failed {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(transfer.entry.name)
            Task { await runTransfer(transfer, destination: destination) }
        }
    }
    
    func cancelTransfer(_ transfer: TransferItem) {
        if let task = activeTransfers[transfer.id] {
            task.cancel()
            activeTransfers.removeValue(forKey: transfer.id)
        }
        if let idx = transfers.firstIndex(where: { $0.id == transfer.id }) {
            transfers[idx].status = .cancelled
        }
    }
    
    func clearCompletedTransfers() {
        transfers.removeAll { $0.status == .completed || $0.status == .cancelled }
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
