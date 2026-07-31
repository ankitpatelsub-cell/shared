import Foundation
import SwiftData

enum HostAuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password: return "Password"
        case .privateKey: return "SSH Key"
        case .none: return "None"
        }
    }
}

@Model
final class Host {
    @Attribute(.unique) var id: UUID
    var label: String
    var address: String
    var port: Int
    var username: String
    var authMethodRaw: String
    /// Foreign key into the Identity store. Nil unless authMethod == .privateKey.
    var identityID: UUID?
    var startupSnippet: String?
    var groupName: String?
    var tags: [String]
    var themeName: String?
    var createdAt: Date

    var authMethod: HostAuthMethod {
        get { HostAuthMethod(rawValue: authMethodRaw) ?? .password }
        set { authMethodRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        label: String,
        address: String,
        port: Int = 22,
        username: String,
        authMethod: HostAuthMethod = .password,
        identityID: UUID? = nil,
        startupSnippet: String? = nil,
        groupName: String? = nil,
        tags: [String] = [],
        themeName: String? = nil
    ) {
        self.id = id
        self.label = label
        self.address = address
        self.port = port
        self.username = username
        self.authMethodRaw = authMethod.rawValue
        self.identityID = identityID
        self.startupSnippet = startupSnippet
        self.groupName = groupName
        self.tags = tags
        self.themeName = themeName
        self.createdAt = Date()
    }

    var connectionSubtitle: String {
        "\(username)@\(address):\(port)"
    }
}
