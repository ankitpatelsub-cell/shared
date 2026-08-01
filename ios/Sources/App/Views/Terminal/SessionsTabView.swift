import SwiftUI

/// Swipe left/right between open sessions (spec 3.3) via a paged TabView —
/// on iPad this reads as the tab strip; on iPhone it's the swipe gesture.
struct SessionsTabView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var splitSessionID: UUID?

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
                    if let primary = sessionStore.activeSession,
                       let secondary = sessionStore.sessions.first(where: { $0.id == splitSessionID }),
                       primary.id != secondary.id,
                       horizontalSizeClass == .regular {
                        HStack(spacing: 1) {
                            TerminalScreenView(viewModel: primary)
                            TerminalScreenView(viewModel: secondary)
                        }
                        .background(Color.gray)
                    } else {
                        sessionPager
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if horizontalSizeClass == .regular && sessionStore.sessions.count > 1 {
                    Menu {
                        Button("Single Terminal") { splitSessionID = nil }
                        ForEach(sessionStore.sessions) { session in
                            if session.id != sessionStore.activeSessionID {
                                Button(session.activeWorkspace?.displayName ?? session.host.label) {
                                    splitSessionID = session.id
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                    }
                }
            }
        }
    }

    private var sessionPager: some View {
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
