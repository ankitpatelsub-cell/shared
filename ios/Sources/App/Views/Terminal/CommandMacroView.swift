import SwiftUI

struct CommandMacroView: View {
    @ObservedObject private var store = CommandMacroStore.shared
    let onExecute: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var editingMacro: CommandMacro?

    var body: some View {
        NavigationStack {
            if store.macros.isEmpty {
                ContentUnavailableView(
                    "No Macros",
                    systemImage: "hammer",
                    description: Text("Create command macros for quick execution")
                )
                .navigationTitle("Command Macros")
            } else {
                List(store.macros) { macro in
                    Button {
                        onExecute(macro.commands)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: macro.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(macro.name)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)

                                Text(macro.displayCommands)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if let description = macro.description {
                                    Text(description)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteMacro(macro)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editingMacro = macro
                            showingEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
                .navigationTitle("Command Macros")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            editingMacro = nil
                            showingEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CommandMacroEditorView(macro: editingMacro, isPresented: $showingEditor)
        }
    }
}

struct CommandMacroEditorView: View {
    let macro: CommandMacro?
    @Binding var isPresented: Bool
    @ObservedObject private var store = CommandMacroStore.shared
    @State private var name = ""
    @State private var icon = "hammer"
    @State private var description = ""
    @State private var commandText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Macro Name", text: $name)
                    TextField("Description", text: $description)
                }

                Section("Icon") {
                    HStack {
                        Image(systemName: icon)
                            .foregroundStyle(.blue)
                            .font(.headline)

                        Picker("Icon", selection: $icon) {
                            ForEach(["hammer", "play", "gearshape", "wrench", "folder", "arrow.up.square", "eraser", "info.circle"], id: \.self) { iconName in
                                Label(iconName, systemImage: iconName)
                                    .tag(iconName)
                            }
                        }
                    }
                }

                Section("Commands") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("One command per line")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $commandText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 120)
                            .cornerRadius(6)
                    }
                }
            }
            .navigationTitle(macro != nil ? "Edit Macro" : "New Macro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveMacro()
                        isPresented = false
                    }
                    .disabled(name.isEmpty || commandText.isEmpty)
                }
            }
            .onAppear {
                if let macro = macro {
                    name = macro.name
                    icon = macro.icon
                    description = macro.description ?? ""
                    commandText = macro.commands.joined(separator: "\n")
                }
            }
        }
    }

    private func saveMacro() {
        let commands = commandText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let commands_with_newline = commands.map { $0.hasSuffix("\n") ? $0 : $0 + "\n" }

        if let macro = macro {
            let updated = CommandMacro(
                id: macro.id,
                name: name,
                commands: commands_with_newline,
                icon: icon,
                description: description.isEmpty ? nil : description
            )
            store.updateMacro(updated)
        } else {
            let newMacro = CommandMacro(
                id: UUID(),
                name: name,
                commands: commands_with_newline,
                icon: icon,
                description: description.isEmpty ? nil : description
            )
            store.addMacro(newMacro)
        }
    }
}
