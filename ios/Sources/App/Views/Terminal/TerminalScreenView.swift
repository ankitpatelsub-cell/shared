import SwiftUI

struct TerminalScreenView: View {
    @ObservedObject var viewModel: TerminalViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingSFTP = false
    @State private var showingTranscript = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TerminalRepresentable(terminalView: viewModel.terminalView)
                // Keep edge glyphs clear of the display boundary. Without a
                // gutter, SwiftTerm's first column can be visibly clipped.
                .padding(.horizontal, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExtraKeysAccessoryView(viewModel: viewModel)
        }
        .background(Color.black)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if viewModel.status == .disconnected {
                await viewModel.connect()
            }
        }
        .sheet(isPresented: $showingSFTP) {
            NavigationStack {
                SFTPGateView(host: viewModel.host, connectionID: viewModel.id)
            }
        }
        .sheet(isPresented: $showingTranscript) {
            TerminalTranscriptView(viewModel: viewModel)
        }
        .alert("Paste Multiple Lines?", isPresented: Binding(
            get: { viewModel.pendingMultilinePaste != nil },
            set: { if !$0 { viewModel.pendingMultilinePaste = nil } }
        )) {
            Button("Cancel", role: .cancel) { viewModel.pendingMultilinePaste = nil }
            Button("Paste", role: .destructive) { viewModel.confirmMultilinePaste() }
        } message: {
            Text("Pasting multiple lines can execute commands immediately on the remote host.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HostAvatarView(label: viewModel.host.label, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                statusBadge
            }

            Spacer(minLength: 8)

            if canReconnect {
                topBarButton("arrow.clockwise") {
                    Task { await viewModel.connect() }
                }
                .accessibilityLabel("Reconnect")
            }
            topBarButton("folder") { showingSFTP = true }
            topBarButton("doc.text.magnifyingglass") { showingTranscript = true }
            topBarButton("xmark") { sessionStore.close(viewModel) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
        }
    }

    private var statusBadge: some View {
        let color = Theme.Status.color(for: viewModel.status)
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: viewModel.status == .connecting ? 4 : 0)
            Text(statusLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private func topBarButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.12)))
        }
    }

    private var statusLabel: String {
        switch viewModel.status {
        case .connected:
            if let latency = viewModel.responseLatencyMilliseconds {
                return "Connected · \(latency) ms"
            }
            return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .failed(let message): return message
        }
    }

    private var sessionTitle: String {
        guard let workspace = viewModel.activeWorkspace else { return viewModel.host.label }
        return "\(workspace.displayName) · \(workspace.tool.title)"
    }

    private var canReconnect: Bool {
        switch viewModel.status {
        case .disconnected, .failed: return true
        case .connecting, .connected: return false
        }
    }
}

private struct TerminalTranscriptView: View {
    @ObservedObject var viewModel: TerminalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(filteredTranscript)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .searchable(text: $searchText, prompt: "Find output")
            .navigationTitle("Terminal Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    ShareLink(item: viewModel.plainTextTranscript) { Image(systemName: "square.and.arrow.up") }
                    Button("Clear", role: .destructive) { viewModel.clearTranscript() }
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filteredTranscript: String {
        let transcript = viewModel.plainTextTranscript
        guard !searchText.isEmpty else { return transcript }
        return transcript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .joined(separator: "\n")
    }
}
