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
            List {
                ForEach(viewModel.filteredGroups(from: hosts), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.hosts) { host in
                            HostRow(host: host)
                                .contentShape(Rectangle())
                                .onTapGesture { connectingHost = host }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(host)
                                    } label: { Label("Delete", systemImage: "trash") }

                                    Button {
                                        editingHost = host
                                    } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        connectingHost = host
                                    } label: { Label("Connect", systemImage: "bolt.fill") }
                                    .tint(.green)
                                }
                                .contextMenu {
                                    Button("Duplicate") { duplicate(host) }
                                    ShareLink(item: host.connectionSubtitle)
                                }
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchText)
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isPresentingNewHost = true } label: { Image(systemName: "plus") }
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
            startupSnippet: host.startupSnippet,
            groupName: host.groupName,
            tags: host.tags,
            themeName: host.themeName
        )
        modelContext.insert(copy)
    }
}

private struct HostRow: View {
    let host: Host

    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(host.label).font(.body)
                Text(host.connectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
