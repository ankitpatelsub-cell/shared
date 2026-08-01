import Foundation

enum AgentTool: String, CaseIterable, Codable, Identifiable {
    case codex
    case claude
    case hermes
    case shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .hermes: return "Hermes"
        case .shell: return "Shell"
        }
    }

    var icon: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "sparkles"
        case .hermes: return "bolt.fill"
        case .shell: return "terminal"
        }
    }

    var executable: String? { self == .shell ? nil : rawValue }
}

struct WorkspaceSession: Codable, Identifiable, Equatable {
    let id: UUID
    let hostID: UUID
    let hostLabel: String
    let path: String
    let tool: AgentTool
    let tmuxName: String
    var lastOpenedAt: Date
    var customName: String?
    var pinnedAt: Date?
    var arguments: [String]?
    var environment: [String: String]?
    var startupPrompt: String?

    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        let folder = (path as NSString).lastPathComponent
        return folder.isEmpty ? path : folder
    }
}

struct AgentPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var tool: AgentTool
    var arguments: [String]
    var environment: [String: String]
    var startupPrompt: String

    init(id: UUID = UUID(), name: String, tool: AgentTool, arguments: [String] = [], environment: [String: String] = [:], startupPrompt: String = "") {
        self.id = id
        self.name = name
        self.tool = tool
        self.arguments = arguments
        self.environment = environment
        self.startupPrompt = startupPrompt
    }
}
