import SwiftUI
import SwiftTerm

/// The extra-keys row above the keyboard — per the spec, "the single
/// most-copied Termius detail." Ctrl/Alt are latching modifiers: toggle one
/// on, then tap a regular key on the software keyboard, and the *next*
/// character typed should be remapped (e.g. Ctrl+C -> 0x03) before it's
/// sent. Wiring that remap requires intercepting `TerminalView`'s key
/// input pipeline (it manages its own `UIKeyInput` internally), which is
/// left as a follow-up — the toggle buttons here are wired and visible,
/// but don't yet transform the next keystroke.
struct ExtraKeysAccessoryView: View {
    let terminalView: TerminalView

    @State private var ctrlActive = false
    @State private var altActive = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                keyButton("esc") { sendRaw([0x1B]) }
                keyButton("tab") { sendRaw([0x09]) }
                toggleButton("ctrl", isActive: $ctrlActive)
                toggleButton("alt", isActive: $altActive)
                keyButton("←") { sendCSI("D") }
                keyButton("↑") { sendCSI("A") }
                keyButton("↓") { sendCSI("B") }
                keyButton("→") { sendCSI("C") }
                keyButton("⌘") {}
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
    }

    private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(minWidth: 40, minHeight: 32)
        }
        .buttonStyle(.bordered)
    }

    private func toggleButton(_ label: String, isActive: Binding<Bool>) -> some View {
        Button {
            isActive.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(minWidth: 40, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(isActive.wrappedValue ? .accentColor : .secondary)
    }

    private func sendRaw(_ bytes: [UInt8]) {
        terminalView.terminalDelegate?.send(source: terminalView, data: bytes[...])
    }

    private func sendCSI(_ letter: String) {
        sendRaw(Array("\u{1B}[\(letter)".utf8))
    }
}
