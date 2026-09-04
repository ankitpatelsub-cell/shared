import SwiftUI

struct TerminalSettingsView: View {
    @AppStorage("dev.termvault.settings.fontSize") private var fontSize: Double = 14
    @AppStorage("dev.termvault.settings.terminalFont") private var terminalFont = "system"
    @AppStorage("dev.termvault.settings.terminalTheme") private var terminalTheme = "midnight"
    @AppStorage("dev.termvault.settings.pasteProtection") private var pasteProtection = true
    @State private var autoApproveSettings = AutoApproveSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $terminalTheme) {
                        ForEach(TerminalTheme.allThemes, id: \.name) { theme in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(uiColor: theme.uiBackground))
                                    .frame(width: 16, height: 16)
                                Text(theme.name)
                            }
                            .tag(theme.name.lowercased())
                        }
                    }

                    Picker("Font", selection: $terminalFont) {
                        Text("System").tag("system")
                        Text("Menlo").tag("menlo")
                        Text("Courier").tag("courier")
                    }

                    Slider(value: $fontSize, in: 10...24, step: 1) {
                        Text("Font Size")
                    }
                    .onChange(of: fontSize) { _, _ in }

                    Text("Current: \(Int(fontSize))pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Input") {
                    Toggle("Paste Protection", isOn: $pasteProtection)
                        .help("Warn before pasting multiple lines")

                    // Auto-approve is only ever consulted while Paste Protection
                    // is on (see TerminalViewModel.send: the whole prompt check
                    // is skipped entirely once protection is off) — so this
                    // control has to show when protection is ON, not off, or
                    // there's no way to reach the one setting combination that
                    // actually skips the prompt.
                    if pasteProtection {
                        Toggle("Auto-Approve Multi-line Paste", isOn: Binding(
                            get: { autoApproveSettings.autoApproveMultilinePaste },
                            set: { autoApproveSettings.autoApproveMultilinePaste = $0 }
                        ))
                        .help("Skip the confirmation and paste multi-line input immediately")
                    }

                    NavigationLink("Customize Keyboard Row") {
                        KeyboardShortcutsCustomizeView()
                    }
                    .help("Choose which keys show above the keyboard, and in what order")
                }

                Section("Approvals") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-Approve SSH Host Keys", isOn: Binding(
                            get: { autoApproveSettings.autoApproveHostKeys },
                            set: { autoApproveSettings.autoApproveHostKeys = $0 }
                        ))
                        .help("Automatically trust new SSH host keys on first connection")

                        Text("Enable this mode when running automated SSH operations or when Claude/Codex needs to approve connections without user interaction.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Preview") {
                    let theme = TerminalTheme.theme(for: terminalTheme)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ForEach(["$", "ls", "-la", "/home"], id: \.self) { text in
                                Text(text)
                                    .font(.system(size: CGFloat(fontSize), weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color(hex: theme.foreground))
                            }
                            Spacer()
                        }
                    }
                    .frame(minHeight: 60)
                    .padding()
                    .background(Color(uiColor: theme.uiBackground))
                    .cornerRadius(8)
                }
            }
            .navigationTitle("Terminal Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let rgb = Int(hex, radix: 16) ?? 0
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    TerminalSettingsView()
}
