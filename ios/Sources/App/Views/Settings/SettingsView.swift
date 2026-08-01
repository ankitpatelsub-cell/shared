import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lockService: BiometricLockService
    @AppStorage("dev.termvault.settings.fontSize") private var fontSize: Double = 14
    @AppStorage("dev.termvault.settings.iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("dev.termvault.settings.agentNotifications") private var agentNotifications = false
    @AppStorage("dev.termvault.settings.pasteProtection") private var pasteProtection = true
    @AppStorage("dev.termvault.settings.appearance") private var appearance = "system"
    @AppStorage("dev.termvault.settings.accent") private var accent = "blue"
    @AppStorage("dev.termvault.settings.extendedKeys") private var extendedKeys = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Picker("Accent Color", selection: $accent) {
                        ForEach(["blue", "purple", "green", "orange", "pink"], id: \.self) { color in
                            Text(color.capitalized).tag(color)
                        }
                    }
                }
                Section("App Lock") {
                    Toggle("Face ID / Passcode Lock", isOn: $lockService.isBiometricLockEnabled)
                }
                Section("Terminal") {
                    Stepper(value: $fontSize, in: 10...24) {
                        Text("Font Size: \(Int(fontSize))")
                    }
                    Toggle("Confirm Multiline Paste", isOn: $pasteProtection)
                    Toggle("Extended Key Row", isOn: $extendedKeys)
                    Text("Pinch directly on the terminal to change its font size.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Agents") {
                    NavigationLink("Agent Presets") { AgentPresetsView() }
                    Toggle("Completion Notifications", isOn: $agentNotifications)
                        .onChange(of: agentNotifications) { _, enabled in
                            if enabled {
                                Task {
                                    if !(await NotificationService.requestAuthorization()) {
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
