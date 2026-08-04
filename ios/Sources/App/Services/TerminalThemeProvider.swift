import UIKit

struct TerminalTheme {
    let name: String
    let foreground: String
    let background: String
    let uiBackground: UIColor
    let cursorColor: UIColor
    let selectionColor: UIColor

    static let midnight = TerminalTheme(
        name: "Midnight",
        foreground: "#f2f2f2",
        background: "#000000",
        uiBackground: .black,
        cursorColor: .white,
        selectionColor: UIColor(white: 0.2, alpha: 0.5)
    )

    static let solarized = TerminalTheme(
        name: "Solarized Dark",
        foreground: "#839496",
        background: "#002b36",
        uiBackground: UIColor(red: 0, green: 0.17, blue: 0.21, alpha: 1),
        cursorColor: UIColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1),
        selectionColor: UIColor(red: 0.04, green: 0.16, blue: 0.23, alpha: 0.5)
    )

    static let dracula = TerminalTheme(
        name: "Dracula",
        foreground: "#f8f8f2",
        background: "#282a36",
        uiBackground: UIColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1),
        cursorColor: UIColor(red: 0.97, green: 0.54, blue: 0.69, alpha: 1),
        selectionColor: UIColor(red: 0.28, green: 0.29, blue: 0.36, alpha: 0.5)
    )

    static let nord = TerminalTheme(
        name: "Nord",
        foreground: "#d8dee9",
        background: "#2e3440",
        uiBackground: UIColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1),
        cursorColor: UIColor(red: 0.84, green: 0.93, blue: 1.0, alpha: 1),
        selectionColor: UIColor(red: 0.29, green: 0.34, blue: 0.42, alpha: 0.5)
    )

    static let gruvbox = TerminalTheme(
        name: "Gruvbox Dark",
        foreground: "#ebdbb2",
        background: "#282828",
        uiBackground: UIColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1),
        cursorColor: UIColor(red: 0.92, green: 0.86, blue: 0.70, alpha: 1),
        selectionColor: UIColor(red: 0.33, green: 0.30, blue: 0.29, alpha: 0.5)
    )

    static let monokai = TerminalTheme(
        name: "Monokai",
        foreground: "#f8f8f2",
        background: "#272822",
        uiBackground: UIColor(red: 0.15, green: 0.15, blue: 0.14, alpha: 1),
        cursorColor: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1),
        selectionColor: UIColor(red: 0.34, green: 0.34, blue: 0.33, alpha: 0.5)
    )

    static let oneLight = TerminalTheme(
        name: "One Light",
        foreground: "#383a42",
        background: "#fafafa",
        uiBackground: UIColor(white: 0.98, alpha: 1),
        cursorColor: UIColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1),
        selectionColor: UIColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 0.5)
    )

    static let tokyoNight = TerminalTheme(
        name: "Tokyo Night",
        foreground: "#c0caf5",
        background: "#1a1b26",
        uiBackground: UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1),
        cursorColor: UIColor(red: 0.75, green: 0.79, blue: 0.96, alpha: 1),
        selectionColor: UIColor(red: 0.18, green: 0.20, blue: 0.28, alpha: 0.5)
    )

    static let allThemes: [TerminalTheme] = [
        .midnight,
        .solarized,
        .dracula,
        .nord,
        .gruvbox,
        .monokai,
        .oneLight,
        .tokyoNight
    ]

    static func theme(for name: String) -> TerminalTheme {
        allThemes.first { $0.name.lowercased() == name.lowercased() } ?? .midnight
    }
}
