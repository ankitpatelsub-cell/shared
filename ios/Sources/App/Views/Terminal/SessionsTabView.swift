import SwiftUI

/// Swipe left/right between open sessions (spec 3.3) via a paged TabView —
/// on iPad this reads as the tab strip; on iPhone it's the swipe gesture.
struct SessionsTabView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var splitSessionID: UUID?

    var body: some View {
        NavigationStack {
            content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Sessions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                splitViewToolbarItem
            }
            // An active session already has its own compact host/status bar.
            // Remove the otherwise redundant 44-point navigation heading to
            // leave another terminal row visible above the keyboard.
            .toolbar(sessionStore.sessions.isEmpty ? .visible : .hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var content: some View {
        if sessionStore.sessions.isEmpty {
            ContentUnavailableView(
                "No Open Sessions",
                systemImage: "terminal",
                description: Text("Connect to a host from the Hosts tab to start a session.")
            )
        } else if let primary = sessionStore.activeSession,
                  let secondary = splitSession,
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

    private var splitSession: TerminalViewModel? {
        sessionStore.sessions.first { $0.id == splitSessionID }
    }

    @ToolbarContentBuilder
    private var splitViewToolbarItem: some ToolbarContent {
        if horizontalSizeClass == .regular && sessionStore.sessions.count > 1 {
            ToolbarItem {
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

    private var sessionPager: some View {
        TabView(selection: $sessionStore.activeSessionID) {
            ForEach(sessionStore.sessions) { session in
                TerminalScreenView(viewModel: session)
                    .tag(Optional(session.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
}
