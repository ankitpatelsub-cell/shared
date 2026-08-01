import SwiftUI
import SwiftData

struct HostListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Host.label) private var hosts: [Host]
    @Query private var identities: [Identity]
    @StateObject private var viewModel = HostListViewModel()

    @State private var editingHost: Host?
    @State private var isPresentingNewHost = false
    @State private var connectingHost: Host?

    var body: some View {
        NavigationStack {
            Group {
                if hosts.isEmpty {
                    emptyState
                } else {
                    hostList
                }
            }
            .searchable(text: $viewModel.searchText)
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isPresentingNewHost = true } label: { Image(systemName: "plus.circle.fill") }
                        .font(.title3)
                }
            }
            .sheet(isPresented: $isPresentingNewHost) {
                HostEditorView(host: nil)
            }
            .sheet(item: $editingHost) { host in
                HostEditorView(host: host)
            }
            .navigationDestination(item: $connectingHost) { host in
                ConnectDestinationView(host: host, identity: identity(for: host))
            }
        }
    }

    /// Split out of `body` — the compiler couldn't type-check the List,
    /// ForEach/Section, and per-row swipe-action/context-menu chain as one
    /// nested expression ("unable to type-check this expression in
    /// reasonable time"). Breaking it into its own property, with the row
    /// itself further extracted to `HostListRow`, gives the type checker
    /// smaller pieces to solve independently.
    private var hostList: some View {
        List {
            ForEach(viewModel.filteredGroups(from: hosts), id: \.title) { group in
                Section {
                    ForEach(group.hosts) { host in
                        HostListRow(
                            host: host,
                            onConnect: { connectingHost = host },
                            onEdit: { editingHost = host },
                            onDelete: { delete(host) },
                            onDuplicate: { duplicate(host) }
                        )
                    }
                } header: {
                    Text(group.title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Hosts Yet", systemImage: "server.rack")
        } description: {
            Text("Add a host to start an SSH session.")
        } actions: {
            Button("Add Host") { isPresentingNewHost = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func identity(for host: Host) -> Identity? {
        guard let id = host.identityID else { return nil }
        return identities.first { $0.id == id }
    }

    private func delete(_ host: Host) {
        try? KeychainService.deletePassword(for: host)
        modelContext.delete(host)
    }

    private func duplicate(_ host: Host) {
        let copy = Host(
            label: host.label + " Copy",
            address: host.address,
            port: host.port,
            username: host.username,
            authMethod: host.authMethod,
            identityID: host.identityID,
            jumpHostID: host.jumpHostID,
            startupSnippet: host.startupSnippet,
            groupName: host.groupName,
            tags: host.tags,
            themeName: host.themeName
        )
        modelContext.insert(copy)
    }
}

/// One row's full modifier chain (swipe actions, context menu, list-row
/// styling), pulled out of `HostListView.hostList` so each piece is its
/// own small expression for the type checker rather than one giant nested
/// closure tree.
private struct HostListRow: View {
    let host: Host
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        HostRow(host: host)
            .cardBackground()
            .contentShape(Rectangle())
            .onTapGesture(perform: onConnect)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .leading) {
                Button(action: onConnect) {
                    Label("Connect", systemImage: "bolt.fill")
                }
                .tint(.green)
            }
            .contextMenu {
                Button("Duplicate", action: onDuplicate)
                ShareLink(item: host.connectionSubtitle)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}

private struct HostRow: View {
    let host: Host

    var body: some View {
        HStack(spacing: 12) {
            HostAvatarView(label: host.label)

            VStack(alignment: .leading, spacing: 3) {
                Text(host.label)
                    .font(.system(.body, design: .default, weight: .semibold))
                Text(host.connectionSubtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: host.authMethod == .privateKey ? "key.fill" : "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(host.authMethod == .privateKey ? "SSH key auth" : "Password auth")
        }
    }
}

/// Kicks off (or reuses) the session on `.task` rather than inline in
/// `body`, so navigating here twice for the same host never opens a second
/// connection or re-triggers `connect()` as a side effect of SwiftUI
/// re-rendering the view.
private struct ConnectDestinationView: View {
    let host: Host
    let identity: Identity?
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var viewModel: TerminalViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TerminalScreenView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            viewModel = sessionStore.open(host: host, identity: identity)
        }
    }
}
