package dev.termvault.app.ui.terminal

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

private data class QuickShortcut(val letter: Char, val label: String, val description: String)

private val quickShortcuts = listOf(
    QuickShortcut('c', "Ctrl+C", "Interrupt the running command"),
    QuickShortcut('d', "Ctrl+D", "Send EOF / exit the shell"),
    QuickShortcut('l', "Ctrl+L", "Clear the screen"),
    QuickShortcut('a', "Ctrl+A", "Jump to start of line"),
    QuickShortcut('e', "Ctrl+E", "Jump to end of line"),
    QuickShortcut('u', "Ctrl+U", "Clear line before cursor"),
    QuickShortcut('k', "Ctrl+K", "Clear line after cursor"),
    QuickShortcut('w', "Ctrl+W", "Delete the word before cursor"),
    QuickShortcut('r', "Ctrl+R", "Reverse history search"),
    QuickShortcut('z', "Ctrl+Z", "Suspend the running command"),
)

/**
 * The extra-keys row above the keyboard — per the spec, "the single
 * most-copied Termius detail." Mirrors iOS `ExtraKeysAccessoryView`: Esc,
 * Tab, Backspace, a readline-style clear-line, arrows, Home/End/Delete, and
 * a "More" sheet with the Ctrl-chords used constantly in a shell. Unlike
 * iOS, there's no sticky Ctrl/Alt toggle that modifies the *next*
 * soft-keyboard keystroke — that needs deep IME interception this pass
 * didn't take on — so Ctrl combos go through the "More" sheet's one-tap
 * buttons instead.
 */
@Composable
fun ExtraKeysBar(viewModel: TerminalViewModel) {
    var showShortcuts by remember { mutableStateOf(false) }

    Surface(tonalElevation = 2.dp) {
        Row(
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 8.dp, vertical = 6.dp),
        ) {
            KeyCap("esc") { viewModel.sendRawBytes(byteArrayOf(0x1B)) }
            KeyCap("tab") { viewModel.sendRawBytes(byteArrayOf(0x09)) }
            KeyCap("⌫") { viewModel.sendRawBytes(byteArrayOf(0x7F)) }
            KeyCap("Clear") { viewModel.sendRawBytes(byteArrayOf(0x01, 0x0B)) }
            Spacer(modifier = Modifier.width(8.dp))
            KeyCap("←") { viewModel.sendCsi("D") }
            KeyCap("↑") { viewModel.sendCsi("A") }
            KeyCap("↓") { viewModel.sendCsi("B") }
            KeyCap("→") { viewModel.sendCsi("C") }
            Spacer(modifier = Modifier.width(8.dp))
            KeyCap("Home") { viewModel.sendCsi("H") }
            KeyCap("End") { viewModel.sendCsi("F") }
            KeyCap("Del") { viewModel.sendCsi("3~") }
            Spacer(modifier = Modifier.width(8.dp))
            KeyCap("•••") { showShortcuts = true }
        }
    }

    if (showShortcuts) {
        AlertDialog(
            onDismissRequest = { showShortcuts = false },
            title = { Text("Shortcuts") },
            text = {
                LazyColumn {
                    items(quickShortcuts) { shortcut ->
                        ListItem(
                            headlineContent = { Text(shortcut.label, style = MaterialTheme.typography.titleSmall) },
                            supportingContent = { Text(shortcut.description) },
                            modifier = Modifier.clickable {
                                viewModel.sendControlChord(shortcut.letter)
                                showShortcuts = false
                            },
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showShortcuts = false }) { Text("Done") }
            },
        )
    }
}

@Composable
private fun KeyCap(label: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.padding(horizontal = 2.dp)) {
        Text(label)
    }
}
