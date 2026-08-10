package dev.termvault.app.ui.terminal

import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.IdentityEntity
import dev.termvault.app.history.CommandHistoryStore
import dev.termvault.app.history.SessionHistoryStore
import dev.termvault.app.ssh.JumpHop
import dev.termvault.app.ssh.SshSessionManager
import dev.termvault.app.terminal.TerminalEmulatorView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class ConnectionState { CONNECTING, CONNECTED, DISCONNECTED, FAILED }

/**
 * Deliberately *not* an `androidx.lifecycle.ViewModel`: [dev.termvault.app.ui.AppRoot]
 * pushes the terminal screen with plain Compose state (no Navigation-Compose
 * back stack), so a real ViewModel scoped to the default Activity-level
 * `ViewModelStore` would never actually get cleared when the user backs out
 * — one abandoned SSH connection per host ever opened, for the life of the
 * process. [dispose] is called explicitly from a `DisposableEffect` instead,
 * giving this a lifetime tied to the screen's actual presence in composition.
 */
class TerminalViewModel(
    private val host: HostEntity,
    private val identity: IdentityEntity?,
    private val jumpHosts: List<JumpHop>,
    private val sessionManager: SshSessionManager,
    private val commandHistoryStore: CommandHistoryStore,
    private val sessionHistoryStore: SessionHistoryStore,
    private val applicationScope: CoroutineScope,
) {
    private val connectionId = host.id
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _connectionState = MutableStateFlow(ConnectionState.CONNECTING)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private var view: TerminalEmulatorView? = null
    private val startedAt = System.currentTimeMillis()
    private var bytesTransferred = 0L

    fun attach(view: TerminalEmulatorView) {
        this.view = view
        view.attach(connectionId, sessionManager, scope)
        connect()
    }

    private fun connect() {
        scope.launch {
            _connectionState.value = ConnectionState.CONNECTING
            runCatching {
                sessionManager.connect(
                    connectionId = connectionId,
                    host = host,
                    identity = identity,
                    jumpHosts = jumpHosts,
                    onOutput = { data ->
                        bytesTransferred += data.size
                        view?.feed(data)
                    },
                    onClose = { _connectionState.value = ConnectionState.DISCONNECTED },
                )
            }.onSuccess {
                _connectionState.value = ConnectionState.CONNECTED
            }.onFailure { error ->
                _connectionState.value = ConnectionState.FAILED
                _lastError.value = error.message ?: "Connection failed."
            }
        }
    }

    fun retry() = connect()

    fun send(text: String) {
        view?.sendRaw(text)
    }

    fun sendRawBytes(bytes: ByteArray) {
        view?.sendRaw(String(bytes, Charsets.ISO_8859_1))
    }

    fun sendCsi(suffix: String) {
        view?.sendRaw("[$suffix")
    }

    /** Sends the control byte for Ctrl+<letter> (e.g. 'c' -> 0x03). */
    fun sendControlChord(letter: Char) {
        val upper = letter.uppercaseChar()
        if (upper !in 'A'..'Z') return
        sendRawBytes(byteArrayOf((upper.code - 'A'.code + 1).toByte()))
    }

    fun runCommand(command: String) {
        scope.launch { commandHistoryStore.record(command, host.id) }
        view?.sendRaw("$command\r")
    }

    fun dispose() {
        view = null
        scope.cancel()
        applicationScope.launch {
            sessionHistoryStore.record(
                hostId = host.id,
                hostLabel = host.label,
                workspaceName = null,
                startedAt = startedAt,
                transcript = "",
                averageLatencyMs = 0,
                dataTransferredBytes = bytesTransferred,
                commandCount = 0,
            )
            sessionManager.disconnect(connectionId)
        }
    }
}
