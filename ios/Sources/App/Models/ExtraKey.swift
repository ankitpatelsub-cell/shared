import Foundation

/// One entry in the customizable extra-keys row above the keyboard.
/// `ExtraKeysAccessoryView` renders whichever keys the user has enabled, in
/// the order they chose (via `ExtraKeysOrder`); `KeyboardShortcutsCustomizeView`
/// is where they pick that selection.
enum ExtraKey: String, CaseIterable, Identifiable {
    case esc, tab, shiftTab, ctrl, alt, backspace, clearLine
    case tilde, slash, pipe, dash
    case arrowLeft, arrowUp, arrowDown, arrowRight
    case home, end, pageUp, pageDown, delete, f1
    case copy, paste, selectAll
    case shortcuts

    var id: String { rawValue }

    /// Short label shown on the keycap itself.
    var label: String {
        switch self {
        case .esc: return "esc"
        case .tab: return "tab"
        case .shiftTab: return "⇧tab"
        case .ctrl: return "ctrl"
        case .alt: return "alt"
        case .backspace: return "⌫"
        case .clearLine: return "Clear"
        case .tilde: return "~"
        case .slash: return "/"
        case .pipe: return "|"
        case .dash: return "-"
        case .arrowLeft: return "←"
        case .arrowUp: return "↑"
        case .arrowDown: return "↓"
        case .arrowRight: return "→"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .delete: return "Del"
        case .f1: return "F1"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .selectAll: return "Select"
        case .shortcuts: return "•••"
        }
    }

    /// Longer, unambiguous name used in the customize screen and for
    /// accessibility, since the keycap label alone (e.g. "~") isn't always
    /// self-explanatory out of context.
    var fullName: String {
        switch self {
        case .esc: return "Escape"
        case .tab: return "Tab"
        case .shiftTab: return "Shift+Tab (Backtab)"
        case .ctrl: return "Ctrl (one-shot modifier)"
        case .alt: return "Alt (one-shot modifier)"
        case .backspace: return "Backspace"
        case .clearLine: return "Clear Current Line"
        case .tilde: return "~"
        case .slash: return "/"
        case .pipe: return "|"
        case .dash: return "-"
        case .arrowLeft: return "Left Arrow"
        case .arrowUp: return "Up Arrow"
        case .arrowDown: return "Down Arrow"
        case .arrowRight: return "Right Arrow"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .delete: return "Forward Delete"
        case .f1: return "F1"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .selectAll: return "Select All"
        case .shortcuts: return "More Shortcuts (Ctrl+C, Ctrl+D, …)"
        }
    }

    /// The row's original fixed layout, kept as the default for anyone who
    /// hasn't customized it yet.
    static let defaultOrder: [ExtraKey] = [
        .esc, .tab, .ctrl, .alt,
        .backspace, .clearLine,
        .tilde, .slash, .pipe, .dash,
        .arrowLeft, .arrowUp, .arrowDown, .arrowRight,
        .copy, .paste, .selectAll,
        .shortcuts,
    ]
}

/// Wraps an ordered `[ExtraKey]` selection as a single `@AppStorage`-compatible
/// value (comma-joined raw values), so the accessory bar and the customize
/// screen both read/write the exact same persisted list.
struct ExtraKeysOrder: RawRepresentable, Equatable {
    var keys: [ExtraKey]

    init(keys: [ExtraKey]) {
        self.keys = keys
    }

    init?(rawValue: String) {
        guard !rawValue.isEmpty else {
            self.keys = []
            return
        }
        self.keys = rawValue.split(separator: ",").compactMap { ExtraKey(rawValue: String($0)) }
    }

    var rawValue: String {
        keys.map(\.rawValue).joined(separator: ",")
    }
}
