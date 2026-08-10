package dev.termvault.app.ssh

import android.content.Context

/**
 * Trust-on-first-use (TOFU) host key store — the same model OpenSSH's
 * `known_hosts` uses. Mirrors iOS `HostKeyStore.swift`. Fingerprints
 * aren't secret, so a plain (unencrypted) SharedPreferences file is fine
 * here, unlike [dev.termvault.app.security.SecretStore].
 */
class HostKeyStore(context: Context) {
    sealed class Verdict {
        object TrustedNew : Verdict()
        object TrustedMatch : Verdict()
        data class Mismatch(val previous: String) : Verdict()
    }

    private val prefs = context.getSharedPreferences("dev.termvault.hostkeys", Context.MODE_PRIVATE)

    private fun key(host: String, port: Int) = "$host:$port"

    fun knownFingerprint(host: String, port: Int): String? = prefs.getString(key(host, port), null)

    fun evaluate(fingerprint: String, host: String, port: Int): Verdict {
        val known = knownFingerprint(host, port) ?: return Verdict.TrustedNew
        return if (known == fingerprint) Verdict.TrustedMatch else Verdict.Mismatch(known)
    }

    fun trust(fingerprint: String, host: String, port: Int) {
        prefs.edit().putString(key(host, port), fingerprint).apply()
    }

    fun forget(host: String, port: Int) {
        prefs.edit().remove(key(host, port)).apply()
    }
}
