import SwiftUI
import Citadel

/// SFTP rides the same SSH connection the terminal session already has
/// open. This view just waits for that connected `SSHClient` to be
/// available from the actor before handing it to `SFTPBrowserView`.
struct SFTPGateView: View {
    let host: Host
    let connectionID: UUID
    var onLaunch: ((String, AgentTool) -> Void)? = nil
    var onLaunchPreset: ((String, AgentPreset) -> Void)? = nil
    @State private var sshClient: SSHClient?
    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let sshClient {
                SFTPBrowserView(host: host, connectionID: connectionID, sshClient: sshClient, onLaunch: onLaunch, onLaunchPreset: onLaunchPreset)
            } else {
                ContentUnavailableView {
                    Label(errorMessage == nil ? "Connecting" : "SFTP Unavailable", systemImage: errorMessage == nil ? "network" : "exclamationmark.triangle")
                } description: {
                    Text(errorMessage ?? "Waiting for the SSH connection…")
                } actions: {
                    if errorMessage != nil {
                        Button("Retry") {
                            errorMessage = nil
                            attempt += 1
                        }
                    }
                }
                .overlay { if errorMessage == nil { ProgressView().offset(y: 70) } }
                .task(id: attempt) { await waitForConnection() }
            }
        }
    }

    private func waitForConnection() async {
        for _ in 0..<50 {
            if let client = await SSHSessionManager.shared.session(for: connectionID) {
                sshClient = client
                return
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        errorMessage = "The SSH connection did not become ready within 10 seconds."
    }
}
