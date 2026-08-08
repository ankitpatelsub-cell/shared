import SwiftUI
import SwiftData

/// Swipe left/right between open sessions (spec 3.3) via a paged TabView —
/// on iPad this reads as the tab strip; on iPhone it's the swipe gesture.
struct SessionsTabView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Query private var identities: [Identity]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var splitSessionID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if sessionStore.sessions.count > 1 {
                    sessionTabStrip
                }
                content
            }
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

    /// A always-visible strip of open sessions — tapping one switches to it
    /// immediately, instead of swiping through them one at a time or diving
    /// into the "…" menu's buried "Switch Session" submenu. Mirrors the
    /// browser-tab-bar pattern every user already knows.
    private var sessionTabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sessionStore.sessions) { session in
                        SessionTabChip(
                            session: session,
                            isActive: session.id == sessionStore.activeSessionID
                        ) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                sessionStore.activeSessionID = session.id
                            }
                        } onClose: {
                            sessionStore.close(session)
                        }
                        .id(session.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(Color.black.opacity(0.92))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
            }
            .onChange(of: sessionStore.activeSessionID) { _, newValue in
                guard let newValue else { return }
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
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
        } else if let primary = sessionStore.activeSession?.terminal,
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

    // Splitting is only supported terminal-to-terminal; SFTP sessions fall
    // back to the single-pane pager.
    private var splitSession: TerminalViewModel? {
        sessionStore.terminalSessions.first { $0.id == splitSessionID }
    }

    @ToolbarContentBuilder
    private var splitViewToolbarItem: some ToolbarContent {
        if horizontalSizeClass == .regular && sessionStore.terminalSessions.count > 1 {
            ToolbarItem {
                Menu {
                    Button("Single Terminal") { splitSessionID = nil }
                    ForEach(sessionStore.terminalSessions) { session in
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
                Group {
                    switch session {
                    case .terminal(let viewModel):
                        TerminalScreenView(viewModel: viewModel)
                    case .sftp(let viewModel):
                        SFTPBrowserView(
                            viewModel: viewModel,
                            onLaunch: { path, tool in launchWorkspace(host: viewModel.host, path: path, tool: tool) },
                            onLaunchPreset: { path, preset in launchWorkspace(host: viewModel.host, path: path, preset: preset) }
                        )
                    }
                }
                .tag(Optional(session.id))
            }
        }
        // Always `.never`: `indexDisplayMode` used to flip between `.always`
        // and `.never` based on session count, and toggling it exactly when
        // a session is added/removed crashes UIKitPageIndexView (array
        // index out-of-bounds inside its internal dot-count update — this
        // is what produced the SIGTRAP opening SFTP browse, since that adds
        // a new session while page count and index-mode changed together).
        // The tab strip above already shows position/switching, so the
        // page dots were redundant even at a single session.
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func identity(for host: Host) -> Identity? {
        guard let id = host.identityID else { return nil }
        return identities.first { $0.id == id }
    }

    private func launchWorkspace(host: Host, path: String, tool: AgentTool) {
        let workspace = workspaceStore.session(host: host, path: path, tool: tool)
        sessionStore.open(workspace: workspace, host: host, identity: identity(for: host))
    }

    private func launchWorkspace(host: Host, path: String, preset: AgentPreset) {
        let workspace = workspaceStore.session(host: host, path: path, preset: preset)
        sessionStore.open(workspace: workspace, host: host, identity: identity(for: host))
    }
}

private struct SessionTabChip: View {
    let session: OpenSession
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                statusDot
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.6))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 16, height: 16)
                }
                .accessibilityLabel("Close \(session.displayTitle)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isActive ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
            )
            .overlay(
                Capsule().strokeBorder(isActive ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let terminal = session.terminal, terminal.status.isFailure || terminal.status == .disconnected {
                Button {
                    Task { await terminal.reconnect() }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive, action: onClose) {
                Label("Close", systemImage: "xmark")
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if case .terminal(let vm) = session {
            Circle()
                .fill(Theme.Status.color(for: vm.status))
                .frame(width: 6, height: 6)
        } else {
            Image(systemName: "folder")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
