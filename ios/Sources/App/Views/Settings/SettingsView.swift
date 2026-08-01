import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lockService: BiometricLockService
    @AppStorage("dev.termvault.settings.fontSize") private var fontSize: Double = 14
    @AppStorage("dev.termvault.settings.iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("dev.termvault.settings.agentNotifications") private var agentNotifications = false
    @AppStorage("dev.termvault.settings.pasteProtection") private var pasteProtection = true

    var body: some View {
        NavigationStack {
            Form {
                Section("App Lock") {
                    Toggle("Face ID / Passcode Lock", isOn: $lockService.isBiometricLockEnabled)
                }
                Section("Terminal") {
                    Stepper(value: $fontSize, in: 10...24) {
                        Text("Font Size: \(Int(fontSize))")
                    }
                    Toggle("Confirm Multiline Paste", isOn: $pasteProtection)
                }
                Section("Agents") {
                    NavigationLink("Agent Presets") { AgentPresetsView() }
                    Toggle("Completion Notifications", isOn: $agentNotifications)
                        .onChange(of: agentNotifications) { _, enabled in
                            if enabled {
                                Task {
                                    if !await NotificationService.requestAuthorization() {
                                        agentNotifications = false
                                    }
                                }
                            }
                        }
                }
                Section("Integrations") {
                    NavigationLink {
                        GitHubSettingsView()
                    } label: {
                        Label("GitHub Personal Access Token", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                Section("Sync") {
                    Toggle("iCloud Sync (encrypted)", isOn: $iCloudSyncEnabled)
                    if iCloudSyncEnabled {
                        Text("Hosts would be encrypted client-side before syncing via CloudKit's private database. Not yet wired to a CloudKit container — see spec section 6 and README.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink("About") { AboutView() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
