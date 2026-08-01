import SwiftUI

struct GitHubSettingsView: View {
    @State private var token = ""
    @State private var account: String?
    @State private var statusMessage: String?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section("Personal Access Token") {
                SecureField("github_pat_…", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save and Verify") { Task { await saveAndVerify() } }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChecking)
                if let account {
                    Label("Connected as \(account)", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                }
                if let statusMessage { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
                Button("Remove Token", role: .destructive) {
                    try? KeychainService.deleteGitHubToken()
                    token = ""
                    account = nil
                    statusMessage = "Token removed from the Keychain."
                }
            }
            Section("Recommended Permissions") {
                Text("Use a fine-grained token limited to the repositories you need. Grant Contents read access, Issues read/write, and Pull requests read/write only when you want those actions.")
                    .font(.caption)
            }
        }
        .navigationTitle("GitHub")
        .task { await verifyStoredToken() }
    }

    private func saveAndVerify() async {
        isChecking = true
        defer { isChecking = false }
        do {
            try KeychainService.setGitHubToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
            let user = try await GitHubService.shared.validateToken()
            account = user.login
            token = ""
            statusMessage = "Verified. The token is stored only in the iOS Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func verifyStoredToken() async {
        guard (try? KeychainService.githubToken()) != nil else { return }
        do { account = (try await GitHubService.shared.validateToken()).login }
        catch { statusMessage = error.localizedDescription }
    }
}
