import SwiftUI

struct TerminalSettingsView: View {
    @AppStorage("dev.termvault.settings.fontSize") private var fontSize: Double = 14
    @AppStorage("dev.termvault.settings.terminalFont") private var terminalFont = "system"
    @AppStorage("dev.termvault.settings.terminalTheme") private var terminalTheme = "midnight"
    @AppStorage("dev.termvault.settings.pasteProtection") private var pasteProtection = true
    @AppStorage("dev.termvault.settings.extendedKeys") private var extendedKeys = true
    @AppStorage("dev.termvault.settings.gesturesEnabled") private var gesturesEnabled = true
    @AppStorage("dev.termvault.settings.keyRowLayout") private var keyRowLayout = "standard"

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

                    Toggle("Extended Keys", isOn: $extendedKeys)
                        .help("Show additional keyboard shortcuts")

                    Picker("Key Row Layout", selection: $keyRowLayout) {
                        Text("Compact").tag("compact")
                        Text("Standard").tag("standard")
                        Text("Full").tag("full")
                    }
                }

                Section("Gestures") {
                    Toggle("Enable Gestures", isOn: $gesturesEnabled)

                    if gesturesEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Swipe Right")
                                        .font(.subheadline)
                                    Text("Send Ctrl+C")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            HStack {
                                Image(systemName: "arrow.left")
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Swipe Left")
                                        .font(.subheadline)
                                    Text("Send Ctrl+D")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            HStack {
                                Image(systemName: "arrow.down")
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Swipe Down")
                                        .font(.subheadline)
                                    Text("Jump to Latest Output")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            HStack {
                                Image(systemName: "arrow.up")
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Swipe Up")
                                        .font(.subheadline)
                                    Text("Scroll to Top")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
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
