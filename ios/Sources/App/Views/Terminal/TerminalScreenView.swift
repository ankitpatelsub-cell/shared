import SwiftUI

struct TerminalScreenView: View {
    @ObservedObject var viewModel: TerminalViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingSFTP = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TerminalRepresentable(terminalView: viewModel.terminalView)
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
                SFTPGateView(host: viewModel.host)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(viewModel.host.label)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Button {
                showingSFTP = true
            } label: {
                Image(systemName: "folder")
                    .foregroundStyle(.white)
            }
            Button {
                sessionStore.close(viewModel)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.9))
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected, .failed: return .red
        }
    }

    private var statusLabel: String {
        switch viewModel.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .failed(let message): return message
        }
    }
}
