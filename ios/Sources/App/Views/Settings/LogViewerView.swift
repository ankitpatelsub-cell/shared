import SwiftUI

/// Surfaces `ErrorLogger`'s persisted entries — the logging pipeline
/// existed (file persistence, categories, os_log) but had no screen
/// showing it and nothing in the app actually called `.log(...)`, so it
/// was silent infrastructure. Now reachable from Settings, and error paths
/// across SSH/SFTP/host-key/keychain/file-sync now report into it.
struct LogViewerView: View {
    @State private var logs: [ErrorLogger.LogEntry] = []
    @State private var selected: ErrorLogger.LogEntry?
    @State private var showingClearConfirmation = false

    var body: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView(
                    "No Errors Logged",
                    systemImage: "checkmark.circle",
                    description: Text("Problems the app runs into will show up here.")
                )
            } else {
                List {
                    ForEach(logs.reversed()) { entry in
                        Button { selected = entry } label: {
                            row(for: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Error Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !logs.isEmpty {
                    ShareLink(item: ErrorLogger.shared.exportLogsAsText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .confirmationDialog("Clear all logged errors?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) {
                ErrorLogger.shared.clearLogs()
                refresh()
            }
        }
        .sheet(item: $selected) { entry in
            ErrorDetailView(entry: entry)
        }
        .onAppear { refresh() }
    }

    private func row(for entry: ErrorLogger.LogEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.category.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(entry.message)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func refresh() {
        logs = ErrorLogger.shared.getRecentLogs(limit: 200)
    }
}
