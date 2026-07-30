import SwiftUI
import Citadel

/// SFTP rides the same SSH connection the terminal session already has
/// open. This view just waits for that connected `SSHClient` to be
/// available from the actor before handing it to `SFTPBrowserView`.
struct SFTPGateView: View {
    let host: Host
    @State private var sshClient: SSHClient?
    @State private var isConnected = false

    var body: some View {
        Group {
            if let sshClient {
                SFTPBrowserView(host: host, sshClient: sshClient)
            } else {
                ProgressView("Waiting for connection…")
                    .task {
                        // The terminal session connects asynchronously;
                        // poll briefly rather than assuming it's already
                        // up by the time this sheet appears.
                        for _ in 0..<50 {
                            if let client = await SSHSessionManager.shared.session(for: host.id) {
                                sshClient = client
                                return
                            }
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                    }
            }
        }
    }
}
