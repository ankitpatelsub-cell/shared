import SwiftUI
import SwiftTerm

/// The extra-keys row above the keyboard — per the spec, "the single
/// most-copied Termius detail." Mirrors what mature mobile SSH clients
/// (Termius, Blink) put here, since a soft keyboard has no physical Ctrl,
/// Alt, arrows, or navigation keys, and shell work leans hard on all of
/// them:
///
/// - Esc, Tab, Ctrl/Alt (real one-shot modifiers — see
///   `TerminalViewModel.pendingModifier` — not just visual toggles)
/// - Arrow keys, Home/End, Page Up/Down, forward-Delete
/// - Copy / Paste / Select — wired to SwiftTerm's own built-in
///   `copy(_:)`/`paste(_:)`/`selectAll()` (the same `UIResponderStandardEditActions`
///   machinery behind the system long-press menu; not reimplemented here)
/// - A "More" sheet with the Ctrl-chords used constantly in a shell
///   (Ctrl+C, Ctrl+D, Ctrl+L, …) as one-tap buttons, so you don't have to
///   toggle Ctrl and then hunt for the letter every time
///
/// There's deliberately no "Cut" button: a remote shell's scrollback isn't
/// editable text with something to remove *from* — every real terminal
/// app (including this one) only offers Copy/Paste for that reason.
struct ExtraKeysAccessoryView: View {
    @ObservedObject var viewModel: TerminalViewModel
    @State private var showingShortcuts = false

    private var terminalView: TerminalView { viewModel.terminalView }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                keyButton("esc") { viewModel.sendRawBytes([0x1B]) }
                keyButton("tab") { viewModel.sendRawBytes([0x09]) }
                toggleButton("ctrl", modifier: .ctrl)
                toggleButton("alt", modifier: .alt)

                divider

                keyButton("←") { sendCSI("D") }
                keyButton("↑") { sendCSI("A") }
                keyButton("↓") { sendCSI("B") }
                keyButton("→") { sendCSI("C") }

                divider

                keyButton("Home") { sendCSI("H") }
                keyButton("End") { sendCSI("F") }
                keyButton("PgUp") { sendCSI("5~") }
                keyButton("PgDn") { sendCSI("6~") }
                keyButton("Del") { sendCSI("3~") }

                divider

                keyButton("Copy") { terminalView.copy(nil) }
                keyButton("Paste") { terminalView.paste(nil) }
                keyButton("Select") { terminalView.selectAll(nil) }

                divider

                keyButton("•••") { showingShortcuts = true }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
        .sheet(isPresented: $showingShortcuts) {
            QuickShortcutsSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.3))
            .frame(width: 1, height: 24)
    }

    private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(minWidth: 40, minHeight: 32)
        }
        .buttonStyle(.bordered)
    }

    private func toggleButton(_ label: String, modifier: TerminalModifier) -> some View {
        let isActive = viewModel.pendingModifier == modifier
        return Button {
            viewModel.toggleModifier(modifier)
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(minWidth: 40, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(isActive ? .accentColor : .secondary)
    }

    private func sendCSI(_ suffix: String) {
        viewModel.sendRawBytes(Array("\u{1B}[\(suffix)".utf8))
    }
}

/// One-tap Ctrl-chords that come up constantly in a shell — hidden behind
/// "More" rather than crowding the always-visible bar, the same tradeoff
/// Termius/Blink make between an always-on strip and a fuller shortcuts
/// list.
private struct QuickShortcutsSheet: View {
    @ObservedObject var viewModel: TerminalViewModel
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(letter: Character, label: String, description: String)] = [
        ("c", "Ctrl+C", "Interrupt the running command"),
        ("d", "Ctrl+D", "Send EOF / exit the shell"),
        ("l", "Ctrl+L", "Clear the screen"),
        ("a", "Ctrl+A", "Jump to start of line"),
        ("e", "Ctrl+E", "Jump to end of line"),
        ("u", "Ctrl+U", "Clear line before cursor"),
        ("k", "Ctrl+K", "Clear line after cursor"),
        ("w", "Ctrl+W", "Delete the word before cursor"),
        ("r", "Ctrl+R", "Reverse history search"),
        ("z", "Ctrl+Z", "Suspend the running command"),
    ]

    var body: some View {
        NavigationStack {
            List(shortcuts, id: \.label) { shortcut in
                Button {
                    viewModel.sendControlChord(shortcut.letter)
                } label: {
                    HStack {
                        Text(shortcut.label)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                        Text(shortcut.description)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
