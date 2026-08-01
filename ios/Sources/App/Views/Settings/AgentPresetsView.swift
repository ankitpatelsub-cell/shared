import SwiftUI

struct AgentPresetsView: View {
    @EnvironmentObject private var store: AgentPresetStore
    @State private var editing: AgentPreset?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(store.presets) { preset in
                Button { editing = preset } label: {
                    HStack {
                        Label(preset.name, systemImage: preset.tool.icon)
                        Spacer()
                        Text(preset.tool.title).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: store.delete)
        }
        .navigationTitle("Agent Presets")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { AgentPresetEditor(preset: $0) }
        .sheet(isPresented: $adding) {
            AgentPresetEditor(preset: AgentPreset(name: "New Preset", tool: .codex))
        }
    }
}

private struct AgentPresetEditor: View {
    @EnvironmentObject private var store: AgentPresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var preset: AgentPreset
    @State private var argumentsText: String
    @State private var environmentText: String

    init(preset: AgentPreset) {
        _preset = State(initialValue: preset)
        _argumentsText = State(initialValue: preset.arguments.joined(separator: " "))
        _environmentText = State(initialValue: preset.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Preset name", text: $preset.name)
                Picker("Tool", selection: $preset.tool) {
                    ForEach(AgentTool.allCases) { Text($0.title).tag($0) }
                }
                Section("Launch") {
                    TextField("Arguments", text: $argumentsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Startup prompt", text: $preset.startupPrompt, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Environment") {
                    TextField("NAME=value, one per line", text: $environmentText, axis: .vertical)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3...10)
                    Text("Environment variable names are validated before launch. Values remain in app preferences, so do not put secrets here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Agent Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        preset.arguments = parseArguments(argumentsText)
                        preset.environment = parseEnvironment(environmentText)
                        store.save(preset)
                        dismiss()
                    }
                }
            }
        }
    }

    private func parseEnvironment(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }

    private func parseArguments(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in text {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\" && quote != "'" {
                escaping = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaping { current.append("\\") }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
