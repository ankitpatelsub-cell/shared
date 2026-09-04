package dev.termvault.app.ssh

import android.util.Base64
import net.schmizz.sshj.common.Buffer
import net.schmizz.sshj.transport.verification.HostKeyVerifier
import java.security.MessageDigest
import java.security.PublicKey

/**
 * Trust-on-first-use host key validation — mirrors iOS
 * `TOFUHostKeyValidator.swift`. Pins the fingerprint of the first key seen
 * for a host:port and hard-fails a later connection whose key changed.
 *
 * Same scope note as the iOS version: this auto-trusts a *new* key
 * silently (matching classic `known_hosts` first-connect behavior) rather
 * than prompting before trusting it — only a *changed* key is rejected.
 * Wiring a confirm-before-trust prompt would mean blocking sshj's
 * connection thread (this callback is synchronous) on a Compose dialog
 * result, which is real future work, not something either client does today.
 */
class TofuHostKeyVerifier(
    private val host: String,
    private val port: Int,
    private val store: HostKeyStore,
) : HostKeyVerifier {

    override fun verify(hostname: String, port: Int, key: PublicKey): Boolean {
        val fingerprint = fingerprint(key)
        return when (val verdict = store.evaluate(fingerprint, host, this.port)) {
            is HostKeyStore.Verdict.TrustedNew -> {
                store.trust(fingerprint, host, this.port)
                true
            }
            is HostKeyStore.Verdict.TrustedMatch -> true
            is HostKeyStore.Verdict.Mismatch -> false
        }
    }

    override fun findExistingAlgorithms(hostname: String, port: Int): List<String> = emptyList()

    companion object {
        fun fingerprint(key: PublicKey): String {
            val blob = Buffer.PlainBuffer().putPublicKey(key).compactData
            val digest = MessageDigest.getInstance("SHA-256").digest(blob)
            val encoded = Base64.encodeToString(digest, Base64.NO_WRAP or Base64.NO_PADDING)
            return "SHA256:$encoded"
        }
    }
}
