import SwiftUI
import SwiftData

struct RootTabView: View {
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Query private var snippets: [Snippet]
    @Query private var hosts: [Host]
    @Query private var identities: [Identity]
    @AppStorage("dev.termvault.settings.accent") private var accent = "blue"

    var body: some View {
        TabView(selection: Binding(
            get: { navigationStore.selectedTab },
            set: { navigationStore.navigate(to: $0) }
        )) {
            HostListView()
                .tabItem { Label("Hosts", systemImage: "server.rack") }
                .tag(RootTab.hosts)

            WorkspaceBrowserTabView()
                .tabItem { Label("Browser", systemImage: "folder") }
                .tag(RootTab.browser)

            SessionsTabView()
                .tabItem { Label("Sessions", systemImage: "terminal") }
                .tag(RootTab.sessions)

            IdentityManagerView()
                .tabItem { Label("Keys", systemImage: "key.fill") }
                .tag(RootTab.keys)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(RootTab.settings)
        }
        .tint(Theme.accentColor(for: accent))
        // Runs at the app root (not inside a single tab) so agent-completion
        // notifications keep firing no matter which tab is on screen —
        // previously this lived inside WorkspaceBrowserTabView and silently
        // stopped polling as soon as you switched to Hosts/Sessions/Settings.
        .task {
            while !Task.isCancelled {
                await workspaceStore.checkForCompletions()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: snippets.map { "\($0.id):\($0.runOnConnect):\($0.command)" }.joined()) {
            sessionStore.connectionSnippetCommands = snippets.filter { $0.runOnConnect }.map(\.command)
        }
        .task(id: hosts.map(\.id).map(\.uuidString).joined() + identities.map(\.id).map(\.uuidString).joined()) {
            sessionStore.configureConnectionCatalog(hosts: hosts, identities: identities)
        }
    }
}
