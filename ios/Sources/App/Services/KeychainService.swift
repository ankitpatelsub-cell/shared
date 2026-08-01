import Foundation
import Security

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
    case itemNotFound
    case unexpectedData
}

/// Thin wrapper over Keychain Services. Every secret (host passwords,
/// private key PEM data, key passphrases) is stored here and *only* here —
/// never in SwiftData, UserDefaults, or a plist. Items are scoped to
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so they never leave the
/// device (no iCloud Keychain sync, no backup restore onto another device).
enum KeychainService {
    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ data: Data, account: String, service: String) throws {
        // Delete-then-add keeps this idempotent without needing a separate
        // "update" code path.
        SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)

        var query = baseQuery(account: account, service: service)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
    }

    static func read(account: String, service: String) throws -> Data {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
        guard let data = result as? Data else { throw KeychainError.unexpectedData }
        return data
    }

    static func delete(account: String, service: String) throws {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }
}

private enum KeychainServiceName {
    static let hostPassword = "dev.termvault.host.password"
    static let identityPrivateKey = "dev.termvault.identity.privatekey"
    static let identityPassphrase = "dev.termvault.identity.passphrase"
    static let githubToken = "dev.termvault.github.token"
}

extension KeychainService {
    static func githubToken() throws -> String {
        let data = try read(account: "github.com", service: KeychainServiceName.githubToken)
        guard let token = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedData }
        return token
    }

    static func setGitHubToken(_ token: String) throws {
        try save(Data(token.utf8), account: "github.com", service: KeychainServiceName.githubToken)
    }

    static func deleteGitHubToken() throws {
        try delete(account: "github.com", service: KeychainServiceName.githubToken)
    }

    static func password(for host: Host) throws -> String {
        let data = try read(account: host.id.uuidString, service: KeychainServiceName.hostPassword)
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedData }
        return string
    }

    static func setPassword(_ password: String, for host: Host) throws {
        try save(Data(password.utf8), account: host.id.uuidString, service: KeychainServiceName.hostPassword)
    }

    static func deletePassword(for host: Host) throws {
        try delete(account: host.id.uuidString, service: KeychainServiceName.hostPassword)
    }

    static func privateKeyPEM(for identity: Identity) throws -> String {
        let data = try read(account: identity.id.uuidString, service: KeychainServiceName.identityPrivateKey)
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedData }
        return string
    }

    static func setPrivateKeyPEM(_ pem: String, for identity: Identity) throws {
        try save(Data(pem.utf8), account: identity.id.uuidString, service: KeychainServiceName.identityPrivateKey)
    }

    static func passphrase(for identity: Identity) throws -> String {
        let data = try read(account: identity.id.uuidString, service: KeychainServiceName.identityPassphrase)
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedData }
        return string
    }

    static func setPassphrase(_ passphrase: String, for identity: Identity) throws {
        try save(Data(passphrase.utf8), account: identity.id.uuidString, service: KeychainServiceName.identityPassphrase)
    }

    static func deleteSecrets(for identity: Identity) throws {
        try delete(account: identity.id.uuidString, service: KeychainServiceName.identityPrivateKey)
        try delete(account: identity.id.uuidString, service: KeychainServiceName.identityPassphrase)
    }
}
