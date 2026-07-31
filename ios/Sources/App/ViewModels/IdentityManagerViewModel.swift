import Foundation
import SwiftData

@MainActor
final class IdentityManagerViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var lastGeneratedPrivateKeyPEM: String?

    func generateKey(label: String, type: IdentityKeyType, passphrase: String?, context: ModelContext) {
        do {
            let generated: IdentityKeyGenerator.GeneratedKey
            switch type {
            case .ed25519:
                generated = IdentityKeyGenerator.generateEd25519(comment: label)
            case .rsa4096:
                generated = try IdentityKeyGenerator.generateRSA4096(comment: label)
            }

            let identity = Identity(
                label: label,
                keyType: type,
                fingerprint: generated.fingerprint,
                publicKey: generated.publicKeyLine,
                hasPassphrase: passphrase?.isEmpty == false
            )

            try KeychainService.setPrivateKeyPEM(generated.privateKeyPEM, for: identity)
            if let passphrase, !passphrase.isEmpty {
                try KeychainService.setPassphrase(passphrase, for: identity)
            }

            context.insert(identity)
            lastGeneratedPrivateKeyPEM = generated.privateKeyPEM
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importKey(
        label: String,
        type: IdentityKeyType,
        privateKeyPEM: String,
        publicKeyLine: String,
        passphrase: String?,
        context: ModelContext
    ) {
        let fingerprint = Self.fingerprint(fromPublicKeyLine: publicKeyLine) ?? "unknown"
        let identity = Identity(
            label: label,
            keyType: type,
            fingerprint: fingerprint,
            publicKey: publicKeyLine,
            hasPassphrase: passphrase?.isEmpty == false
        )
        do {
            try KeychainService.setPrivateKeyPEM(privateKeyPEM, for: identity)
            if let passphrase, !passphrase.isEmpty {
                try KeychainService.setPassphrase(passphrase, for: identity)
            }
            context.insert(identity)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ identity: Identity, context: ModelContext) {
        try? KeychainService.deleteSecrets(for: identity)
        context.delete(identity)
    }

    private static func fingerprint(fromPublicKeyLine line: String) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let data = Data(base64Encoded: String(parts[1])) else { return nil }
        return SSHKeyFormat.fingerprint(publicKeyBlob: Array(data))
    }
}
