import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportKeyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: IdentityManagerViewModel

    @State private var label = ""
    @State private var keyType: IdentityKeyType = .ed25519
    @State private var privateKeyPEM = ""
    @State private var publicKeyLine = ""
    @State private var passphrase = ""
    @State private var showingFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $label)
                Picker("Type", selection: $keyType) {
                    ForEach(IdentityKeyType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Section("Private Key") {
                    TextEditor(text: $privateKeyPEM)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                    Button("Import from file…") { showingFileImporter = true }
                }
                Section("Public Key (.pub)") {
                    TextEditor(text: $publicKeyLine)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 60)
                }
                SecureField("Passphrase (optional)", text: $passphrase)
            }
            .navigationTitle("Import Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        viewModel.importKey(
                            label: label,
                            type: keyType,
                            privateKeyPEM: privateKeyPEM,
                            publicKeyLine: publicKeyLine,
                            passphrase: passphrase.isEmpty ? nil : passphrase,
                            context: modelContext
                        )
                        dismiss()
                    }
                    .disabled(label.isEmpty || privateKeyPEM.isEmpty)
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result, let data = try? Data(contentsOf: url) {
                    privateKeyPEM = String(decoding: data, as: UTF8.self)
                }
            }
        }
    }
}
