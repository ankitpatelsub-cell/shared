import SwiftUI
import SwiftData

struct GenerateKeyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: IdentityManagerViewModel

    @State private var label = ""
    @State private var keyType: IdentityKeyType = .ed25519
    @State private var passphrase = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label)
                    Picker("Type", selection: $keyType) {
                        ForEach(IdentityKeyType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    SecureField("Passphrase (optional)", text: $passphrase)
                }
                if let pem = viewModel.lastGeneratedPrivateKeyPEM {
                    Section("Generated") {
                        Text(pem)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Generate Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        viewModel.generateKey(
                            label: label,
                            type: keyType,
                            passphrase: passphrase.isEmpty ? nil : passphrase,
                            context: modelContext
                        )
                        if viewModel.errorMessage == nil { dismiss() }
                    }
                    .disabled(label.isEmpty)
                }
            }
        }
    }
}
