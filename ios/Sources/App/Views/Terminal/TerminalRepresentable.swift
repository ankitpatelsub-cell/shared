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
        view.keyboardDismissMode = .interactive
        view.panGestureRecognizer.minimumNumberOfTouches = 1
        
        // Increase scrollback buffer - SwiftTerm defaults to ~1000 lines
        // Allow much more history for SSH sessions
        view.scrollbackLines = 10000
    }
}
