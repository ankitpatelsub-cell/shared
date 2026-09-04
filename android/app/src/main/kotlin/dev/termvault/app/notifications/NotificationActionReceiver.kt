package dev.termvault.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.termvault.app.TermVaultApplication
import dev.termvault.app.util.ShellQuote
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Handles the "Continue"/"Cancel" action buttons on an "agent waiting"
 * notification by sending the implied key straight into the tmux pane over
 * a plain exec command — mirrors iOS `NotificationService.handleAction`.
 * Deliberately doesn't go through the interactive [dev.termvault.app.ssh.SshSessionManager]
 * pty session, since this can fire without that session open;
 * [dev.termvault.app.ssh.RemoteCommandService] only needs *some* existing
 * SSH connection to the host already alive in this process.
 */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key = when (intent.action) {
            NotificationService.CONTINUE_ACTION -> "Enter"
            NotificationService.CANCEL_ACTION -> "Escape"
            else -> return
        }
        val hostIdString = intent.getStringExtra(NotificationService.EXTRA_HOST_ID) ?: return
        val tmuxName = intent.getStringExtra(NotificationService.EXTRA_TMUX_NAME) ?: return
        val hostId = runCatching { UUID.fromString(hostIdString) }.getOrNull() ?: return

        val app = TermVaultApplication.from(context)
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            runCatching {
                app.remoteCommandService.run(
                    hostId,
                    "tmux send-keys -t ${ShellQuote.quote(tmuxName)} $key 2>/dev/null || true",
                )
            }
            pendingResult.finish()
        }
    }
}
