package dev.termvault.app.terminal

import android.util.Log
import com.termux.terminal.TerminalSessionClient

/**
 * Minimal [TerminalSessionClient]: only [getTerminalCursorStyle] and
 * [onTerminalCursorStateChange] are ever actually called by
 * `TerminalEmulator` (see `TerminalSessionClient.java`'s doc comment for
 * how that was verified) — the log* methods are called by the vendored
 * `Logger` helper class.
 */
class TermVaultTerminalClient : TerminalSessionClient {
    override fun onTerminalCursorStateChange(state: Boolean) {}

    override fun getTerminalCursorStyle(): Int? = null

    override fun logError(tag: String, message: String) { Log.e(tag, message) }
    override fun logWarn(tag: String, message: String) { Log.w(tag, message) }
    override fun logInfo(tag: String, message: String) { Log.i(tag, message) }
    override fun logDebug(tag: String, message: String) { Log.d(tag, message) }
    override fun logVerbose(tag: String, message: String) { Log.v(tag, message) }

    override fun logStackTraceWithMessage(tag: String, message: String, e: Exception) {
        Log.e(tag, message, e)
    }

    override fun logStackTrace(tag: String, e: Exception) { Log.e(tag, "", e) }
}
