import Foundation

@MainActor
final class AgentPresetStore: ObservableObject {
    @Published private(set) var presets: [AgentPreset] = []
    private let key = "dev.termvault.agentPresets.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let values = try? JSONDecoder().decode([AgentPreset].self, from: data) {
            presets = values
        } else {
            presets = [
                AgentPreset(name: "Codex", tool: .codex),
                AgentPreset(name: "Claude", tool: .claude),
                AgentPreset(name: "Hermes", tool: .hermes),
                AgentPreset(name: "Project Shell", tool: .shell),
            ]
        }
    }

    func save(_ preset: AgentPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) { presets[index] = preset }
        else { presets.append(preset) }
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { presets.remove(at: index) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: key) }
    }
}
