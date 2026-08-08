import SwiftUI
import SwiftData

/// A live, cross-host view of every open session — previously this view
/// existed but was wired to nothing (no tab, no menu item routed to it) and
/// its row tap went to `NavigationLink(destination: EmptyView())`, so it was
/// dead code. Now reachable from the Hosts tab toolbar, it shows every open
/// terminal/SFTP session per host (not just one), and tapping a session
/// switches straight to it.
struct HostStatusDashboardView: View {
    @Query(sort: \Host.label) private var hosts: [Host]
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @ObservedObject private var historyStore = SessionHistoryStore.shared
    @Environment(\.dismiss) private var dismiss

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
                    Section {
                        let openSessions = sessionStore.sessions.filter { $0.host.id == host.id }
                        if openSessions.isEmpty {
                            idleRow(for: host)
                        } else {
                            ForEach(openSessions) { session in
                                Button { open(session) } label: {
                                    sessionRow(session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text(host.label)
                    } footer: {
                        if let lastSession = historyStore.records.first(where: { $0.hostID == host.id }) {
                            Text("Last closed: \(lastSession.endedAt, format: .relative(presentation: .named))")
                        }
                    }
                }
                .navigationTitle("Connection Status")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private func idleRow(for host: Host) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color.gray).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("No open sessions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: OpenSession) -> some View {
        HStack(spacing: 12) {
            statusDot(for: session)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let terminal = session.terminal {
                        Text(statusLabel(terminal.status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let tool = terminal.activeWorkspace?.tool {
                            Text("· \(tool.title)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("SFTP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func statusDot(for session: OpenSession) -> some View {
        Circle()
            .fill(session.terminal.map { Theme.Status.color(for: $0.status) } ?? .blue)
            .frame(width: 8, height: 8)
    }

    private func statusLabel(_ status: ConnectionStatus) -> String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }

    private func open(_ session: OpenSession) {
        sessionStore.activeSessionID = session.id
        navigationStore.navigate(to: .sessions)
        dismiss()
    }
}

#Preview {
    HostStatusDashboardView()
}
