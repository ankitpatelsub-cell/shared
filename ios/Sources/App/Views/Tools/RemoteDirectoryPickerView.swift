import SwiftUI
import SwiftData
import Citadel

/// Lets the user browse a host's remote filesystem and pick a directory —
/// used by File Sync's remote-path field. Reuses an already-connected
/// session for this host if one exists (e.g. an open terminal tab) so it
/// doesn't disturb it; otherwise opens a short-lived connection of its own
/// (SFTP rides the same SSH session a terminal would, same as everywhere
/// else in the app) and tears it down when the picker closes.
struct RemoteDirectoryPickerView: View {
    let host: Host
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var identities: [Identity]

    @State private var currentPath = "/"
    @State private var entries: [SFTPEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sshClient: SSHClient?
    @State private var ownsConnection = false
    @State private var connectionID = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Can't Browse", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            self.errorMessage = nil
                            Task { await connectAndLoad() }
                        }
                    }
                } else if sshClient == nil {
                    ProgressView("Connecting to \(host.label)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    directoryList
                }
            }
            .navigationTitle(host.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        onSelect(currentPath)
                        dismiss()
                    }
                    .disabled(sshClient == nil)
                }
            }
        }
        .task { await connectAndLoad() }
        .onDisappear {
            guard ownsConnection else { return }
            let id = connectionID
            Task { await SSHSessionManager.shared.disconnect(connectionID: id) }
        }
    }

    @ViewBuilder
    private var directoryList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    Task { await goUp() }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(currentPath == "/")

                Text(currentPath)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

            let folders = entries.filter(\.isDirectory)
            List(folders) { entry in
                Button {
                    Task { await load(path: entry.path) }
                } label: {
                    Label(entry.name, systemImage: "folder")
                        .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .overlay {
                if !isLoading && folders.isEmpty {
                    ContentUnavailableView("No Subfolders", systemImage: "folder")
                }
            }
        }
    }

    private func connectAndLoad() async {
        if let existing = await SSHSessionManager.shared.session(forHostID: host.id) {
            sshClient = existing
            ownsConnection = false
            await load(path: currentPath)
            return
        }

        let identity = identities.first { $0.id == host.identityID }
        do {
            try await SSHSessionManager.shared.connect(
                connectionID: connectionID,
                host: host,
                identity: identity,
                onOutput: { _ in },
                onClose: { }
            )
            ownsConnection = true
            sshClient = await SSHSessionManager.shared.session(for: connectionID)
            await load(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(path: String) async {
        guard let sshClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await SFTPService.shared.listDirectory(hostID: connectionID, sshClient: sshClient, path: path)
            currentPath = path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goUp() async {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        await load(path: parent.isEmpty ? "/" : parent)
    }
}
