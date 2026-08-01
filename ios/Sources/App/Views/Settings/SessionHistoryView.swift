import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject private var store = SessionHistoryStore.shared
    @State private var searchText = ""
    @State private var selected: SessionHistoryRecord?

    private var filtered: [SessionHistoryRecord] {
        guard !searchText.isEmpty else { return store.records }
        return store.records.filter {
            $0.hostLabel.localizedCaseInsensitiveContains(searchText) ||
            ($0.workspaceName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filtered) { record in
            Button { selected = record } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.workspaceName ?? record.hostLabel).fontWeight(.semibold)
                        Text(record.endedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        Text(record.transcript.split(separator: "\n").suffix(2).joined(separator: " "))
                            .font(.system(.caption2, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if record.isBookmarked { Image(systemName: "bookmark.fill").foregroundStyle(.tint) }
                }
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button(role: .destructive) { store.delete(record) } label: { Label("Delete", systemImage: "trash") }
                Button { store.toggleBookmark(record) } label: { Label("Bookmark", systemImage: "bookmark") }
                    .tint(.orange)
            }
        }
        .searchable(text: $searchText, prompt: "Search hosts and output")
        .navigationTitle("Session History")
        .sheet(item: $selected) { record in
            NavigationStack {
                ScrollView {
                    Text(record.transcript).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .navigationTitle(record.workspaceName ?? record.hostLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selected = nil } } }
            }
        }
    }
}
