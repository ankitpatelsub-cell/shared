import Foundation
import Citadel

enum OpenSession: Identifiable {
    case terminal(TerminalViewModel)
    case sftp(SFTPBrowserViewModel)

    var id: UUID {
        switch self {
        case .terminal(let vm): return vm.id
        case .sftp(let vm): return vm.id
        }
    }

    var terminal: TerminalViewModel? {
        if case .terminal(let vm) = self { return vm }
        return nil
    }

    var sftp: SFTPBrowserViewModel? {
        if case .sftp(let vm) = self { return vm }
        return nil
    }

    var host: Host {
        switch self {
        case .terminal(let vm): return vm.host
        case .sftp(let vm): return vm.host
        }
    }

    var displayTitle: String {
        switch self {
        case .terminal(let vm):
            if let customTitle = vm.customTitle, !customTitle.isEmpty { return customTitle }
            return vm.activeWorkspace?.displayName ?? vm.host.label
        case .sftp(let vm):
            if let customTitle = vm.customTitle, !customTitle.isEmpty { return customTitle }
            return "\(vm.host.label) Files"
        }
    }

    var isPinned: Bool {
        switch self {
        case .terminal(let vm): return vm.isPinned
        case .sftp(let vm): return vm.isPinned
        }
    }

    var persistenceKey: String {
        switch self {
        case .terminal(let vm): return vm.persistenceKey
        case .sftp(let vm): return vm.persistenceKey
        }
    }

    var customTitle: String? {
        switch self {
        case .terminal(let vm): return vm.customTitle
        case .sftp(let vm): return vm.customTitle
        }
    }
}

/// Holds every currently-open terminal or SFTP browser session, independent
/// of navigation — this is what lets a user flip between session tabs
/// without SwiftUI tearing the connection down.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [OpenSession] = []
    @Published var activeSessionID: UUID?
    var connectionSnippetCommands: [String] = []
    private var connectionHosts: [Host] = []
    private var connectionIdentities: [Identity] = []
    private let preferencesKey = "dev.termvault.sessionPreferences"

    private struct SessionPreference: Codable {
        var title: String?
        var pinned: Bool
        var order: Int
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

    func configureConnectionCatalog(hosts: [Host], identities: [Identity]) {
        connectionHosts = hosts
        connectionIdentities = identities
    }

    @discardableResult
    func open(host: Host, identity: Identity?) -> TerminalViewModel {
        let jumpHosts = buildJumpHosts(for: host)
        let viewModel = TerminalViewModel(host: host, identity: identity, jumpHosts: jumpHosts)
        viewModel.connectionSnippetCommands = connectionSnippetCommands
        applyPreference(to: viewModel)
        sessions.append(.terminal(viewModel))
        sortSessions()
        activeSessionID = viewModel.id
        Task { await viewModel.connect() }
        return viewModel
    }

    @discardableResult
    func openNewTab(for host: Host, identity: Identity?) -> TerminalViewModel {
        // Always create a new tab for the same host
        let jumpHosts = buildJumpHosts(for: host)
        let viewModel = TerminalViewModel(host: host, identity: identity, jumpHosts: jumpHosts)
        viewModel.connectionSnippetCommands = connectionSnippetCommands
        applyPreference(to: viewModel)
        sessions.append(.terminal(viewModel))
        sortSessions()
        activeSessionID = viewModel.id
        Task { await viewModel.connect() }
        return viewModel
    }

    @discardableResult
    func open(workspace: WorkspaceSession, host: Host, identity: Identity?) -> TerminalViewModel {
        if let existing = terminalSessions.first(where: { $0.activeWorkspace?.id == workspace.id }) {
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
        sessions.append(.terminal(viewModel))
        sortSessions()
        activeSessionID = viewModel.id
        Task { await viewModel.attach(to: workspace) }
        return viewModel
    }

    @discardableResult
    func openSFTP(host: Host, connectionID: UUID, sshClient: SSHClient) -> SFTPBrowserViewModel {
        let viewModel = SFTPBrowserViewModel(host: host, connectionID: connectionID, sshClient: sshClient)
        applyPreference(to: viewModel)
        sessions.append(.sftp(viewModel))
        sortSessions()
        activeSessionID = viewModel.id
        Task { await viewModel.load() }
        return viewModel
    }

    var terminalSessions: [TerminalViewModel] {
        sessions.compactMap { $0.terminal }
    }

    func close(_ session: OpenSession) {
        switch session {
        case .terminal(let vm):
            SessionHistoryStore.shared.record(vm)
            vm.disconnect()
        case .sftp(let vm):
            vm.cancelAllTransfers()
        }
        sessions.removeAll { $0.id == session.id }
        if activeSessionID == session.id {
            activeSessionID = sessions.last?.id
        }
    }

    func close(_ session: TerminalViewModel) {
        close(.terminal(session))
    }

    func move(_ session: OpenSession, by offset: Int) {
        guard let source = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let destination = min(max(0, source + offset), sessions.count - 1)
        guard source != destination else { return }
        let item = sessions.remove(at: source)
        sessions.insert(item, at: destination)
        savePreferences()
    }

    func move(_ session: TerminalViewModel, by offset: Int) {
        move(.terminal(session), by: offset)
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

    private func applyPreference(to session: SFTPBrowserViewModel) {
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

    var activeSession: OpenSession? {
        sessions.first { $0.id == activeSessionID }
    }
}
