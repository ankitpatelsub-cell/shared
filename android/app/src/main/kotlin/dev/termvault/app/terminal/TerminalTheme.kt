package dev.termvault.app.terminal

import android.graphics.Color

/** Direct port of iOS `TerminalThemeProvider.swift` (the file defines `TerminalTheme` directly, despite its name). */
data class TerminalTheme(
    val themeName: String,
    val foregroundHex: String,
    val backgroundHex: String,
    val uiBackground: Int,
    val cursorColor: Int,
    val selectionColor: Int,
) {
    val foreground: Int get() = Color.parseColor(foregroundHex)
    val background: Int get() = Color.parseColor(backgroundHex)

    companion object {
        val midnight = TerminalTheme(
            "Midnight", "#f2f2f2", "#000000",
            uiBackground = Color.BLACK,
            cursorColor = Color.WHITE,
            selectionColor = Color.argb(128, 51, 51, 51),
        )
        val solarized = TerminalTheme(
            "Solarized Dark", "#839496", "#002b36",
            uiBackground = Color.rgb(0, 43, 54),
            cursorColor = Color.rgb(130, 148, 150),
            selectionColor = Color.argb(128, 10, 41, 59),
        )
        val dracula = TerminalTheme(
            "Dracula", "#f8f8f2", "#282a36",
            uiBackground = Color.rgb(41, 41, 54),
            cursorColor = Color.rgb(247, 138, 176),
            selectionColor = Color.argb(128, 71, 74, 92),
        )
        val nord = TerminalTheme(
            "Nord", "#d8dee9", "#2e3440",
            uiBackground = Color.rgb(46, 51, 64),
            cursorColor = Color.rgb(214, 237, 255),
            selectionColor = Color.argb(128, 74, 87, 107),
        )
        val gruvbox = TerminalTheme(
            "Gruvbox Dark", "#ebdbb2", "#282828",
            uiBackground = Color.rgb(41, 41, 41),
            cursorColor = Color.rgb(235, 219, 179),
            selectionColor = Color.argb(128, 84, 77, 74),
        )
        val monokai = TerminalTheme(
            "Monokai", "#f8f8f2", "#272822",
            uiBackground = Color.rgb(38, 38, 36),
            cursorColor = Color.rgb(247, 247, 242),
            selectionColor = Color.argb(128, 87, 87, 84),
        )
        val oneLight = TerminalTheme(
            "One Light", "#383a42", "#fafafa",
            uiBackground = Color.rgb(250, 250, 250),
            cursorColor = Color.rgb(102, 102, 102),
            selectionColor = Color.argb(128, 240, 240, 240),
        )
        val tokyoNight = TerminalTheme(
            "Tokyo Night", "#c0caf5", "#1a1b26",
            uiBackground = Color.rgb(26, 28, 38),
            cursorColor = Color.rgb(191, 201, 245),
            selectionColor = Color.argb(128, 46, 51, 71),
        )

        val allThemes = listOf(midnight, solarized, dracula, nord, gruvbox, monokai, oneLight, tokyoNight)

        fun theme(forName: String?): TerminalTheme =
            allThemes.firstOrNull { it.themeName.equals(forName, ignoreCase = true) } ?: midnight
    }
}
