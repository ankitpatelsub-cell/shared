import SwiftUI
import SwiftTerm

/// Thin `UIViewRepresentable` wrapper — the view model owns the actual
/// `TerminalView` instance so it survives across SwiftUI re-renders and tab
/// switches without losing scrollback or re-attaching delegates.
struct TerminalRepresentable: UIViewRepresentable {
    let terminalView: TerminalView

    func makeUIView(context: Context) -> TerminalView {
        terminalView
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}
}
