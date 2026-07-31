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
        HStack(spacing: 12) {
            HostAvatarView(label: viewModel.host.label, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.host.label)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                statusBadge
            }

            Spacer(minLength: 8)

            topBarButton("folder") { showingSFTP = true }
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
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .failed(let message): return message
        }
    }
}
