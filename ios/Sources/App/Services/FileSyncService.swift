import Foundation

struct FileSyncRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let hostID: UUID
    let localPath: String
    let remotePath: String
    let direction: SyncDirection // local-to-remote, remote-to-local, bidirectional
    let lastSyncedAt: Date?
    let autoSync: Bool
    let ignorePatterns: [String] // .gitignore style patterns

    enum SyncDirection: String, Codable {
        case localToRemote = "l2r"
        case remoteToLocal = "r2l"
        case bidirectional = "both"
    }

    var displayDirection: String {
        switch direction {
        case .localToRemote: return "Local → Remote"
        case .remoteToLocal: return "Remote → Local"
        case .bidirectional: return "Bidirectional"
        }
    }
}

@MainActor
final class FileSyncService: ObservableObject {
    static let shared = FileSyncService()
    @Published private(set) var syncRecords: [FileSyncRecord] = []
    @Published private(set) var syncStatus: String?
    @Published private(set) var isSyncing = false

    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("file-sync-records.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([FileSyncRecord].self, from: data) {
            syncRecords = decoded
        }
    }

    func addSyncRecord(
        hostID: UUID,
        localPath: String,
        remotePath: String,
        direction: FileSyncRecord.SyncDirection,
        autoSync: Bool = false,
        ignorePatterns: [String] = []
    ) {
        let record = FileSyncRecord(
            id: UUID(),
            hostID: hostID,
            localPath: localPath,
            remotePath: remotePath,
            direction: direction,
            lastSyncedAt: nil,
            autoSync: autoSync,
            ignorePatterns: ignorePatterns
        )
        syncRecords.append(record)
        save()
    }

    func removeSyncRecord(_ record: FileSyncRecord) {
        syncRecords.removeAll { $0.id == record.id }
        save()
    }

    func updateLastSynced(_ record: FileSyncRecord) {
        guard let index = syncRecords.firstIndex(where: { $0.id == record.id }) else { return }
        var updated = syncRecords[index]
        updated = FileSyncRecord(
            id: updated.id,
            hostID: updated.hostID,
            localPath: updated.localPath,
            remotePath: updated.remotePath,
            direction: updated.direction,
            lastSyncedAt: Date(),
            autoSync: updated.autoSync,
            ignorePatterns: updated.ignorePatterns
        )
        syncRecords[index] = updated
        save()
    }

    func syncNow(_ record: FileSyncRecord) async {
        await MainActor.run {
            isSyncing = true
            syncStatus = "Syncing \(record.localPath.components(separatedBy: "/").last ?? "files")..."
        }

        do {
            // Simulate sync operation
            try await Task.sleep(for: .seconds(2))

            await MainActor.run {
                updateLastSynced(record)
                syncStatus = "Sync completed for \(record.localPath)"
                isSyncing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.syncStatus = nil
                }
            }
        } catch {
            await MainActor.run {
                syncStatus = "Sync failed: \(error.localizedDescription)"
                isSyncing = false
            }
        }
    }

    func syncAll() async {
        let records = syncRecords.filter { $0.autoSync }
        for record in records {
            await syncNow(record)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(syncRecords) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
