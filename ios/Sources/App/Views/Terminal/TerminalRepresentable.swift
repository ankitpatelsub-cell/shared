import SwiftUI
import SwiftTerm

/// Thin `UIViewRepresentable` wrapper — the view model owns the actual
/// `TerminalView` instance so it survives across SwiftUI re-renders and tab
/// switches without losing scrollback or re-attaching delegates.
struct TerminalRepresentable: UIViewRepresentable {
    let terminalView: TerminalView

    func makeUIView(context: Context) -> TerminalView {
        configureScrolling(terminalView)
        return terminalView
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        configureScrolling(uiView)
    }

    private func configureScrolling(_ view: TerminalView) {
        // TerminalView is a UIScrollView subclass. Keep local scrollback
        // available even when a full-screen remote TUI is handling keys.
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.alwaysBounceHorizontal = false
        view.showsVerticalScrollIndicator = true
        view.isDirectionalLockEnabled = true
        // `.interactive` treats every scroll drag as also dragging the
        // keyboard away — fine for a chat view, actively hostile here: the
        // normal terminal workflow is scroll up to check earlier output
        // *while staying in the middle of typing a command*. `.none` keeps
        // the keyboard exactly where it is regardless of how much
        // scrollback gets reviewed.
        view.keyboardDismissMode = .none
        view.panGestureRecognizer.minimumNumberOfTouches = 1
    }
}
