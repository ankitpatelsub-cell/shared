import Foundation
import Crypto

/// Low-level helpers for encoding SSH's wire format: the same
/// length-prefixed "string" and big-endian "mpint" encodings used both in
/// `authorized_keys`-style public key blobs and in the `openssh-key-v1`
/// private key container.
enum SSHWire {
    static func string(_ bytes: [UInt8]) -> [UInt8] {
        uint32(UInt32(bytes.count)) + bytes
    }

    static func string(_ data: Data) -> [UInt8] { string(Array(data)) }
    static func string(_ text: String) -> [UInt8] { string(Array(text.utf8)) }

    static func uint32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    }

    /// SSH "mpint": big-endian, minimal-length, with a leading 0x00 byte
    /// inserted if the high bit of the first byte would otherwise make an
    /// unsigned value read as negative (SSH mpints are signed two's
    /// complement).
    static func mpint(_ bytes: [UInt8]) -> [UInt8] {
        var trimmed = Array(bytes.drop { $0 == 0 })
        if trimmed.isEmpty { trimmed = [0] }
        if let first = trimmed.first, first & 0x80 != 0 {
            trimmed.insert(0, at: 0)
        }
        return string(trimmed)
    }
}

enum SSHKeyFormatError: Error, LocalizedError {
    case derParsingFailed
    case unsupportedKeyType

    var errorDescription: String? {
        switch self {
        case .derParsingFailed: return "Could not parse the generated key's DER encoding."
        case .unsupportedKeyType: return "Unsupported SSH key type."
        }
    }
}

enum SSHKeyFormat {
    /// The standard OpenSSH fingerprint format: `SHA256:<base64-no-padding>`
    /// of the public key blob, matching what `ssh-keygen -lf` prints.
    static func fingerprint(publicKeyBlob: [UInt8]) -> String {
        let digest = SHA256.hash(data: Data(publicKeyBlob))
        let base64 = Data(digest).base64EncodedString()
        let trimmed = base64.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(trimmed)"
    }

    static func pem(label: String, derBytes: [UInt8]) -> String {
        let base64 = Data(derBytes).base64EncodedString()
        var lines: [String] = []
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<end]))
            index = end
        }
        return "-----BEGIN \(label)-----\n" + lines.joined(separator: "\n") + "\n-----END \(label)-----\n"
    }
}
