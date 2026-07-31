import Foundation
import Crypto
import Security

/// Generates local SSH key pairs for the Identity Manager screen.
///
/// Ed25519 keys are encoded as a real (unencrypted) `openssh-key-v1`
/// container — the same format `ssh-keygen -t ed25519` produces. If a
/// passphrase is supplied it's stored in the Keychain alongside the key for
/// app-level gating, but this generator does not yet apply the
/// bcrypt-pbkdf + aes256-ctr encryption OpenSSH uses to protect the private
/// section on disk; add that before treating passphrase-protected keys as
/// protecting anything beyond the app sandbox.
///
/// RSA 4096 keys use `SecKey`, whose RSA external representation is
/// PKCS#1 DER — valid as a standard `-----BEGIN RSA PRIVATE KEY-----` PEM
/// that OpenSSH and most SSH libraries accept directly.
enum IdentityKeyGenerator {
    struct GeneratedKey {
        let privateKeyPEM: String
        let publicKeyLine: String
        let fingerprint: String
    }

    static func generateEd25519(comment: String) -> GeneratedKey {
        let privateKey = Curve25519.Signing.PrivateKey()
        let seed = Array(privateKey.rawRepresentation)
        let publicKeyBytes = Array(privateKey.publicKey.rawRepresentation)

        let publicBlob = SSHWire.string("ssh-ed25519") + SSHWire.string(publicKeyBytes)
        let publicKeyLine = "ssh-ed25519 \(Data(publicBlob).base64EncodedString()) \(comment)"
        let fingerprint = SSHKeyFormat.fingerprint(publicKeyBlob: publicBlob)

        var magic = Array("openssh-key-v1".utf8)
        magic.append(0)

        var body: [UInt8] = []
        body += SSHWire.string("none") // ciphername
        body += SSHWire.string("none") // kdfname
        body += SSHWire.string([])     // kdfoptions
        body += SSHWire.uint32(1)      // number of keys
        body += SSHWire.string(publicBlob)

        let checkInt = UInt32.random(in: 0...UInt32.max)
        var privateSection: [UInt8] = []
        privateSection += SSHWire.uint32(checkInt)
        privateSection += SSHWire.uint32(checkInt)
        privateSection += SSHWire.string("ssh-ed25519")
        privateSection += SSHWire.string(publicKeyBytes)
        privateSection += SSHWire.string(seed + publicKeyBytes) // 64-byte expanded secret
        privateSection += SSHWire.string(comment)

        var padByte: UInt8 = 1
        while privateSection.count % 8 != 0 {
            privateSection.append(padByte)
            padByte += 1
        }
        body += SSHWire.string(privateSection)

        let pem = SSHKeyFormat.pem(label: "OPENSSH PRIVATE KEY", derBytes: magic + body)
        return GeneratedKey(privateKeyPEM: pem, publicKeyLine: publicKeyLine, fingerprint: fingerprint)
    }

    static func generateRSA4096(comment: String) throws -> GeneratedKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 4096,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SSHKeyFormatError.derParsingFailed
        }
        guard let privateDER = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }
        guard let publicDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }

        let privatePEM = SSHKeyFormat.pem(label: "RSA PRIVATE KEY", derBytes: Array(privateDER))

        let (modulus, exponent) = try parseRSAPublicKeyDER(Array(publicDER))
        let publicBlob = SSHWire.string("ssh-rsa") + SSHWire.mpint(exponent) + SSHWire.mpint(modulus)
        let publicKeyLine = "ssh-rsa \(Data(publicBlob).base64EncodedString()) \(comment)"
        let fingerprint = SSHKeyFormat.fingerprint(publicKeyBlob: publicBlob)

        return GeneratedKey(privateKeyPEM: privatePEM, publicKeyLine: publicKeyLine, fingerprint: fingerprint)
    }

    /// Minimal ASN.1 DER parser for `RSAPublicKey ::= SEQUENCE { modulus
    /// INTEGER, publicExponent INTEGER }` — the only shape
    /// `SecKeyCopyExternalRepresentation` returns for an RSA public key, so
    /// a general-purpose DER/BER parser isn't needed here.
    private static func parseRSAPublicKeyDER(_ bytes: [UInt8]) throws -> (modulus: [UInt8], exponent: [UInt8]) {
        var index = 0

        func readLength() throws -> Int {
            guard index < bytes.count else { throw SSHKeyFormatError.derParsingFailed }
            let first = bytes[index]; index += 1
            if first & 0x80 == 0 { return Int(first) }
            let byteCount = Int(first & 0x7f)
            guard byteCount > 0, index + byteCount <= bytes.count else { throw SSHKeyFormatError.derParsingFailed }
            var length = 0
            for _ in 0..<byteCount {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
            return length
        }

        func readTag(_ expected: UInt8) throws -> Int {
            guard index < bytes.count, bytes[index] == expected else { throw SSHKeyFormatError.derParsingFailed }
            index += 1
            return try readLength()
        }

        _ = try readTag(0x30) // SEQUENCE

        let modLength = try readTag(0x02) // INTEGER: modulus
        guard index + modLength <= bytes.count else { throw SSHKeyFormatError.derParsingFailed }
        let modulus = Array(bytes[index..<index + modLength])
        index += modLength

        let expLength = try readTag(0x02) // INTEGER: publicExponent
        guard index + expLength <= bytes.count else { throw SSHKeyFormatError.derParsingFailed }
        let exponent = Array(bytes[index..<index + expLength])
        index += expLength

        return (modulus, exponent)
    }
}

