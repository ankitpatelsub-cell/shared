package dev.termvault.app.ui.keys

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.termvault.app.data.db.IdentityDao
import dev.termvault.app.data.db.IdentityEntity
import dev.termvault.app.data.model.IdentityKeyType
import dev.termvault.app.security.SecretStore
import dev.termvault.app.ssh.IdentityKeyGenerator
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class IdentityManagerViewModel(
    private val identityDao: IdentityDao,
    private val secretStore: SecretStore,
) : ViewModel() {
    val identities: StateFlow<List<IdentityEntity>> =
        identityDao.observeAll().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun generate(label: String, keyType: IdentityKeyType, comment: String) {
        viewModelScope.launch {
            val generated = when (keyType) {
                IdentityKeyType.ED25519 -> IdentityKeyGenerator.generateEd25519(comment)
                IdentityKeyType.RSA4096 -> IdentityKeyGenerator.generateRsa4096(comment)
            }
            val identity = IdentityEntity(
                label = label,
                keyTypeRaw = keyType.rawValue,
                fingerprint = generated.fingerprint,
                publicKey = generated.publicKeyLine,
            )
            identityDao.upsert(identity)
            secretStore.setPrivateKeyPem(generated.privateKeyPem, identity)
        }
    }

    fun delete(identity: IdentityEntity) {
        viewModelScope.launch {
            secretStore.deleteSecrets(identity)
            identityDao.delete(identity)
        }
    }
}
