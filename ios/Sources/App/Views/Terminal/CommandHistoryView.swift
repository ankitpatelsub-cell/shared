import SwiftUI

struct CommandHistoryView: View {
    let hostID: UUID
    @ObservedObject private var store = CommandHistoryStore.shared
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @Environment(\.dismiss) private var dismiss

    private var filtered: [CommandHistoryRecord] {
        var results: [CommandHistoryRecord]

        if showFavoritesOnly {
            results = store.favorites(for: hostID)
        } else {
            results = store.records.filter { $0.hostID == hostID }
        }

        guard !searchText.isEmpty else { return results }
        return results.filter { $0.command.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Commands",
                    systemImage: "terminal.badge.xmark",
                    description: Text(searchText.isEmpty && !showFavoritesOnly ? "Command history will appear here" : "No matching commands")
                )
                .navigationTitle("Command History")
            } else {
                List(filtered) { record in
                    Button {
                        UIPasteboard.general.string = record.command.trimmingCharacters(in: .whitespacesAndNewlines)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.displayCommand)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    Text(record.timestamp, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if let status = record.status {
                                        Label(status, systemImage: status == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(status == "success" ? .green : .red)
                                    }
                                }
                            }

                            Spacer()

                            if record.isFavorite {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            store.toggleFavorite(record)
                        } label: {
                            Label("Favorite", systemImage: record.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
                .navigationTitle("Command History")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showFavoritesOnly.toggle()
                        } label: {
                            Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                .foregroundStyle(showFavoritesOnly ? .yellow : .primary)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search commands")
            }
        }
    }
}