enum OpenSSHKeyParsingError: Error, LocalizedError {
    case invalidPEM
    case unsupportedCipher
    case unsupportedKeyType
    case truncated

    var errorDescription: String? {
        switch self {
        case .invalidPEM:
            return "Could not parse this OpenSSH private key."
        case .unsupportedCipher:
            return "Encrypted OpenSSH private keys aren't supported yet — re-export without a passphrase (ssh-keygen -p -N \"\"), or generate the key in TermVault directly."
        case .unsupportedKeyType:
            return "Only Ed25519 keys can be used for SSH authentication right now — Citadel's RSA private-key type has no way to import a standard PEM through its public API."
        case .truncated:
            return "This OpenSSH private key is truncated or corrupt."
        }
    }
}

extension IdentityKeyGenerator {
    /// Reverses `generateEd25519`'s `openssh-key-v1` encoding to recover the
    /// raw 32-byte seed, which is what `Curve25519.Signing.PrivateKey`
    /// needs. Only handles the unencrypted case (`cipher "none"`) — the
    /// same limitation `generateEd25519` has on the write side. Real
    /// `ssh-keygen`-produced unencrypted Ed25519 keys parse fine too, since
    /// this follows the same openssh-key-v1 container format they use.
    static func parseEd25519PrivateKey(pem: String) throws -> Curve25519.Signing.PrivateKey {
        let body = pem
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: body) else { throw OpenSSHKeyParsingError.invalidPEM }
        let bytes = Array(data)

        var magic = Array("openssh-key-v1".utf8)
        magic.append(0)
        guard bytes.count > magic.count, Array(bytes.prefix(magic.count)) == magic else {
            throw OpenSSHKeyParsingError.invalidPEM
        }

        var reader = ByteReader(bytes: bytes, offset: magic.count)
        let cipherName = String(decoding: try reader.readString(), as: UTF8.self)
        let kdfName = String(decoding: try reader.readString(), as: UTF8.self)
        _ = try reader.readString() // kdfoptions
        guard cipherName == "none", kdfName == "none" else {
            throw OpenSSHKeyParsingError.unsupportedCipher
        }

        let keyCount = try reader.readUInt32()
        guard keyCount == 1 else { throw OpenSSHKeyParsingError.invalidPEM }
        _ = try reader.readString() // public key blob (re-derived from the private section below)

        var privateReader = ByteReader(bytes: try reader.readString(), offset: 0)
        _ = try privateReader.readUInt32() // checkint1
        _ = try privateReader.readUInt32() // checkint2

        let keyType = String(decoding: try privateReader.readString(), as: UTF8.self)
        guard keyType == "ssh-ed25519" else { throw OpenSSHKeyParsingError.unsupportedKeyType }
        _ = try privateReader.readString() // public key (32 bytes)

        let expanded = try privateReader.readString() // 64 bytes: seed (32) + public key (32)
        guard expanded.count == 64 else { throw OpenSSHKeyParsingError.truncated }
        let seed = Array(expanded.prefix(32))

        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }

    private struct ByteReader {
        let bytes: [UInt8]
        var offset: Int

        mutating func readUInt32() throws -> UInt32 {
            guard offset + 4 <= bytes.count else { throw OpenSSHKeyParsingError.truncated }
            let value = (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
            offset += 4
            return value
        }

        mutating func readString() throws -> [UInt8] {
            let length = Int(try readUInt32())
            guard length >= 0, offset + length <= bytes.count else { throw OpenSSHKeyParsingError.truncated }
            let value = Array(bytes[offset..<offset + length])
            offset += length
            return value
        }
    }
}
