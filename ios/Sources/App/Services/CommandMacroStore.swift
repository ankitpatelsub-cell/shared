import Foundation

struct CommandMacro: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let commands: [String] // List of commands to execute in sequence
    let icon: String // SF symbol name
    let description: String?
    let delay: Double = 0.5 // Delay between commands in seconds

    var displayCommands: String {
        commands.joined(separator: " → ")
    }
}

@MainActor
final class CommandMacroStore: ObservableObject {
    static let shared = CommandMacroStore()
    @Published private(set) var macros: [CommandMacro] = []

    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("command-macros.json")

        // Load persisted macros
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([CommandMacro].self, from: data) {
            macros = decoded
        } else {
            // Add default macros
            addDefaultMacros()
        }
    }

    func addMacro(_ macro: CommandMacro) {
        guard !macros.contains(where: { $0.name == macro.name }) else { return }
        macros.append(macro)
        save()
    }

    func deleteMacro(_ macro: CommandMacro) {
        macros.removeAll { $0.id == macro.id }
        save()
    }

    func updateMacro(_ macro: CommandMacro) {
        guard let index = macros.firstIndex(where: { $0.id == macro.id }) else { return }
        macros[index] = macro
        save()
    }

    private func addDefaultMacros() {
        let defaults = [
            CommandMacro(
                id: UUID(),
                name: "Clear Screen",
                commands: ["clear"],
                icon: "eraser",
                description: "Clear terminal screen"
            ),
            CommandMacro(
                id: UUID(),
                name: "System Info",
                commands: ["uname -a", "whoami"],
                icon: "info.circle",
                description: "Show system information"
            ),
            CommandMacro(
                id: UUID(),
                name: "List Files",
                commands: ["ls -lah"],
                icon: "folder",
                description: "List all files with details"
            ),
            CommandMacro(
                id: UUID(),
                name: "Git Status",
                commands: ["git status"],
                icon: "square.and.pencil",
                description: "Check git status"
            ),
            CommandMacro(
                id: UUID(),
                name: "Update System",
                commands: ["sudo apt update", "sudo apt upgrade -y"],
                icon: "arrow.up.square",
                description: "Update system packages"
            )
        ]

        macros = defaults
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(macros) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
