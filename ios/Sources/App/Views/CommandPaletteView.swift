import SwiftUI
import SwiftData

struct CommandPaletteView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionStore: SessionStore
    @Query(sort: \Host.label) private var hosts: [Host]
    @Query(sort: \Snippet.name) private var snippets: [Snippet]
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    var onAction: (CommandAction) -> Void

    enum CommandAction {
        case openHost(Host)
        case openSnippet(Snippet)
        case newTabForHost(Host)
        case openSettings
        case openKeys
        case newSession
    }

    var filteredItems: [CommandItem] {
        var items: [CommandItem] = []

        // Add hosts
        for host in hosts {
            items.append(CommandItem.host(host))
        }

        // Add snippets
        for snippet in snippets {
            items.append(CommandItem.snippet(snippet))
        }

        // Add actions
        items.append(CommandItem.action(action: .newSession, title: "New Session", icon: "plus.circle"))
        items.append(CommandItem.action(action: .openSettings, title: "Settings", icon: "gear"))
        items.append(CommandItem.action(action: .openKeys, title: "SSH Keys", icon: "key"))

        // Add new tab actions for each host with active sessions
        for session in sessionStore.sessions {
            if session.activeWorkspace == nil {
                items.append(CommandItem.newTabForHost(session.host))
            }
        }

        guard !searchText.isEmpty else { return items }

        let query = searchText.lowercased()
        return items.filter { item in
            switch item.type {
            case .host(let host):
                return host.label.lowercased().contains(query) ||
                       host.address.lowercased().contains(query) ||
                       host.username.lowercased().contains(query)
            case .snippet(let snippet):
                return snippet.name.lowercased().contains(query) ||
                       snippet.command.lowercased().contains(query)
            case .action(_, let title, _):
                return title.lowercased().contains(query)
            case .newTabForHost(let host):
                return "New Tab \(host.label)".lowercased().contains(query) ||
                       host.label.lowercased().contains(query)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredItems) { item in
                    Button {
                        handleSelection(item)
                    } label: {
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundStyle(item.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(.body, design: .default))
                                    .foregroundStyle(.primary)
                                if let subtitle = item.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search hosts, snippets, commands...")
            .onAppear {
                isSearchFocused = true
            }
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func handleSelection(_ item: CommandItem) {
        switch item.type {
        case .host(let host):
            onAction(.openHost(host))
        case .snippet(let snippet):
            onAction(.openSnippet(snippet))
        case .newTabForHost(let host):
            onAction(.newTabForHost(host))
        case .action(let action, _, _):
            onAction(action)
        }
        isPresented = false
    }
}

struct CommandItem: Identifiable {
    let id = UUID()
    enum ItemType {
        case host(Host)
        case snippet(Snippet)
        case action(CommandAction, title: String, icon: String)
        case newTabForHost(Host)
    }
    let type: ItemType

    static func host(_ host: Host) -> CommandItem {
        CommandItem(type: .host(host))
    }

    static func snippet(_ snippet: Snippet) -> CommandItem {
        CommandItem(type: .snippet(snippet))
    }

    static func action(action: CommandAction, title: String, icon: String) -> CommandItem {
        CommandItem(type: .action(action, title: title, icon: icon))
    }

    static func newTabForHost(_ host: Host) -> CommandItem {
        CommandItem(type: .newTabForHost(host))
    }

    var title: String {
        switch type {
        case .host(let host): return host.label
        case .snippet(let snippet): return snippet.name
        case .action(_, let title, _): return title
        case .newTabForHost(let host): return "New Tab: \(host.label)"
        }
    }

    var subtitle: String? {
        switch type {
        case .host(let host): return "\(host.username)@\(host.address):\(host.port)"
        case .snippet(let snippet): return snippet.command
        case .action: return nil
        case .newTabForHost(let host): return "\(host.username)@\(host.address):\(host.port)"
        }
    }

    var icon: String {
        switch type {
        case .host: return "server.rack"
        case .snippet: return "doc.text"
        case .action(_, _, let icon): return icon
        case .newTabForHost: return "plus.rectangle.on.rectangle"
        }
    }

    var color: Color {
        switch type {
        case .host: return .blue
        case .snippet: return .green
        case .action: return .orange
        case .newTabForHost: return .purple
        }
    }
}