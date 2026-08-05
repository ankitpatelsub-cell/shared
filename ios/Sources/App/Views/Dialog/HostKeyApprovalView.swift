import SwiftUI

struct HostKeyApprovalView: View {
    let host: String
    let port: Int
    let fingerprint: String
    let keyType: String
    let onDecision: (HostKeyApprovalService.ApprovalDecision) -> Void

    @State private var showFullFingerprint = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text("Unknown SSH Host Key")
                                .font(.headline)
                        }
                        Text("This is the first time connecting to this host. Verify the fingerprint matches your expectations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Host Information
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Host")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(host)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Port")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(port)")
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Key Type")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(keyType)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    // Fingerprint
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SHA256 Fingerprint")
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 8) {
                            if showFullFingerprint {
                                Text(fingerprint)
                                    .monospaced()
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                            } else {
                                Text(abbreviatedFingerprint)
                                    .monospaced()
                                    .font(.caption)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)

                                Button(action: { showFullFingerprint = true }) {
                                    Text("Show Full Fingerprint")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    // Warning
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Security Notice")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Only approve this host if you've verified this fingerprint with the server administrator.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Verify Host Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reject") {
                        onDecision(.reject)
                    }
                    .foregroundStyle(.red)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button(action: { onDecision(.trustOnce) }) {
                        Text("Trust This Session")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }

                    Button(action: { onDecision(.trustAlways) }) {
                        Text("Trust Always")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
    }

    private var abbreviatedFingerprint: String {
        let parts = fingerprint.split(separator: ":")
        guard parts.count >= 4 else { return fingerprint }
        return parts.prefix(4).joined(separator: ":") + ":..."
    }
}

#Preview {
    HostKeyApprovalView(
        host: "example.com",
        port: 22,
        fingerprint: "SHA256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        keyType: "ssh-rsa"
    ) { _ in }
}
