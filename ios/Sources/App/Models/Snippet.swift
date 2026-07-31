import Foundation
import SwiftData

@Model
final class Snippet {
    @Attribute(.unique) var id: UUID
    var name: String
    var command: String
    var runOnConnect: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        runOnConnect: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.runOnConnect = runOnConnect
        self.createdAt = Date()
    }
}
