import SwiftUI
import SwiftData

struct HostStatusDashboardView: View {
    @Query(sort: \Host.label) private var hosts: [Host]
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var historyStore = SessionHistoryStore.shared
    @State private var selectedHost: Host?

    var body: some View {
        NavigationStack {
            if hosts.isEmpty {
                ContentUnavailableView(
                    "No Hosts",
                    systemImage: "network",
                    description: Text("Add hosts to see connection status")
                )
                .navigationTitle("Connection Status")
            } else {
                List(hosts) { host in
                    let activeSession = sessionStore.terminalSessions.first { $0.host.id == host.id }
                    let lastSession = historyStore.records.first { $0.hostID == host.id }

                    NavigationLink(destination: EmptyView()) {
                        HStack(spacing: 12) {
                            VStack(alignment: .center, spacing: 4) {
                                Circle()
                                    .fill(statusColor(for: activeSession))
                                    .frame(width: 12, height: 12)
                                    .shadow(color: statusColor(for: activeSession).opacity(0.6), radius: 3)

                                Text(activeSession != nil ? "Live" : "Idle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(host.label)
                                    .fontWeight(.semibold)

                                HStack(spacing: 8) {
                                    Text(host.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let session = activeSession {
                                        Label(
                                            String(format: "%.0fms", session.responseLatencyMilliseconds.map(Double.init) ?? 0),
                                            systemImage: "network"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    }
                                }

                                if let lastSession = lastSession {
                                    Text("Last: \(lastSession.endedAt, style: .relative)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                if let session = activeSession {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.gray)
                                }

                                Text(activeSession == nil ? "Offline" : "Online")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                .navigationTitle("Connection Status")
            }
        }
    }

    private func statusColor(for session: TerminalViewModel?) -> Color {
        guard let session = session else { return .gray }
        switch session.status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        }
    }
}

#Preview {
    HostStatusDashboardView()
}
