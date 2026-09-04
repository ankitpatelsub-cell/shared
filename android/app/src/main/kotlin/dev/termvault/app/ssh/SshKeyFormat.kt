package dev.termvault.app.ssh

import android.util.Base64
import java.math.BigInteger
import java.security.MessageDigest

/** SSH wire-format helpers — same "string"/"mpint" encoding as iOS `SSHWire`/`SSHKeyFormat`. */
object SshWire {
    fun string(bytes: ByteArray): ByteArray = uint32(bytes.size) + bytes
    fun string(text: String): ByteArray = string(text.toByteArray(Charsets.UTF_8))

    fun uint32(value: Int): ByteArray = byteArrayOf(
        (value ushr 24).toByte(),
        (value ushr 16).toByte(),
        (value ushr 8).toByte(),
        value.toByte(),
    )

    /** SSH "mpint": big-endian, minimal, signed two's-complement (leading 0x00 if the high bit would read negative). */
    fun mpint(bytes: ByteArray): ByteArray {
        var trimmed = bytes.dropWhile { it == 0.toByte() }
        if (trimmed.isEmpty()) trimmed = listOf(0.toByte())
        if ((trimmed.first().toInt() and 0x80) != 0) {
            trimmed = listOf(0.toByte()) + trimmed
        }
        return string(trimmed.toByteArray())
    }

    fun mpint(value: BigInteger): ByteArray = mpint(value.toByteArray())
}

object SshKeyFormat {
    /** Standard OpenSSH fingerprint format, matching `ssh-keygen -lf`. */
    fun fingerprint(publicKeyBlob: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(publicKeyBlob)
        val encoded = Base64.encodeToString(digest, Base64.NO_WRAP or Base64.NO_PADDING)
        return "SHA256:$encoded"
    }

    fun pem(label: String, der: ByteArray): String {
        val base64 = Base64.encodeToString(der, Base64.NO_WRAP)
        val lines = base64.chunked(64)
        return "-----BEGIN $label-----\n" + lines.joinToString("\n") + "\n-----END $label-----\n"
    }
}
