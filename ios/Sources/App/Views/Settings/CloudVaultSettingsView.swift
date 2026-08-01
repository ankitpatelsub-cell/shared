import SwiftData
import SwiftUI

struct CloudVaultSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [Host]
    @Query private var identities: [Identity]
    @Query private var snippets: [Snippet]
    @State private var email = ""
    @State private var password = ""
    @State private var isAuthenticated = false
    @State private var isWorking = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                Label("End-to-End Encrypted", systemImage: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Hosts, passwords, private keys, and snippets are encrypted on this device. The VPS stores only ciphertext and cannot read your vault.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Vault password (12+ characters)", text: $password)
                    .textContentType(.password)
                if isAuthenticated {
                    Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Sign Out", role: .destructive) {
                        try? KeychainService.deleteCloudToken()
                        isAuthenticated = false
                        password = ""
                    }
                } else {
                    HStack {
                        Button("Sign In") { Task { await authenticate(register: false) } }
                        Spacer()
                        Button("Create Account") { Task { await authenticate(register: true) } }
                    }
                    .disabled(email.isEmpty || password.count < 12 || isWorking)
                }
            }

            if isAuthenticated {
                Section("Vault") {
                    Button {
                        Task { await upload() }
                    } label: {
                        Label("Upload This Device", systemImage: "arrow.up.circle")
                    }
                    Button {
                        Task { await restore() }
                    } label: {
                        Label("Restore and Merge", systemImage: "arrow.down.circle")
                    }
                    Text("Restore merges matching records by ID and does not delete local-only records.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isWorking { Section { ProgressView("Syncing encrypted vault…") } }
            if let statusMessage { Section { Text(statusMessage).font(.footnote) } }
        }
        .navigationTitle("Cloud Vault")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isAuthenticated = (try? KeychainService.cloudToken()) != nil }
    }

    private func authenticate(register: Bool) async {
        isWorking = true; defer { isWorking = false }
        do {
            try await CloudVaultService.shared.authenticate(email: email, password: password, register: register)
            isAuthenticated = true
            statusMessage = register ? "Account created. Upload this device to create the vault." : "Signed in successfully."
        } catch { statusMessage = error.localizedDescription }
    }

    private func upload() async {
        guard !password.isEmpty else { statusMessage = "Enter your vault password first."; return }
        isWorking = true; defer { isWorking = false }
        do {
            let revision = try await CloudVaultService.shared.upload(
                hosts: hosts, identities: identities, snippets: snippets, password: password
            )
            statusMessage = "Encrypted vault uploaded (revision \(revision))."
        } catch { statusMessage = error.localizedDescription }
    }

    private func restore() async {
        guard !password.isEmpty else { statusMessage = "Enter your vault password first."; return }
        isWorking = true; defer { isWorking = false }
        do {
            let revision = try await CloudVaultService.shared.restore(into: modelContext, password: password)
            statusMessage = "Vault revision \(revision) restored and merged."
        } catch { statusMessage = error.localizedDescription }
    }
}
