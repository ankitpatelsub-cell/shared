import SwiftUI
import SwiftData

struct HostEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var identities: [Identity]

    let host: Host?

    @State private var label = ""
    @State private var address = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: HostAuthMethod = .password
    @State private var password = ""
    @State private var selectedIdentityID: UUID?
    @State private var startupSnippet = ""
    @State private var groupName = ""
    @State private var themeName = ""
    @State private var errorMessage: String?

    init(host: Host?) {
        self.host = host
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Label", text: $label)
                    TextField("Address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Group (optional)", text: $groupName)
                }

                Section("Auth") {
                    Picker("Method", selection: $authMethod) {
                        ForEach(HostAuthMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    if authMethod == .password {
                        SecureField("Password", text: $password)
                    } else if authMethod == .privateKey {
                        Picker("SSH Key", selection: $selectedIdentityID) {
                            Text("None").tag(UUID?.none)
                            ForEach(identities) { identity in
                                Text(identity.label).tag(Optional(identity.id))
                            }
                        }
                    }
                }

                Section("Startup Snippet") {
                    TextField("Command to run on connect (optional)", text: $startupSnippet, axis: .vertical)
                }

                Section("Appearance") {
                    TextField("Theme override (optional)", text: $themeName)
                }
            }
            .navigationTitle(host == nil ? "Add Host" : "Edit Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(label.isEmpty || address.isEmpty || username.isEmpty)
                }
            }
            .onAppear(perform: populateFromExistingHost)
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func populateFromExistingHost() {
        guard let host else { return }
        label = host.label
        address = host.address
        port = String(host.port)
        username = host.username
        authMethod = host.authMethod
        selectedIdentityID = host.identityID
        startupSnippet = host.startupSnippet ?? ""
        groupName = host.groupName ?? ""
        themeName = host.themeName ?? ""
        password = (try? KeychainService.password(for: host)) ?? ""
    }

    private func save() {
        let portNumber = Int(port) ?? 22
        let target = host ?? Host(
            label: label,
            address: address,
            port: portNumber,
            username: username
        )

        target.label = label
        target.address = address
        target.port = portNumber
        target.username = username
        target.authMethod = authMethod
        target.identityID = authMethod == .privateKey ? selectedIdentityID : nil
        target.startupSnippet = startupSnippet.isEmpty ? nil : startupSnippet
        target.groupName = groupName.isEmpty ? nil : groupName
        target.themeName = themeName.isEmpty ? nil : themeName

        if host == nil {
            modelContext.insert(target)
        }

        do {
            if authMethod == .password, !password.isEmpty {
                try KeychainService.setPassword(password, for: target)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
