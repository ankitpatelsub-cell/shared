import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var recentSessions: [WorkspaceSession] = []

    private let defaultsKey = "workspaceSessions.v1"
    private var notifiedFinishedSessions: Set<UUID> = []
    private var observedRunningSessions: Set<UUID> = []

    init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([WorkspaceSession].self, from: data) else { return }
        recentSessions = decoded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    @discardableResult
    func session(host: Host, path: String, tool: AgentTool) -> WorkspaceSession {
        let key = Self.tmuxName(hostID: host.id, path: path, tool: tool)
        if let index = recentSessions.firstIndex(where: { $0.tmuxName == key && $0.hostID == host.id }) {
            recentSessions[index].lastOpenedAt = Date()
            let existing = recentSessions.remove(at: index)
            recentSessions.insert(existing, at: 0)
            save()
            return existing
        }

        let value = WorkspaceSession(
            id: UUID(), hostID: host.id, hostLabel: host.label, path: path,
            tool: tool, tmuxName: key, lastOpenedAt: Date(), customName: nil, pinnedAt: nil,
            arguments: nil, environment: nil, startupPrompt: nil
        )
        recentSessions.insert(value, at: 0)
        recentSessions = Array(recentSessions.prefix(30))
        save()
        return value
    }

    func session(host: Host, path: String, preset: AgentPreset) -> WorkspaceSession {
        var value = session(host: host, path: path, tool: preset.tool)
        guard let index = recentSessions.firstIndex(where: { $0.id == value.id }) else { return value }
        recentSessions[index].customName = preset.name
        recentSessions[index].arguments = preset.arguments
        recentSessions[index].environment = preset.environment
        recentSessions[index].startupPrompt = preset.startupPrompt
        value = recentSessions[index]
        save()
        return value
    }

    func remove(_ session: WorkspaceSession) {
        recentSessions.removeAll { $0.id == session.id }
        save()
    }

    func rename(_ session: WorkspaceSession, to name: String) {
        guard let index = recentSessions.firstIndex(where: { $0.id == session.id }) else { return }
        recentSessions[index].customName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func togglePin(_ session: WorkspaceSession) {
        guard let index = recentSessions.firstIndex(where: { $0.id == session.id }) else { return }
        recentSessions[index].pinnedAt = recentSessions[index].pinnedAt == nil ? Date() : nil
        sortSessions()
        save()
    }

    func duplicate(_ session: WorkspaceSession) -> WorkspaceSession {
        let copy = WorkspaceSession(
            id: UUID(), hostID: session.hostID, hostLabel: session.hostLabel,
            path: session.path, tool: session.tool,
            tmuxName: "\(session.tmuxName)-\(UUID().uuidString.prefix(6).lowercased())",
            lastOpenedAt: Date(), customName: "\(session.displayName) Copy", pinnedAt: nil,
            arguments: session.arguments, environment: session.environment, startupPrompt: session.startupPrompt
        )
        recentSessions.insert(copy, at: 0)
        save()
        return copy
    }

    func terminate(_ session: WorkspaceSession) async throws {
        _ = try await RemoteCommandService.shared.run(
            hostID: session.hostID,
            command: "tmux kill-session -t \(ProjectDashboardViewModel.quote(session.tmuxName))"
        )
    }

    private func sortSessions() {
        recentSessions.sort {
            if ($0.pinnedAt != nil) != ($1.pinnedAt != nil) { return $0.pinnedAt != nil }
            return $0.lastOpenedAt > $1.lastOpenedAt
        }
    }

    func checkForCompletions() async {
        guard UserDefaults.standard.bool(forKey: "dev.termvault.settings.agentNotifications") else { return }
        for workspace in recentSessions where workspace.tool.executable != nil && !notifiedFinishedSessions.contains(workspace.id) {
            let name = ProjectDashboardViewModel.quote(workspace.tmuxName)
            guard let output = try? await RemoteCommandService.shared.run(
                hostID: workspace.hostID,
                command: "tmux display-message -p -t \(name) '#{pane_current_command}' 2>/dev/null || true"
            ), !output.isEmpty else { continue }
            if output == workspace.tool.executable {
                observedRunningSessions.insert(workspace.id)
            } else if observedRunningSessions.contains(workspace.id) {
                notifiedFinishedSessions.insert(workspace.id)
                await NotificationService.agentFinished(workspace)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recentSessions) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func tmuxName(hostID: UUID, path: String, tool: AgentTool) -> String {
        var hash: UInt64 = 5381
        for byte in "\(hostID.uuidString)|\(path)|\(tool.rawValue)".utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return "termvault-\(tool.rawValue)-\(String(hash, radix: 16))"
    }
}
