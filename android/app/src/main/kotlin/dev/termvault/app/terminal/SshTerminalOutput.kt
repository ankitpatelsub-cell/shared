package dev.termvault.app.terminal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.termux.terminal.TerminalOutput
import dev.termvault.app.ssh.SshSessionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Bridges the vendored [TerminalEmulator]/[TerminalOutput] contract to a
 * live SSH shell: every byte the emulator wants to write back (typed input,
 * or a response the emulator itself generates, e.g. a cursor-position
 * report) goes out over [SshSessionManager.send] for [connectionId].
 * Mirrors iOS `SSHTerminalOutput`/`TerminalViewModel`'s write-back path.
 */
class SshTerminalOutput(
    private val context: Context,
    private val connectionId: UUID,
    private val sessionManager: SshSessionManager,
    private val scope: CoroutineScope,
    private val onTitleChanged: (String) -> Unit = {},
    private val onBell: () -> Unit = {},
) : TerminalOutput() {

    override fun write(data: ByteArray, offset: Int, count: Int) {
        val chunk = data.copyOfRange(offset, offset + count)
        scope.launch {
            runCatching { sessionManager.send(connectionId, String(chunk, Charsets.UTF_8)) }
        }
    }

    override fun titleChanged(oldTitle: String?, newTitle: String?) {
        onTitleChanged(newTitle.orEmpty())
    }

    override fun onCopyTextToClipboard(text: String?) {
        if (text.isNullOrEmpty()) return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText("TermVault", text))
    }

    override fun onPasteTextFromClipboard() {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        val text = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
        if (!text.isNullOrEmpty()) {
            scope.launch { runCatching { sessionManager.send(connectionId, text) } }
        }
    }

    override fun onBell() {
        onBell.invoke()
    }

    override fun onColorsChanged() {
        // No-op: TerminalEmulatorView re-reads mColors.mCurrentColors on every render.
    }
}
