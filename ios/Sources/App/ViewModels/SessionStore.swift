import Foundation

/// Holds every currently-open terminal session (one per connected host),
/// independent of navigation — this is what lets a user flip between
/// session tabs without SwiftUI tearing the connection down.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [TerminalViewModel] = []
    @Published var activeSessionID: UUID?

    @discardableResult
    func open(host: Host, identity: Identity?) -> TerminalViewModel {
        if let existing = sessions.first(where: { $0.host.id == host.id && $0.activeWorkspace == nil }) {
            activeSessionID = existing.id
            return existing
        }
        let viewModel = TerminalViewModel(host: host, identity: identity)
        sessions.append(viewModel)
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
        let viewModel = TerminalViewModel(host: host, identity: identity)
        sessions.append(viewModel)
        activeSessionID = viewModel.id
        Task { await viewModel.attach(to: workspace) }
        return viewModel
    }

    func close(_ session: TerminalViewModel) {
        session.disconnect()
        sessions.removeAll { $0.id == session.id }
        if activeSessionID == session.id {
            activeSessionID = sessions.last?.id
        }
    }

    var activeSession: TerminalViewModel? {
        sessions.first { $0.id == activeSessionID }
    }
}
