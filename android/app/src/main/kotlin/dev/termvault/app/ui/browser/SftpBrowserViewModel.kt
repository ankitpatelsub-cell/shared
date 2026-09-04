package dev.termvault.app.ui.browser

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.IdentityEntity
import dev.termvault.app.data.model.SftpEntry
import dev.termvault.app.ssh.SftpService
import dev.termvault.app.ssh.SshNotConnectedException
import dev.termvault.app.ssh.SshSessionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

sealed class BrowserState {
    object Idle : BrowserState()
    object Connecting : BrowserState()
    object Loading : BrowserState()
    data class Loaded(val path: String, val entries: List<SftpEntry>) : BrowserState()
    data class Failed(val message: String) : BrowserState()
}

class SftpBrowserViewModel(
    private val sessionManager: SshSessionManager,
    private val sftpService: SftpService,
    private val applicationScope: CoroutineScope,
) : ViewModel() {
    private val connectionId = UUID.randomUUID()

    private val _state = MutableStateFlow<BrowserState>(BrowserState.Idle)
    val state: StateFlow<BrowserState> = _state.asStateFlow()

    fun open(host: HostEntity, identity: IdentityEntity?) {
        viewModelScope.launch {
            _state.value = BrowserState.Connecting
            runCatching {
                sessionManager.connect(connectionId, host, identity, onOutput = {}, onClose = {})
            }.onSuccess {
                listDirectory(".")
            }.onFailure { error ->
                _state.value = BrowserState.Failed(error.message ?: "Connection failed.")
            }
        }
    }

    fun listDirectory(path: String) {
        viewModelScope.launch {
            _state.value = BrowserState.Loading
            runCatching {
                val client = sessionManager.session(connectionId) ?: throw SshNotConnectedException()
                sftpService.listDirectory(connectionId, client, path)
            }.onSuccess { entries ->
                _state.value = BrowserState.Loaded(path, entries)
            }.onFailure { error ->
                _state.value = BrowserState.Failed(error.message ?: "Could not list directory.")
            }
        }
    }

    fun navigateUp() {
        val current = (_state.value as? BrowserState.Loaded)?.path ?: return
        val parent = current.trimEnd('/').substringBeforeLast('/', ".").ifEmpty { "/" }
        listDirectory(parent)
    }

    override fun onCleared() {
        super.onCleared()
        sftpService.disconnect(connectionId)
        applicationScope.launch { sessionManager.disconnect(connectionId) }
    }
}
