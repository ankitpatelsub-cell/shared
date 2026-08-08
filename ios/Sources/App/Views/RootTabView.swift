import SwiftUI
import SwiftData

struct RootTabView: View {
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @ObservedObject private var notificationRouter = NotificationRouter.shared
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
        .onChange(of: notificationRouter.pendingTab) { _, tab in
            guard let tab else { return }
            navigationStore.navigate(to: tab)
            notificationRouter.pendingTab = nil
        }
        .onChange(of: notificationRouter.pendingWorkspaceID) { _, workspaceID in
            guard let workspaceID else { return }
            defer { notificationRouter.pendingWorkspaceID = nil }
            // Best-effort: only routes to a session that's already open in
            // this process. A notification can arrive after the app was
            // relaunched fresh (sessions gone), in which case there's
            // nothing live to switch to — fall back to the Browser tab so
            // the user can relaunch the workspace themselves.
            if let session = sessionStore.terminalSessions.first(where: { $0.activeWorkspace?.id == workspaceID }) {
                sessionStore.activeSessionID = session.id
                navigationStore.navigate(to: .sessions)
            } else {
                navigationStore.navigate(to: .browser)
            }
        }
    }
}
