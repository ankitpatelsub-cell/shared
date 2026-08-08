import SwiftData
import SwiftUI

struct SnippetLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionStore: SessionStore
    @Query(sort: \Snippet.name) private var snippets: [Snippet]
    @State private var editing: Snippet?
    @State private var adding = false
    @State private var resultMessage: String?

    var body: some View {
        List {
            if snippets.isEmpty {
                ContentUnavailableView(
                    "No Snippets", systemImage: "text.badge.plus",
                    description: Text("Save commands for quick reuse and multi-host execution.")
                )
            }
            ForEach(snippets) { snippet in
                Button { editing = snippet } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(snippet.name).fontWeight(.semibold)
                            if snippet.runOnConnect {
                                Text("ON CONNECT").font(.caption2.weight(.bold)).foregroundStyle(.tint)
                            }
                        }
                        Text(snippet.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { modelContext.delete(snippet) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { Task { await runOnConnectedHosts(snippet) } } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .tint(.green)
                }
                .contextMenu {
                    Button("Run on Connected Hosts") { Task { await runOnConnectedHosts(snippet) } }
                    Button("Edit") { editing = snippet }
                }
            }
        }
        .navigationTitle("Snippets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) { SnippetEditorView() }
        .sheet(item: $editing) { SnippetEditorView(snippet: $0) }
        .alert("Snippet Execution", isPresented: Binding(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } }
        )) { Button("OK") {} } message: { Text(resultMessage ?? "") }
    }

    private func runOnConnectedHosts(_ snippet: Snippet) async {
        let sessions = sessionStore.terminalSessions.filter { $0.status == .connected }
        guard !sessions.isEmpty else { resultMessage = "No connected hosts."; return }
        var successes = 0
        var failures: [String] = []
        for session in sessions {
            do {
                _ = try await RemoteCommandService.shared.run(hostID: session.host.id, command: snippet.command)
                successes += 1
            } catch { failures.append(session.host.label) }
        }
        resultMessage = failures.isEmpty
            ? "Ran on \(successes) connected host(s)."
            : "Succeeded on \(successes); failed on: \(failures.joined(separator: ", "))."
    }
}

private struct SnippetEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let snippet: Snippet?
    @State private var name: String
    @State private var command: String
    @State private var runOnConnect: Bool

    init(snippet: Snippet? = nil) {
        self.snippet = snippet
        _name = State(initialValue: snippet?.name ?? "")
        _command = State(initialValue: snippet?.command ?? "")
        _runOnConnect = State(initialValue: snippet?.runOnConnect ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Command", text: $command, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(4...12)
                Toggle("Run when connecting", isOn: $runOnConnect)
            }
            .navigationTitle(snippet == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let value = snippet ?? Snippet(name: name, command: command)
                        value.name = name; value.command = command; value.runOnConnect = runOnConnect
                        if snippet == nil { modelContext.insert(value) }
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || command.isEmpty)
                }
            }
        }
    }
}
