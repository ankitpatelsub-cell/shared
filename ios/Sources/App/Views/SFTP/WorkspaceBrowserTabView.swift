import SwiftUI
import SwiftData

struct WorkspaceBrowserTabView: View {
    @Query(sort: \Host.label) private var hosts: [Host]
    @Query private var identities: [Identity]
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @State private var renamingWorkspace: WorkspaceSession?
    @State private var workspaceName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !workspaceStore.recentSessions.isEmpty {
                    Section("Continue Working") {
                        ForEach(workspaceStore.recentSessions) { workspace in
                            if let host = hosts.first(where: { $0.id == workspace.hostID }) {
                                Button {
                                    launch(workspace, host: host)
                                } label: {
                                    WorkspaceRow(workspace: workspace)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(workspace.pinnedAt == nil ? "Pin" : "Unpin") {
                                        workspaceStore.togglePin(workspace)
                                    }
                                    Button("Rename") {
                                        workspaceName = workspace.displayName
                                        renamingWorkspace = workspace
                                    }
                                    Button("Duplicate") {
                                        launch(workspaceStore.duplicate(workspace), host: host)
                                    }
                                    Button("Restart Remote Session") {
                                        Task {
                                            try? await workspaceStore.terminate(workspace)
                                            if let active = sessionStore.terminalSessions.first(where: { $0.activeWorkspace?.id == workspace.id }) {
                                                sessionStore.close(active)
                                            }
                                            launch(workspace, host: host)
                                        }
                                    }
                                    Button("Terminate Remote Session", role: .destructive) {
                                        Task {
                                            do { try await workspaceStore.terminate(workspace) }
                                            catch { errorMessage = error.localizedDescription }
                                        }
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) { workspaceStore.remove(workspace) } label: {
                                        Label("Forget", systemImage: "trash")
                                    }
                                    Button { workspaceStore.togglePin(workspace) } label: {
                                        Label(workspace.pinnedAt == nil ? "Pin" : "Unpin", systemImage: "pin")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }

                Section("Browse a Host") {
                    ForEach(hosts) { host in
                        Button {
                            browseFiles(host: host)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(host.label)
                                    Text(host.connectionSubtitle)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "externaldrive.connected.to.line.below")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Browser")
            .alert("Rename Session", isPresented: Binding(
                get: { renamingWorkspace != nil },
                set: { if !$0 { renamingWorkspace = nil } }
            )) {
                TextField("Session name", text: $workspaceName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let renamingWorkspace { workspaceStore.rename(renamingWorkspace, to: workspaceName) }
                    renamingWorkspace = nil
                }
            }
            .alert("Session Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK") {} } message: { Text(errorMessage ?? "") }
            .overlay {
                if hosts.isEmpty {
                    ContentUnavailableView(
                        "No Hosts Yet", systemImage: "folder",
                        description: Text("Add a host first, then browse its folders here.")
                    )
                }
            }
        }
    }

    private func identity(for host: Host) -> Identity? {
        guard let id = host.identityID else { return nil }
        return identities.first { $0.id == id }
    }

    private func launch(_ workspace: WorkspaceSession, host: Host) {
        sessionStore.open(workspace: workspace, host: host, identity: identity(for: host))
        navigationStore.navigate(to: .sessions)
    }

    private func browseFiles(host: Host) {
        let terminal = sessionStore.open(host: host, identity: identity(for: host))
        navigationStore.navigate(to: .sessions)
        Task {
            for _ in 0..<50 {
                if let sshClient = await SSHSessionManager.shared.session(for: terminal.id) {
                    sessionStore.openSFTP(host: host, connectionID: terminal.id, sshClient: sshClient)
                    return
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: WorkspaceSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workspace.tool.icon)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.displayName).fontWeight(.semibold)
                Text("\(workspace.tool.title) · \(workspace.hostLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(workspace.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(Color.accentColor)
        }
    }
}
