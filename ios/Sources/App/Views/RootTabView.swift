import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var navigationStore: AppNavigationStore

    var body: some View {
        TabView(selection: $navigationStore.selectedTab) {
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
    }
}
