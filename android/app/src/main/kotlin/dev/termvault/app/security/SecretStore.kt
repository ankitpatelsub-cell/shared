package dev.termvault.app.security

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.IdentityEntity

/**
 * Every secret (host passwords, private key PEM, key passphrases, the
 * GitHub PAT, the cloud-vault session token) lives here and *only* here —
 * mirrors iOS `KeychainService.swift`. Backed by Android Keystore via
 * [EncryptedSharedPreferences] rather than SwiftData/plain SharedPreferences,
 * so a rooted-device file read of the prefs XML doesn't expose plaintext.
 */
class SecretStore(context: Context) {
    private val prefs: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "dev.termvault.secrets",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    private fun key(service: String, account: String) = "$service:$account"

    private fun read(service: String, account: String): String? = prefs.getString(key(service, account), null)

    private fun write(service: String, account: String, value: String) {
        prefs.edit().putString(key(service, account), value).apply()
    }

    private fun remove(service: String, account: String) {
        prefs.edit().remove(key(service, account)).apply()
    }

    fun password(host: HostEntity): String? = read(SERVICE_HOST_PASSWORD, host.id.toString())
    fun setPassword(password: String, host: HostEntity) = write(SERVICE_HOST_PASSWORD, host.id.toString(), password)
    fun deletePassword(host: HostEntity) = remove(SERVICE_HOST_PASSWORD, host.id.toString())

    fun privateKeyPem(identity: IdentityEntity): String? = read(SERVICE_IDENTITY_KEY, identity.id.toString())
    fun setPrivateKeyPem(pem: String, identity: IdentityEntity) = write(SERVICE_IDENTITY_KEY, identity.id.toString(), pem)

    fun passphrase(identity: IdentityEntity): String? = read(SERVICE_IDENTITY_PASSPHRASE, identity.id.toString())
    fun setPassphrase(passphrase: String, identity: IdentityEntity) =
        write(SERVICE_IDENTITY_PASSPHRASE, identity.id.toString(), passphrase)

    fun deleteSecrets(identity: IdentityEntity) {
        remove(SERVICE_IDENTITY_KEY, identity.id.toString())
        remove(SERVICE_IDENTITY_PASSPHRASE, identity.id.toString())
    }

    fun githubToken(): String? = read(SERVICE_GITHUB_TOKEN, "github.com")
    fun setGitHubToken(token: String) = write(SERVICE_GITHUB_TOKEN, "github.com", token)
    fun deleteGitHubToken() = remove(SERVICE_GITHUB_TOKEN, "github.com")

    fun cloudToken(): String? = read(SERVICE_CLOUD_TOKEN, "masystem.co.in")
    fun setCloudToken(token: String) = write(SERVICE_CLOUD_TOKEN, "masystem.co.in", token)
    fun deleteCloudToken() = remove(SERVICE_CLOUD_TOKEN, "masystem.co.in")

    companion object {
        private const val SERVICE_HOST_PASSWORD = "dev.termvault.host.password"
        private const val SERVICE_IDENTITY_KEY = "dev.termvault.identity.privatekey"
        private const val SERVICE_IDENTITY_PASSPHRASE = "dev.termvault.identity.passphrase"
        private const val SERVICE_GITHUB_TOKEN = "dev.termvault.github.token"
        private const val SERVICE_CLOUD_TOKEN = "dev.termvault.cloud.token"
    }
}
