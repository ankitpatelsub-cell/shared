import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HostListView()
                .tabItem { Label("Hosts", systemImage: "server.rack") }

            SessionsTabView()
                .tabItem { Label("Sessions", systemImage: "terminal") }

            IdentityManagerView()
                .tabItem { Label("Keys", systemImage: "key.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
