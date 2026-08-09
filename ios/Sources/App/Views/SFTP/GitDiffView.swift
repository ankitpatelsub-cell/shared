import SwiftUI

/// Reviews what an agent (or anything else) changed in a project — the
/// natural next step after a "finished" notification, previously only
/// available as a raw `git diff --stat` dump into a plain text field.
/// Reachable both from the Project Dashboard and directly from an active
/// terminal session's "…" menu, so reviewing a change doesn't require
/// leaving the terminal to go find the SFTP browser first.
struct GitDiffView: View {
    let host: Host
    let path: String

    @State private var files: [GitDiffFile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var includeStaged = true
    @State private var expandedFileIDs: Set<UUID> = []
    @State private var commitMessage = ""
    @State private var isCommitting = false
    @State private var discardTarget: GitDiffFile?
    @State private var isDiscarding = false
    // Separate from `errorMessage` (which replaces the whole screen with
    // ContentUnavailableView) — a failed commit/discard shouldn't blow away
    // the diff the user is looking at, just surface an alert over it.
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't Load Diff", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if files.isEmpty {
                    ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("The working tree is clean."))
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Label("\(files.count) file\(files.count == 1 ? "" : "s")", systemImage: "doc.on.doc")
                                Label("+\(files.reduce(0) { $0 + $1.additions })", systemImage: "plus")
                                    .foregroundStyle(.green)
                                Label("-\(files.reduce(0) { $0 + $1.deletions })", systemImage: "minus")
                                    .foregroundStyle(.red)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        }
                        ForEach(files) { file in
                            Section {
                                if expandedFileIDs.contains(file.id) {
                                    if file.isBinary {
                                        Text("Binary file — no text diff to show.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(file.hunks) { hunk in
                                            hunkView(hunk)
                                        }
                                    }
                                }
                            } header: {
                                Button {
                                    toggle(file.id)
                                } label: {
                                    fileHeader(file)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        discardTarget = file
                                    } label: {
                                        Label("Discard Changes", systemImage: "arrow.uturn.backward")
                                    }
                                }
                            }
                        }

                        Section {
                            TextField("Commit message", text: $commitMessage, axis: .vertical)
                                .lineLimit(2...5)
                            Button {
                                Task { await commitAll() }
                            } label: {
                                if isCommitting {
                                    HStack { ProgressView(); Text("Committing…") }
                                } else {
                                    Text("Commit All Changes")
                                }
                            }
                            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting)
                        } header: {
                            Text("Commit")
                        } footer: {
                            Text("Stages and commits every file shown above with this message.")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Diff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle("Include Staged Changes", isOn: $includeStaged)
                        Button {
                            Task { await load() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: includeStaged) { _, _ in Task { await load() } }
            .task { await load() }
            .confirmationDialog(
                "Discard changes to \(discardTarget?.displayPath ?? "")?",
                isPresented: Binding(get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    if let file = discardTarget { Task { await discard(file) } }
                }
                Button("Cancel", role: .cancel) { discardTarget = nil }
            } message: {
                Text("This can't be undone.")
            }
            .alert("Action Failed", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) { Button("OK") {} } message: { Text(actionError ?? "") }
            .disabled(isDiscarding)
        }
    }

    private func commitAll() async {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !files.isEmpty else { return }
        isCommitting = true
        defer { isCommitting = false }

        // Stage only the files actually shown in this diff, not `-A` —
        // committing everything in the working tree would silently include
        // any pre-existing staged changes the "unstaged only" toggle was
        // deliberately hiding. Renamed files need both the old and new
        // path staged so git records the rename instead of a delete+add.
        let paths = files.flatMap { file -> [String] in
            file.isRenamed ? [file.oldPath, file.newPath] : [file.displayPath]
        }.map(ProjectDashboardViewModel.quote).joined(separator: " ")

        let command = "cd -- \(ProjectDashboardViewModel.quote(path)) && git add -- \(paths) && git commit -m \(ProjectDashboardViewModel.quote(message)) 2>&1"
        do {
            _ = try await RemoteCommandService.shared.run(hostID: host.id, command: command, maxResponseSize: 1_048_576)
            commitMessage = ""
            await load()
        } catch {
            actionError = error.localizedDescription
            ErrorLogger.shared.log(category: .general, message: "Commit failed for \(path)", technicalDetails: error.localizedDescription)
        }
    }

    private func discard(_ file: GitDiffFile) async {
        discardTarget = nil
        isDiscarding = true
        defer { isDiscarding = false }

        // Untracked (new) files aren't restored by `git checkout` — remove
        // them directly. Everything else gets restored to HEAD.
        let target = ProjectDashboardViewModel.quote(file.displayPath)
        let command = file.isNew
            ? "cd -- \(ProjectDashboardViewModel.quote(path)) && rm -f -- \(target) 2>&1"
            : "cd -- \(ProjectDashboardViewModel.quote(path)) && git checkout -- \(target) 2>&1"
        do {
            _ = try await RemoteCommandService.shared.run(hostID: host.id, command: command, maxResponseSize: 1_048_576)
            await load()
        } catch {
            actionError = error.localizedDescription
            ErrorLogger.shared.log(category: .general, message: "Discard failed for \(file.displayPath)", technicalDetails: error.localizedDescription)
        }
    }

    private func fileHeader(_ file: GitDiffFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: expandedFileIDs.contains(file.id) ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            statusBadge(for: file)
            Text(file.displayPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if file.additions > 0 {
                Text("+\(file.additions)").font(.caption2.weight(.semibold)).foregroundStyle(.green)
            }
            if file.deletions > 0 {
                Text("-\(file.deletions)").font(.caption2.weight(.semibold)).foregroundStyle(.red)
            }
        }
        .textCase(nil)
    }

    private func statusBadge(for file: GitDiffFile) -> some View {
        let (label, color): (String, Color) = {
            if file.isNew { return ("A", .green) }
            if file.isDeleted { return ("D", .red) }
            if file.isRenamed { return ("R", .orange) }
            return ("M", .blue)
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(color))
    }

    private func hunkView(_ hunk: GitDiffHunk) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(hunk.header)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                ForEach(hunk.lines) { line in
                    HStack(spacing: 4) {
                        Text(prefix(for: line.kind))
                            .foregroundStyle(.secondary)
                        Text(line.text.isEmpty ? " " : line.text)
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(color(for: line.kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .background(background(for: line.kind))
                }
            }
        }
    }

    private func prefix(for kind: GitDiffLine.Kind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }

    private func color(for kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .primary
        }
    }

    private func background(for kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .addition: return .green.opacity(0.12)
        case .deletion: return .red.opacity(0.12)
        case .context: return .clear
        }
    }

    private func toggle(_ id: UUID) {
        if expandedFileIDs.contains(id) { expandedFileIDs.remove(id) } else { expandedFileIDs.insert(id) }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let flags = includeStaged ? "HEAD" : ""
        let command = "cd -- \(ProjectDashboardViewModel.quote(path)) && git diff \(flags) --no-color 2>&1"
        do {
            let output = try await RemoteCommandService.shared.run(hostID: host.id, command: command, maxResponseSize: 4_194_304)
            let parsed = GitDiff.parse(output)
            files = parsed
            expandedFileIDs = Set(parsed.prefix(3).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
            ErrorLogger.shared.log(category: .general, message: "Couldn't load diff for \(path)", technicalDetails: error.localizedDescription)
        }
    }
}
