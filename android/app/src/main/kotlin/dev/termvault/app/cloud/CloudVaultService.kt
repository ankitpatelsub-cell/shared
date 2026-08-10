package dev.termvault.app.cloud

import dev.termvault.app.data.db.HostDao
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.IdentityDao
import dev.termvault.app.data.db.IdentityEntity
import dev.termvault.app.data.db.SnippetDao
import dev.termvault.app.data.db.SnippetEntity
import dev.termvault.app.security.SecretStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.params.HKDFParameters
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import java.security.SecureRandom
import java.time.Instant
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

private fun b64Encode(bytes: ByteArray): String = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
private fun b64Decode(text: String): ByteArray = android.util.Base64.decode(text, android.util.Base64.NO_WRAP)

class CloudVaultError(message: String) : Exception(message)
class EmptyVaultException : Exception("No encrypted vault has been uploaded yet.")

/**
 * Encrypted cross-device sync of hosts/identities/snippets against the real
 * `backend/termvault/server.py` API — mirrors iOS `CloudVaultService.swift`
 * exactly, including the AES-256-GCM + HKDF-SHA256 envelope format, so
 * vaults uploaded from one platform can be restored on the other.
 */
class CloudVaultService(
    private val secretStore: SecretStore,
    private val hostDao: HostDao,
    private val identityDao: IdentityDao,
    private val snippetDao: SnippetDao,
) {
    private val json = Json { ignoreUnknownKeys = true }

    private val api: CloudVaultApi = Retrofit.Builder()
        .baseUrl("https://masystem.co.in/termvault-api/")
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(CloudVaultApi::class.java)

    suspend fun authenticate(email: String, password: String, register: Boolean) = withContext(Dispatchers.IO) {
        val response = perform { if (register) api.register(AuthRequest(email, password)) else api.login(AuthRequest(email, password)) }
        secretStore.setCloudToken(response.token)
    }

    suspend fun upload(password: String): Int = withContext(Dispatchers.IO) {
        val hosts = hostDao.getAll()
        val identities = identityDao.getAll()
        val snippets = snippetDao.getAll()

        val snapshot = VaultSnapshot(
            createdAt = Instant.now().toString(),
            hosts = hosts.map { host ->
                HostVaultRecord(
                    id = host.id.toString(),
                    label = host.label,
                    address = host.address,
                    port = host.port,
                    username = host.username,
                    authMethod = host.authMethodRaw,
                    identityID = host.identityId?.toString(),
                    jumpHostID = host.jumpHostId?.toString(),
                    startupSnippet = host.startupSnippet,
                    groupName = host.groupName,
                    tags = host.tags,
                    themeName = host.themeName,
                    password = secretStore.password(host),
                )
            },
            identities = identities.map { identity ->
                IdentityVaultRecord(
                    id = identity.id.toString(),
                    label = identity.label,
                    keyType = identity.keyTypeRaw,
                    fingerprint = identity.fingerprint,
                    publicKey = identity.publicKey,
                    privateKey = secretStore.privateKeyPem(identity),
                    passphrase = secretStore.passphrase(identity),
                )
            },
            snippets = snippets.map { SnippetVaultRecord(it.id.toString(), it.name, it.command, it.runOnConnect) },
        )

        val current = readEnvelope()
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val key = deriveKey(password, salt)
        val plaintext = json.encodeToString(VaultSnapshot.serializer(), snapshot).toByteArray(Charsets.UTF_8)
        val (ciphertext, tag, nonce) = encrypt(plaintext, key)

        val envelope = VaultEnvelope(
            salt = b64Encode(salt),
            nonce = b64Encode(nonce),
            ciphertext = b64Encode(ciphertext) + "." + b64Encode(tag),
        )
        val result = perform { api.putVault("Bearer ${cloudToken()}", VaultWriteRequest(current.revision, envelope)) }
        result.revision
    }

    /** Decrypts the stored vault and applies it into Room + [SecretStore], mirroring iOS's SwiftData merge. */
    suspend fun restore(password: String): Int = withContext(Dispatchers.IO) {
        val result = readEnvelope()
        val envelope = result.vault ?: throw EmptyVaultException()
        val snapshot = decrypt(envelope, password)

        for (record in snapshot.identities) {
            val id = UUID.fromString(record.id)
            val value = IdentityEntity(
                id = id,
                label = record.label,
                keyTypeRaw = record.keyType,
                fingerprint = record.fingerprint,
                publicKey = record.publicKey,
                hasPassphrase = record.passphrase != null,
            )
            identityDao.upsert(value)
            record.privateKey?.let { secretStore.setPrivateKeyPem(it, value) }
            record.passphrase?.let { secretStore.setPassphrase(it, value) }
        }
        for (record in snapshot.hosts) {
            val id = UUID.fromString(record.id)
            val value = HostEntity(
                id = id,
                label = record.label,
                address = record.address,
                port = record.port,
                username = record.username,
                authMethodRaw = record.authMethod,
                identityId = record.identityID?.let { UUID.fromString(it) },
                jumpHostId = record.jumpHostID?.let { UUID.fromString(it) },
                startupSnippet = record.startupSnippet,
                groupName = record.groupName,
                tags = record.tags,
                themeName = record.themeName,
            )
            hostDao.upsert(value)
            record.password?.let { secretStore.setPassword(it, value) }
        }
        for (record in snapshot.snippets) {
            snippetDao.upsert(
                SnippetEntity(
                    id = UUID.fromString(record.id),
                    name = record.name,
                    command = record.command,
                    runOnConnect = record.runOnConnect,
                )
            )
        }
        result.revision
    }

    private suspend fun readEnvelope(): VaultReadResponse = perform { api.getVault("Bearer ${cloudToken()}") }

    private fun cloudToken(): String = secretStore.cloudToken() ?: throw CloudVaultError("Not signed in to Cloud Vault.")

    private fun decrypt(envelope: VaultEnvelope, password: String): VaultSnapshot {
        val salt = b64Decode(envelope.salt)
        val nonce = b64Decode(envelope.nonce)
        val parts = envelope.ciphertext.split(".")
        if (parts.size != 2) throw CloudVaultError("The cloud vault returned an invalid response.")
        val ciphertext = b64Decode(parts[0])
        val tag = b64Decode(parts[1])
        val key = deriveKey(password, salt)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        val plaintext = cipher.doFinal(ciphertext + tag)
        return json.decodeFromString(VaultSnapshot.serializer(), String(plaintext, Charsets.UTF_8))
    }

    /** Returns (ciphertext, tag, nonce) — Java's GCM cipher appends the 16-byte tag to the ciphertext; this splits them apart to match iOS's separate `ciphertext`/`tag` wire fields. */
    private fun encrypt(plaintext: ByteArray, key: ByteArray): Triple<ByteArray, ByteArray, ByteArray> {
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        val output = cipher.doFinal(plaintext)
        val ciphertext = output.copyOfRange(0, output.size - 16)
        val tag = output.copyOfRange(output.size - 16, output.size)
        return Triple(ciphertext, tag, nonce)
    }

    /** HKDF-SHA256, matching CryptoKit's `HKDF<SHA256>.deriveKey` used on iOS: extract with [salt], expand with the fixed info string, 32-byte output. */
    private fun deriveKey(password: String, salt: ByteArray): ByteArray {
        val generator = HKDFBytesGenerator(SHA256Digest())
        generator.init(HKDFParameters(password.toByteArray(Charsets.UTF_8), salt, "TermVault encrypted cloud vault v1".toByteArray(Charsets.UTF_8)))
        val output = ByteArray(32)
        generator.generateBytes(output, 0, 32)
        return output
    }

    private suspend fun <T> perform(call: suspend () -> T): T {
        try {
            return call()
        } catch (e: HttpException) {
            val body = e.response()?.errorBody()?.string()
            val message = body?.let { runCatching { json.decodeFromString(ErrorResponse.serializer(), it).error }.getOrNull() }
            throw CloudVaultError(message ?: "Cloud vault request failed (HTTP ${e.code()}).")
        }
    }
}
