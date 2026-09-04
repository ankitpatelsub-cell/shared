package dev.termvault.app.ssh

import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.Security
import java.security.interfaces.RSAPublicKey

data class GeneratedKey(val privateKeyPem: String, val publicKeyLine: String, val fingerprint: String)

/**
 * Generates local SSH key pairs for the Identity Manager screen. Mirrors
 * iOS `IdentityKeyGenerator.swift`, but — unlike iOS, where a hand-rolled
 * parser was needed to read the key back for authentication — sshj parses
 * both formats generated here directly (see `SshSessionManager.authenticate`),
 * so there's no matching "parse back" function needed on this side.
 *
 * Ed25519 keys are encoded as a real `openssh-key-v1` container (the same
 * format `ssh-keygen -t ed25519` produces), built from BouncyCastle's raw
 * 32-byte seed/public key — deliberately using BC's low-level
 * `Ed25519PrivateKeyParameters` API rather than the JCA `KeyPairGenerator`
 * wrapper, since the JCA path's `PrivateKey.getEncoded()` returns a PKCS8
 * -wrapped form and this format needs the bare seed.
 *
 * RSA 4096 keys use the standard JCA `KeyPairGenerator`, whose default
 * PKCS8 DER encoding is exactly what sshj's `PKCS8KeyFile` expects.
 */
object IdentityKeyGenerator {
    init {
        if (Security.getProvider("BC") == null) {
            Security.addProvider(BouncyCastleProvider())
        }
    }

    fun generateEd25519(comment: String): GeneratedKey {
        val generator = Ed25519KeyPairGenerator()
        generator.init(Ed25519KeyGenerationParameters(SecureRandom()))
        val keyPair = generator.generateKeyPair()
        val privateParams = keyPair.private as Ed25519PrivateKeyParameters
        val publicParams = keyPair.public as Ed25519PublicKeyParameters

        val seed = privateParams.encoded
        val publicKeyBytes = publicParams.encoded

        val publicBlob = SshWire.string("ssh-ed25519") + SshWire.string(publicKeyBytes)
        val publicKeyLine = "ssh-ed25519 ${b64(publicBlob)} $comment"
        val fingerprint = SshKeyFormat.fingerprint(publicBlob)

        val magic = "openssh-key-v1".toByteArray(Charsets.UTF_8) + byteArrayOf(0)

        var body = ByteArray(0)
        body += SshWire.string("none") // ciphername
        body += SshWire.string("none") // kdfname
        body += SshWire.string(ByteArray(0)) // kdfoptions
        body += SshWire.uint32(1) // number of keys
        body += SshWire.string(publicBlob)

        val checkInt = SecureRandom().nextInt()
        var privateSection = ByteArray(0)
        privateSection += SshWire.uint32(checkInt)
        privateSection += SshWire.uint32(checkInt)
        privateSection += SshWire.string("ssh-ed25519")
        privateSection += SshWire.string(publicKeyBytes)
        privateSection += SshWire.string(seed + publicKeyBytes) // 64-byte expanded secret
        privateSection += SshWire.string(comment)

        var padByte = 1
        val padding = mutableListOf<Byte>()
        while ((privateSection.size + padding.size) % 8 != 0) {
            padding.add(padByte.toByte())
            padByte++
        }
        privateSection += padding.toByteArray()
        body += SshWire.string(privateSection)

        val pem = SshKeyFormat.pem("OPENSSH PRIVATE KEY", magic + body)
        return GeneratedKey(pem, publicKeyLine, fingerprint)
    }

    fun generateRsa4096(comment: String): GeneratedKey {
        val generator = KeyPairGenerator.getInstance("RSA")
        generator.initialize(4096)
        val keyPair = generator.generateKeyPair()

        val privatePem = SshKeyFormat.pem("PRIVATE KEY", keyPair.private.encoded)

        val publicKey = keyPair.public as RSAPublicKey
        val publicBlob = SshWire.string("ssh-rsa") +
            SshWire.mpint(publicKey.publicExponent) +
            SshWire.mpint(publicKey.modulus)
        val publicKeyLine = "ssh-rsa ${b64(publicBlob)} $comment"
        val fingerprint = SshKeyFormat.fingerprint(publicBlob)

        return GeneratedKey(privatePem, publicKeyLine, fingerprint)
    }

    /** Derives a fingerprint from an imported `ssh-ed25519`/`ssh-rsa ...` public key line. */
    fun fingerprintFromPublicKeyLine(line: String): String? {
        val parts = line.trim().split(" ")
        if (parts.size < 2) return null
        val blob = runCatching { android.util.Base64.decode(parts[1], android.util.Base64.DEFAULT) }.getOrNull()
            ?: return null
        return SshKeyFormat.fingerprint(blob)
    }

    private fun b64(bytes: ByteArray): String =
        android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
}
