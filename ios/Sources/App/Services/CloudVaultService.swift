import CryptoKit
import Foundation
import SwiftData

enum CloudVaultError: Error, LocalizedError {
    case invalidResponse
    case server(String)
    case emptyVault

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The cloud vault returned an invalid response."
        case .server(let message): return message
        case .emptyVault: return "No encrypted vault has been uploaded yet."
        }
    }
}

private struct HostVaultRecord: Codable {
    var id: UUID; var label: String; var address: String; var port: Int; var username: String
    var authMethod: HostAuthMethod; var identityID: UUID?; var startupSnippet: String?
    var groupName: String?; var tags: [String]; var themeName: String?; var password: String?
}

private struct IdentityVaultRecord: Codable {
    var id: UUID; var label: String; var keyType: IdentityKeyType; var fingerprint: String
    var publicKey: String; var privateKey: String?; var passphrase: String?
}

private struct SnippetVaultRecord: Codable {
    var id: UUID; var name: String; var command: String; var runOnConnect: Bool
}

private struct VaultSnapshot: Codable {
    var version = 1
    var createdAt = Date()
    var hosts: [HostVaultRecord]
    var identities: [IdentityVaultRecord]
    var snippets: [SnippetVaultRecord]
}

private struct AuthResponse: Decodable { let token: String }
private struct VaultEnvelope: Codable { let salt: String; let nonce: String; let ciphertext: String }
private struct VaultReadResponse: Decodable { let revision: Int; let vault: VaultEnvelope? }
private struct VaultWriteRequest: Encodable { let revision: Int; let vault: VaultEnvelope }
private struct VaultWriteResponse: Decodable { let revision: Int }

@MainActor
final class CloudVaultService {
    static let shared = CloudVaultService()
    private let baseURL = URL(string: "https://masystem.co.in/termvault-api")!

    func authenticate(email: String, password: String, register: Bool) async throws {
        var request = URLRequest(url: baseURL.appending(path: register ? "v1/register" : "v1/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        let response: AuthResponse = try await perform(request)
        try KeychainService.setCloudToken(response.token)
    }

    func upload(hosts: [Host], identities: [Identity], snippets: [Snippet], password: String) async throws -> Int {
        let snapshot = VaultSnapshot(
            hosts: hosts.map { host in
                HostVaultRecord(
                    id: host.id, label: host.label, address: host.address, port: host.port,
                    username: host.username, authMethod: host.authMethod, identityID: host.identityID,
                    startupSnippet: host.startupSnippet, groupName: host.groupName, tags: host.tags,
                    themeName: host.themeName, password: try? KeychainService.password(for: host)
                )
            },
            identities: identities.map { identity in
                IdentityVaultRecord(
                    id: identity.id, label: identity.label, keyType: identity.keyType,
                    fingerprint: identity.fingerprint, publicKey: identity.publicKey,
                    privateKey: try? KeychainService.privateKeyPEM(for: identity),
                    passphrase: try? KeychainService.passphrase(for: identity)
                )
            },
            snippets: snippets.map { SnippetVaultRecord(id: $0.id, name: $0.name, command: $0.command, runOnConnect: $0.runOnConnect) }
        )
        let current = try await readEnvelope()
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let key = deriveKey(password: password, salt: salt)
        let plaintext = try JSONEncoder.vaultEncoder.encode(snapshot)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        let envelope = VaultEnvelope(
            salt: salt.base64EncodedString(), nonce: Data(sealed.nonce).base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString() + "." + sealed.tag.base64EncodedString()
        )
        var request = try authorizedRequest(path: "v1/vault", method: "PUT")
        request.httpBody = try JSONEncoder().encode(VaultWriteRequest(revision: current.revision, vault: envelope))
        let result: VaultWriteResponse = try await perform(request)
        return result.revision
    }

    func restore(into context: ModelContext, password: String) async throws -> Int {
        let result = try await readEnvelope()
        guard let envelope = result.vault else { throw CloudVaultError.emptyVault }
        let snapshot = try decrypt(envelope, password: password)
        let existingHosts = try context.fetch(FetchDescriptor<Host>())
        let existingIdentities = try context.fetch(FetchDescriptor<Identity>())
        let existingSnippets = try context.fetch(FetchDescriptor<Snippet>())

        for record in snapshot.identities {
            let value = existingIdentities.first { $0.id == record.id } ?? Identity(
                id: record.id, label: record.label, keyType: record.keyType,
                fingerprint: record.fingerprint, publicKey: record.publicKey,
                hasPassphrase: record.passphrase != nil
            )
            value.label = record.label; value.keyType = record.keyType
            value.fingerprint = record.fingerprint; value.publicKey = record.publicKey
            value.hasPassphrase = record.passphrase != nil
            if !existingIdentities.contains(where: { $0.id == record.id }) { context.insert(value) }
            if let privateKey = record.privateKey { try KeychainService.setPrivateKeyPEM(privateKey, for: value) }
            if let passphrase = record.passphrase { try KeychainService.setPassphrase(passphrase, for: value) }
        }
        for record in snapshot.hosts {
            let value = existingHosts.first { $0.id == record.id } ?? Host(
                id: record.id, label: record.label, address: record.address, port: record.port,
                username: record.username, authMethod: record.authMethod, identityID: record.identityID
            )
            value.label = record.label; value.address = record.address; value.port = record.port
            value.username = record.username; value.authMethod = record.authMethod
            value.identityID = record.identityID; value.startupSnippet = record.startupSnippet
            value.groupName = record.groupName; value.tags = record.tags; value.themeName = record.themeName
            if !existingHosts.contains(where: { $0.id == record.id }) { context.insert(value) }
            if let password = record.password { try KeychainService.setPassword(password, for: value) }
        }
        for record in snapshot.snippets {
            let value = existingSnippets.first { $0.id == record.id } ?? Snippet(
                id: record.id, name: record.name, command: record.command, runOnConnect: record.runOnConnect
            )
            value.name = record.name; value.command = record.command; value.runOnConnect = record.runOnConnect
            if !existingSnippets.contains(where: { $0.id == record.id }) { context.insert(value) }
        }
        try context.save()
        return result.revision
    }

    private func readEnvelope() async throws -> VaultReadResponse {
        try await perform(authorizedRequest(path: "v1/vault", method: "GET"))
    }

    private func decrypt(_ envelope: VaultEnvelope, password: String) throws -> VaultSnapshot {
        guard let salt = Data(base64Encoded: envelope.salt),
              let nonceData = Data(base64Encoded: envelope.nonce) else { throw CloudVaultError.invalidResponse }
        let parts = envelope.ciphertext.split(separator: ".")
        guard parts.count == 2, let ciphertext = Data(base64Encoded: String(parts[0])),
              let tag = Data(base64Encoded: String(parts[1])) else { throw CloudVaultError.invalidResponse }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceData), ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(box, using: deriveKey(password: password, salt: salt))
        return try JSONDecoder.vaultDecoder.decode(VaultSnapshot.self, from: plaintext)
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)), salt: salt,
            info: Data("TermVault encrypted cloud vault v1".utf8), outputByteCount: 32
        )
    }

    private func authorizedRequest(path: String, method: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(try KeychainService.cloudToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudVaultError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let value = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
            throw CloudVaultError.server(value ?? "Cloud vault request failed (HTTP \(http.statusCode)).")
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

private extension JSONEncoder {
    static var vaultEncoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
}

private extension JSONDecoder {
    static var vaultDecoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
