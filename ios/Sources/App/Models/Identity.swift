import Foundation
import SwiftData

enum IdentityKeyType: String, Codable, CaseIterable, Identifiable {
    case rsa4096
    case ed25519

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rsa4096: return "RSA 4096"
        case .ed25519: return "Ed25519"
        }
    }
}

/// Metadata only. The private key material and its passphrase are never
/// stored here — they live exclusively in the Keychain, keyed by `id`.
@Model
final class Identity {
    @Attribute(.unique) var id: UUID
    var label: String
    var keyTypeRaw: String
    var fingerprint: String
    var publicKey: String
    var hasPassphrase: Bool
    var createdAt: Date

    var keyType: IdentityKeyType {
        get { IdentityKeyType(rawValue: keyTypeRaw) ?? .ed25519 }
        set { keyTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        label: String,
        keyType: IdentityKeyType,
        fingerprint: String,
        publicKey: String,
        hasPassphrase: Bool = false
    ) {
        self.id = id
        self.label = label
        self.keyTypeRaw = keyType.rawValue
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.hasPassphrase = hasPassphrase
        self.createdAt = Date()
    }
}
