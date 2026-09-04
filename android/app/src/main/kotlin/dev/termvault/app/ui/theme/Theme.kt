package dev.termvault.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Same refined teal used for AccentColor on iOS (res/values/colors.xml accent_light/accent_dark).
val TermVaultAccentLight = Color(0xFF1499A9)
val TermVaultAccentDark = Color(0xFF37C9C9)

private val LightColors = lightColorScheme(
    primary = TermVaultAccentLight,
    secondary = TermVaultAccentLight,
    tertiary = TermVaultAccentLight,
)

private val DarkColors = darkColorScheme(
    primary = TermVaultAccentDark,
    secondary = TermVaultAccentDark,
    tertiary = TermVaultAccentDark,
)

@Composable
fun TermVaultTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colorScheme = if (darkTheme) DarkColors else LightColors
    MaterialTheme(colorScheme = colorScheme, content = content)
}
