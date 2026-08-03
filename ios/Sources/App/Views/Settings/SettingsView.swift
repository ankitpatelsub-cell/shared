import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lockService: BiometricLockService
    @AppStorage("dev.termvault.settings.fontSize") private var fontSize: Double = 14
    @AppStorage("dev.termvault.settings.agentNotifications") private var agentNotifications = false
    @AppStorage("dev.termvault.settings.pasteProtection") private var pasteProtection = true
    @AppStorage("dev.termvault.settings.appearance") private var appearance = "system"
    @AppStorage("dev.termvault.settings.accent") private var accent = "blue"
    @AppStorage("dev.termvault.settings.extendedKeys") private var extendedKeys = true
    @AppStorage("dev.termvault.settings.terminalFont") private var terminalFont = "system"
    @AppStorage("dev.termvault.settings.terminalTheme") private var terminalTheme = "midnight"
    @AppStorage("dev.termvault.settings.keyRowLayout") private var keyRowLayout = "standard"

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
                    Picker("Font", selection: $terminalFont) {
                        Text("SF Mono").tag("system")
                        Text("Menlo").tag("menlo")
                        Text("Courier").tag("courier")
                    }
                    Picker("Color Theme", selection: $terminalTheme) {
                        Text("Midnight").tag("midnight")
                        Text("Solarized Dark").tag("solarized")
                        Text("Dracula").tag("dracula")
                        Text("Paper Light").tag("paper")
                    }
                    Picker("Keyboard Row", selection: $keyRowLayout) {
                        Text("Compact").tag("compact")
                        Text("Standard").tag("standard")
                        Text("Full").tag("full")
                    }
                    Text("Pinch directly on the terminal to change its font size.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Agents") {
                    NavigationLink("Agent Presets") { AgentPresetsView() }
                    NavigationLink("Command Snippets") { SnippetLibraryView() }
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
                Section("Activity") {
                    NavigationLink("Session History") { SessionHistoryView() }
                }
                Section("Integrations") {
                    NavigationLink {
                        SSHConfigView()
                    } label: {
                        Label("SSH Config Import / Export", systemImage: "doc.text")
                    }
                    NavigationLink {
                        GitHubSettingsView()
                    } label: {
                        Label("GitHub Personal Access Token", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                Section("Sync") {
                    NavigationLink {
                        CloudVaultSettingsView()
                    } label: {
                        Label("Encrypted Cloud Vault", systemImage: "lock.icloud")
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
