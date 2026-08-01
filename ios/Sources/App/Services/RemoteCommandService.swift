import Foundation
import Citadel
import NIOCore

enum RemoteCommandError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? { "Connect to the host before running project commands." }
}

actor RemoteCommandService {
    static let shared = RemoteCommandService()

    func run(hostID: UUID, command: String, maxResponseSize: Int = 1_048_576) async throws -> String {
        guard let client = await SSHSessionManager.shared.session(forHostID: hostID) else {
            throw RemoteCommandError.notConnected
        }
        let buffer = try await client.executeCommand(
            command,
            maxResponseSize: maxResponseSize,
            mergeStreams: true
        )
        return String(decoding: buffer.readableBytesView, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
