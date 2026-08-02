import Foundation

struct SessionHistoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let hostID: UUID
    let hostLabel: String
    let workspaceName: String?
    let startedAt: Date
    let endedAt: Date
    let transcript: String
    var isBookmarked: Bool
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
        // Save full transcript (up to 1M chars) instead of truncating to 500K
        let transcript = String(session.plainTextTranscript.suffix(1_000_000))
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        records.insert(SessionHistoryRecord(
            id: UUID(), hostID: session.host.id, hostLabel: session.host.label,
            workspaceName: session.activeWorkspace?.displayName, startedAt: session.startedAt,
            endedAt: Date(), transcript: transcript, isBookmarked: false
        ), at: 0)
        records = Array(records.prefix(maxRecords))
        save()
    }

    func toggleBookmark(_ record: SessionHistoryRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isBookmarked.toggle(); save()
    }

    func delete(_ record: SessionHistoryRecord) {
        records.removeAll { $0.id == record.id }; save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
