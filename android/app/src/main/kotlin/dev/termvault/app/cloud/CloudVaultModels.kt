package dev.termvault.app.cloud

import kotlinx.serialization.Serializable

@Serializable
data class AuthRequest(val email: String, val password: String)

@Serializable
data class AuthResponse(val token: String)

@Serializable
data class VaultEnvelope(val salt: String, val nonce: String, val ciphertext: String)

@Serializable
data class VaultReadResponse(val revision: Int, val vault: VaultEnvelope? = null)

@Serializable
data class VaultWriteRequest(val revision: Int, val vault: VaultEnvelope)

@Serializable
data class VaultWriteResponse(val revision: Int)

@Serializable
data class ErrorResponse(val error: String? = null)

/** Mirrors iOS `HostVaultRecord` — the plaintext shape encrypted inside [VaultEnvelope.ciphertext]. */
@Serializable
data class HostVaultRecord(
    val id: String,
    val label: String,
    val address: String,
    val port: Int,
    val username: String,
    val authMethod: String,
    val identityID: String? = null,
    val jumpHostID: String? = null,
    val startupSnippet: String? = null,
    val groupName: String? = null,
    val tags: List<String> = emptyList(),
    val themeName: String? = null,
    val password: String? = null,
)

@Serializable
data class IdentityVaultRecord(
    val id: String,
    val label: String,
    val keyType: String,
    val fingerprint: String,
    val publicKey: String,
    val privateKey: String? = null,
    val passphrase: String? = null,
)

@Serializable
data class SnippetVaultRecord(
    val id: String,
    val name: String,
    val command: String,
    val runOnConnect: Boolean,
)

@Serializable
data class VaultSnapshot(
    val version: Int = 1,
    val createdAt: String,
    val hosts: List<HostVaultRecord>,
    val identities: List<IdentityVaultRecord>,
    val snippets: List<SnippetVaultRecord>,
)
