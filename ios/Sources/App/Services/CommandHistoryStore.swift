import Foundation

struct CommandHistoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let hostID: UUID
    let command: String
    let timestamp: Date
    let status: String? // success, error, timeout
    var isFavorite: Bool

    var displayCommand: String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 80 ? String(trimmed.prefix(77)) + "…" : trimmed
    }
}

@MainActor
final class CommandHistoryStore: ObservableObject {
    static let shared = CommandHistoryStore()
    @Published private(set) var records: [CommandHistoryRecord] = []

    private let fileURL: URL
    private let maxRecords = 1000

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("command-history.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([CommandHistoryRecord].self, from: data) {
            records = decoded
        }
    }

    func record(_ command: String, hostID: UUID, status: String? = nil) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        records.insert(CommandHistoryRecord(
            id: UUID(),
            hostID: hostID,
            command: command,
            timestamp: Date(),
            status: status,
            isFavorite: false
        ), at: 0)
        records = Array(records.prefix(maxRecords))
        save()
    }

    func toggleFavorite(_ record: CommandHistoryRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isFavorite.toggle()
        save()
    }

    func delete(_ record: CommandHistoryRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func search(_ query: String, hostID: UUID? = nil) -> [CommandHistoryRecord] {
        var results = records.filter { $0.command.localizedCaseInsensitiveContains(query) }
        if let hostID = hostID {
            results = results.filter { $0.hostID == hostID }
        }
        return results
    }

    func favorites(for hostID: UUID? = nil) -> [CommandHistoryRecord] {
        var results = records.filter { $0.isFavorite }
        if let hostID = hostID {
            results = results.filter { $0.hostID == hostID }
        }
        return results
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
