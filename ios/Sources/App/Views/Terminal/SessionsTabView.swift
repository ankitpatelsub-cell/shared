import SwiftUI

/// Swipe left/right between open sessions (spec 3.3) via a paged TabView —
/// on iPad this reads as the tab strip; on iPhone it's the swipe gesture.
struct SessionsTabView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        NavigationStack {
            Group {
                if sessionStore.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Open Sessions",
                        systemImage: "terminal",
                        description: Text("Connect to a host from the Hosts tab to start a session.")
                    )
                } else {
                    TabView(selection: $sessionStore.activeSessionID) {
                        ForEach(sessionStore.sessions) { session in
                            TerminalScreenView(viewModel: session)
                                .tag(Optional(session.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
