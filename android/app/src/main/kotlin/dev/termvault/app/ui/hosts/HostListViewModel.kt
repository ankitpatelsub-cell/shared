package dev.termvault.app.ui.hosts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.termvault.app.data.db.HostDao
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.IdentityDao
import dev.termvault.app.data.db.IdentityEntity
import dev.termvault.app.data.model.HostAuthMethod
import dev.termvault.app.security.SecretStore
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.UUID

class HostListViewModel(
    private val hostDao: HostDao,
    identityDao: IdentityDao,
    private val secretStore: SecretStore,
) : ViewModel() {
    val hosts: StateFlow<List<HostEntity>> =
        hostDao.observeAll().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val identities: StateFlow<List<IdentityEntity>> =
        identityDao.observeAll().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun save(
        existing: HostEntity?,
        label: String,
        address: String,
        port: Int,
        username: String,
        authMethod: HostAuthMethod,
        identityId: UUID?,
        password: String?,
        groupName: String?,
        tags: List<String>,
    ) {
        viewModelScope.launch {
            val host = (existing ?: HostEntity(label = label, address = address, username = username)).copy(
                label = label,
                address = address,
                port = port,
                username = username,
                authMethodRaw = authMethod.rawValue,
                identityId = identityId,
                groupName = groupName?.takeIf { it.isNotBlank() },
                tags = tags,
            )
            hostDao.upsert(host)
            if (authMethod == HostAuthMethod.PASSWORD && !password.isNullOrEmpty()) {
                secretStore.setPassword(password, host)
            }
        }
    }

    fun delete(host: HostEntity) {
        viewModelScope.launch {
            secretStore.deletePassword(host)
            hostDao.delete(host)
        }
    }
}
