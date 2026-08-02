import Foundation

/// Holds every currently-open terminal session (one per connected host),
/// independent of navigation — this is what lets a user flip between
/// session tabs without SwiftUI tearing the connection down.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [TerminalViewModel] = []
    @Published var activeSessionID: UUID?
    var connectionSnippetCommands: [String] = []
    private var connectionHosts: [Host] = []
    private var connectionIdentities: [Identity] = []
    
    func configureConnectionCatalog(hosts: [Host], identities: [Identity]) {
        connectionHosts = hosts
        connectionIdentities = identities
    }
    
    private func buildJumpHosts(for host: Host) -> [SSHJumpHop] {
        var hops: [SSHJumpHop] = []
        var currentJumpHostID = host.jumpHostID
        
        // Follow the chain of jump hosts
        while let jumpHostID = currentJumpHostID,
              let jumpHost = connectionHosts.first(where: { $0.id == jumpHostID }) {
            let jumpIdentity = connectionIdentities.first { $0.id == jumpHost.identityID }
            hops.append(SSHJumpHop(host: jumpHost, identity: jumpIdentity))
            currentJumpHostID = jumpHost.jumpHostID
        }
        
        return hops
    }

    private let preferencesKey = "dev.termvault.sessionPreferences"

    private struct SessionPreference: Codable {
        var title: String?
        var pinned: Bool
        var order: Int
    }

    @discardableResult
    func open(host: Host, identity: Identity?) -> TerminalViewModel {
        if let existing = sessions.first(where: { $0.host.id == host.id && $0.activeWorkspace == nil }) {
            activeSessionID = existing.id
            return existing
        }
        let jumpHosts = buildJumpHosts(for: host)
        let viewModel = TerminalViewModel(host: host, identity: identity, jumpHosts: jumpHosts)
        viewModel.connectionSnippetCommands = connectionSnippetCommands
        applyPreference(to: viewModel)
        sessions.append(viewModel)
        sortSessions()
        activeSessionID = viewModel.id
        Task { await viewModel.connect() }
        return viewModel
    }

    @discardableResult
    func open(workspace: WorkspaceSession, host: Host, identity: Identity?) -> TerminalViewModel {
        if let existing = sessions.first(where: { $0.activeWorkspace?.id == workspace.id }) {
            activeSessionID = existing.id
            return existing
        }
        let jumpHosts = buildJumpHosts(for: host)
        let viewModel = TerminalViewModel(
            host: host,
            identity: identity,
            jumpHosts: jumpHosts,
            persistenceKey: "workspace:\(workspace.id.uuidString)"
        )
        viewModel.connectionSnippetCommands = connectionSnippetCommands
        applyPreference(to: viewModel)
        sessions.append(viewModel)
        sortSessions()
        activeSessionID = viewModel.id
        Task { await viewModel.attach(to: workspace) }
        return viewModel
    }

    func close(_ session: TerminalViewModel) {
        SessionHistoryStore.shared.record(session)
        session.disconnect()
        sessions.removeAll { $0.id == session.id }
        if activeSessionID == session.id {
            activeSessionID = sessions.last?.id
        }
    }

    func move(_ session: TerminalViewModel, by offset: Int) {
        guard let source = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let destination = min(max(0, source + offset), sessions.count - 1)
        guard source != destination else { return }
        let item = sessions.remove(at: source)
        sessions.insert(item, at: destination)
        savePreferences()
    }

    func rename(_ session: TerminalViewModel, to title: String?) {
        session.customTitle = title
        savePreferences()
    }

    func togglePin(_ session: TerminalViewModel) {
        session.isPinned.toggle()
        if session.isPinned { move(session, by: -sessions.count) }
        sortSessions()
        savePreferences()
    }

    private func applyPreference(to session: TerminalViewModel) {
        guard let preference = loadPreferences()[session.persistenceKey] else { return }
        session.customTitle = preference.title
        session.isPinned = preference.pinned
    }

    private func sortSessions() {
        let preferences = loadPreferences()
        sessions.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return (preferences[$0.persistenceKey]?.order ?? Int.max) <
                (preferences[$1.persistenceKey]?.order ?? Int.max)
        }
    }

    private func loadPreferences() -> [String: SessionPreference] {
        guard let data = UserDefaults.standard.data(forKey: preferencesKey),
              let value = try? JSONDecoder().decode([String: SessionPreference].self, from: data) else { return [:] }
        return value
    }

    private func savePreferences() {
        var preferences = loadPreferences()
        for (index, session) in sessions.enumerated() {
            preferences[session.persistenceKey] = SessionPreference(
                title: session.customTitle,
                pinned: session.isPinned,
                order: index
            )
        }
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
    }

    var activeSession: TerminalViewModel? {
        sessions.first { $0.id == activeSessionID }
    }
}
