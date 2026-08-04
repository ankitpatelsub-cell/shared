import Foundation
import SwiftUI
import SwiftData

@Model
final class WorkspaceProject {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    var details: String?
    var icon: String = "folder"
    var color: String = "blue"
    var createdAt: Date = Date()
    var workspaceIDs: [UUID] = []

    init(name: String, description: String? = nil, icon: String = "folder", color: String = "blue") {
        self.name = name
        self.details = description
        self.icon = icon
        self.color = color
    }

    var displayColor: Color {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        default: return .gray
        }
    }

    static let colors = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray"]
    static let icons = ["folder", "star", "bolt", "gear", "database", "cube", "hammer", "wrench"]
}
