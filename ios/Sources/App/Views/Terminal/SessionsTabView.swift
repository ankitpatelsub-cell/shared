import SwiftUI
import SwiftData

/// Switch between open sessions via the tab strip (2+ sessions), the
/// "Switch Session" menu, or Cmd+1…9 on an external keyboard. No swipe
/// gesture or paged TabView — see `sessionPager` for why.
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
            .background(keyboardShortcuts)
        }
    }

    /// External-keyboard session switching (Cmd+1…9) and closing (Cmd+W) —
    /// invisible buttons are the standard SwiftUI way to attach a global
    /// `.keyboardShortcut` that isn't tied to a visible control. Cmd+K for
    /// the command palette already exists on the terminal view itself;
    /// these mirror that same "hardware keyboard on iPad" affordance.
    @ViewBuilder
    private var keyboardShortcuts: some View {
        ForEach(Array(sessionStore.sessions.prefix(9).enumerated()), id: \.element.id) { index, session in
            Button("") { sessionStore.activeSessionID = session.id }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
        if let active = sessionStore.activeSession {
            Button("") { sessionStore.close(active) }
                .keyboardShortcut("w", modifiers: .command)
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

    // `.tabViewStyle(.page(...))` was tried here with `indexDisplayMode`
    // pinned to `.never` after it first crashed opening SFTP browse
    // (UIKitPageIndexView hit an out-of-bounds array read when the session
    // count changed mid-update). That crash recurred with the identical
    // signature regardless — on this iOS build, SwiftUI's `.page` style
    // apparently still drives the same page-index bookkeeping internally
    // even when the dots aren't drawn, so it's still exposed to a
    // dynamically changing `ForEach`. Switching to a plain `ZStack` that
    // shows/hides each session removes `UIKitPageIndexView` (and this
    // whole crash class) from the picture entirely, instead of continuing
    // to tune a parameter of the thing that keeps crashing. Sessions stay
    // mounted (so a backgrounded terminal keeps receiving output) exactly
    // as the TabView pager did; only the swipe-to-switch gesture is gone,
    // since the tab strip above and the "Switch Session" menu already
    // cover switching without it.
    private var sessionPager: some View {
        ZStack {
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
                .opacity(session.id == sessionStore.activeSessionID ? 1 : 0)
                .allowsHitTesting(session.id == sessionStore.activeSessionID)
                .accessibilityHidden(session.id != sessionStore.activeSessionID)
            }
        }
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
