import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject private var store = SessionHistoryStore.shared
    @State private var searchText = ""
    @State private var selected: SessionHistoryRecord?
    @State private var selectedTag: String?
    @State private var filterBookmarked = false

    private var filtered: [SessionHistoryRecord] {
        var result = store.records

        if filterBookmarked {
            result = result.filter { $0.isBookmarked }
        }

        guard !searchText.isEmpty else { return result }
        return result.filter {
            $0.hostLabel.localizedCaseInsensitiveContains(searchText) ||
            ($0.workspaceName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedByDate: [String: [SessionHistoryRecord]] {
        let calendar = Calendar.current
        var groups: [String: [SessionHistoryRecord]] = [:]

        for record in filtered {
            let key = dateGroupKey(for: record.endedAt)
            groups[key, default: []].append(record)
        }

        return groups
    }

    private func dateGroupKey(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateComponents([.weekOfYear], from: date, to: now).weekOfYear == 0 {
            return "This Week"
        } else if calendar.dateComponents([.month], from: date, to: now).month == 0 {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
    }

    private func sessionDuration(_ record: SessionHistoryRecord) -> String {
        let duration = record.endedAt.timeIntervalSince(record.startedAt)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(duration))s"
        }
    }

    var body: some View {
        NavigationStack {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "terminal.badge.xmark",
                    description: Text(searchText.isEmpty && !filterBookmarked ? "Session history will appear here" : "No matching sessions")
                )
                .navigationTitle("Session History")
            } else {
                List {
                    ForEach(Array(groupedByDate.keys.sorted().reversed()), id: \.self) { dateKey in
                        Section(dateKey) {
                            ForEach(groupedByDate[dateKey] ?? []) { record in
                                Button { selected = record } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Text(record.workspaceName ?? record.hostLabel)
                                                    .fontWeight(.semibold)
                                                    .lineLimit(1)
                                                if record.isBookmarked {
                                                    Image(systemName: "bookmark.fill")
                                                        .font(.caption)
                                                        .foregroundStyle(.orange)
                                                }
                                            }

                                            HStack(spacing: 12) {
                                                Text(record.hostLabel)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)

                                                Text("•")
                                                    .foregroundStyle(.secondary)

                                                Text(sessionDuration(record))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Text(record.transcript.split(separator: "\n").suffix(2).joined(separator: " "))
                                                .font(.system(.caption2, design: .monospaced))
                                                .lineLimit(1)
                                                .foregroundStyle(.tertiary)

                                            if !record.tags.isEmpty {
                                                HStack(spacing: 4) {
                                                    ForEach(record.tags.prefix(2), id: \.self) { tag in
                                                        Text(tag)
                                                            .font(.caption2)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.blue.opacity(0.2))
                                                            .foregroundStyle(.blue)
                                                            .cornerRadius(4)
                                                    }
                                                    if record.tags.count > 2 {
                                                        Text("+\(record.tags.count - 2)")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 4) {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)

                                            Text(record.endedAt, style: .time)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
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
                                        store.toggleBookmark(record)
                                    } label: {
                                        Label("Bookmark", systemImage: record.isBookmarked ? "bookmark.slash" : "bookmark")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Session History")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            filterBookmarked.toggle()
                        } label: {
                            Image(systemName: filterBookmarked ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(filterBookmarked ? .orange : .primary)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search hosts and output")
            }
        }
        .sheet(item: $selected) { record in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.workspaceName ?? record.hostLabel)
                                .font(.headline)

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Host")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(record.hostLabel)
                                        .font(.caption)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Duration")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(sessionDuration(record))
                                        .font(.caption)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ended")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(record.endedAt, style: .relative)
                                        .font(.caption)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                            Divider()

                            HStack(spacing: 16) {
                                if record.averageLatency > 0 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Avg Latency")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(record.averageLatency)ms")
                                            .font(.caption)
                                    }
                                }

                                if record.dataTransferred > 0 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Data")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(record.displayDataTransferred)
                                            .font(.caption)
                                    }
                                }

                                if record.commandCount > 0 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Commands")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(record.commandCount)")
                                            .font(.caption)
                                    }
                                }

                                Spacer()
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(record.tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)

                                        Button {
                                            store.removeTag(tag, from: record)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption2)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(4)
                                }

                                Spacer()
                            }

                            TextField("Add new tag", text: .constant(""))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onSubmit {
                                    // Tag input would go here
                                }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcript")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(record.transcript)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle(record.workspaceName ?? record.hostLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        ShareLink(item: record.transcript) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button("Done") { selected = nil }
                    }
                }
            }
        }
    }
}
