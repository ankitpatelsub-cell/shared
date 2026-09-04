package dev.termvault.app.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.termvault.app.cloud.CloudVaultService
import dev.termvault.app.github.GitHubService
import dev.termvault.app.security.SecretStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class SettingsViewModel(
    private val secretStore: SecretStore,
    private val cloudVaultService: CloudVaultService,
    private val gitHubService: GitHubService,
) : ViewModel() {
    private val _status = MutableStateFlow<String?>(null)
    val status: StateFlow<String?> = _status.asStateFlow()

    private val _isBusy = MutableStateFlow(false)
    val isBusy: StateFlow<Boolean> = _isBusy.asStateFlow()

    fun currentGitHubToken(): String? = secretStore.githubToken()

    fun saveGitHubToken(token: String) {
        viewModelScope.launch {
            _isBusy.value = true
            runCatching {
                secretStore.setGitHubToken(token)
                gitHubService.validateToken()
            }.onSuccess {
                _status.value = "GitHub token saved."
            }.onFailure {
                secretStore.deleteGitHubToken()
                _status.value = "Invalid GitHub token: ${it.message}"
            }
            _isBusy.value = false
        }
    }

    fun clearGitHubToken() {
        secretStore.deleteGitHubToken()
        _status.value = "GitHub token removed."
    }

    fun cloudSignIn(email: String, password: String, register: Boolean) {
        viewModelScope.launch {
            _isBusy.value = true
            runCatching { cloudVaultService.authenticate(email, password, register) }
                .onSuccess { _status.value = if (register) "Account created." else "Signed in." }
                .onFailure { _status.value = "Cloud Vault error: ${it.message}" }
            _isBusy.value = false
        }
    }

    fun cloudUpload(password: String) {
        viewModelScope.launch {
            _isBusy.value = true
            runCatching { cloudVaultService.upload(password) }
                .onSuccess { _status.value = "Vault uploaded (revision $it)." }
                .onFailure { _status.value = "Upload failed: ${it.message}" }
            _isBusy.value = false
        }
    }

    fun cloudRestore(password: String) {
        viewModelScope.launch {
            _isBusy.value = true
            runCatching { cloudVaultService.restore(password) }
                .onSuccess { _status.value = "Vault restored (revision $it)." }
                .onFailure { _status.value = "Restore failed: ${it.message}" }
            _isBusy.value = false
        }
    }
}
