import Foundation

struct SessionHistoryRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case ssh, sftp
    }

    let id: UUID
    let hostID: UUID
    let hostLabel: String
    let workspaceName: String?
    let startedAt: Date
    let endedAt: Date
    let transcript: String
    var isBookmarked: Bool
    var tags: [String] = []
    var averageLatency: Int = 0 // milliseconds
    var dataTransferred: Int64 = 0 // bytes
    var commandCount: Int = 0
    var kind: Kind = .ssh

    init(
        id: UUID, hostID: UUID, hostLabel: String, workspaceName: String?,
        startedAt: Date, endedAt: Date, transcript: String, isBookmarked: Bool,
        tags: [String] = [], averageLatency: Int = 0, dataTransferred: Int64 = 0,
        commandCount: Int = 0, kind: Kind = .ssh
    ) {
        self.id = id
        self.hostID = hostID
        self.hostLabel = hostLabel
        self.workspaceName = workspaceName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcript = transcript
        self.isBookmarked = isBookmarked
        self.tags = tags
        self.averageLatency = averageLatency
        self.dataTransferred = dataTransferred
        self.commandCount = commandCount
        self.kind = kind
    }

    // Custom decoding so records saved before `kind` existed (every SSH
    // session recorded up to this point) still decode instead of throwing —
    // they default to `.ssh`, which is what they always were.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hostID = try container.decode(UUID.self, forKey: .hostID)
        hostLabel = try container.decode(String.self, forKey: .hostLabel)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        transcript = try container.decode(String.self, forKey: .transcript)
        isBookmarked = try container.decode(Bool.self, forKey: .isBookmarked)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        averageLatency = try container.decodeIfPresent(Int.self, forKey: .averageLatency) ?? 0
        dataTransferred = try container.decodeIfPresent(Int64.self, forKey: .dataTransferred) ?? 0
        commandCount = try container.decodeIfPresent(Int.self, forKey: .commandCount) ?? 0
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .ssh
    }

    var displayDataTransferred: String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(dataTransferred)
        var unitIndex = 0

        while value > 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.1f %s", value, units[unitIndex])
    }
}

@MainActor
final class SessionHistoryStore: ObservableObject {
    static let shared = SessionHistoryStore()
    @Published private(set) var records: [SessionHistoryRecord] = []

    private let fileURL: URL
    private let maxRecords = 500 // Increased from 100

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("session-history.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SessionHistoryRecord].self, from: data) {
            records = decoded
        }
    }

    func record(_ session: TerminalViewModel) {
        let transcript = String(session.plainTextTranscript.suffix(1_000_000))
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        records.insert(SessionHistoryRecord(
            id: UUID(), hostID: session.host.id, hostLabel: session.host.label,
            workspaceName: session.activeWorkspace?.displayName, startedAt: session.startedAt,
            endedAt: Date(), transcript: transcript, isBookmarked: false,
            tags: [],
            averageLatency: session.averageLatency,
            dataTransferred: session.sessionDataTransferred,
            commandCount: session.sessionCommandCount
        ), at: 0)
        records = Array(records.prefix(maxRecords))
        save()
    }

    /// Records an SFTP browsing session — previously only SSH terminal
    /// sessions ever showed up in Session History, so closing an SFTP tab
    /// left no trace at all no matter what was browsed or transferred.
    func record(sftp session: SFTPBrowserViewModel) {
        guard let summary = session.historySummary else { return }
        records.insert(SessionHistoryRecord(
            id: UUID(), hostID: session.host.id, hostLabel: session.host.label,
            workspaceName: nil, startedAt: session.startedAt, endedAt: Date(),
            transcript: summary, isBookmarked: false, kind: .sftp
        ), at: 0)
        records = Array(records.prefix(maxRecords))
        save()
    }

    func toggleBookmark(_ record: SessionHistoryRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isBookmarked.toggle()
        save()
    }

    func addTag(_ tag: String, to record: SessionHistoryRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !records[index].tags.contains(trimmed) else { return }
        records[index].tags.append(trimmed)
        save()
    }

    func removeTag(_ tag: String, from record: SessionHistoryRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].tags.removeAll { $0 == tag.lowercased() }
        save()
    }

    func filterByTag(_ tag: String) -> [SessionHistoryRecord] {
        records.filter { $0.tags.contains(tag.lowercased()) }
    }

    func allTags() -> [String] {
        Set(records.flatMap { $0.tags }).sorted()
    }

    func delete(_ record: SessionHistoryRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
