import SwiftUI

struct PortForwardingView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var viewModel: TerminalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddForward = false
    @State private var forwardType: PortForwardType = .dynamic
    @State private var localPort = ""
    @State private var remoteHost = ""
    @State private var remotePort = ""
    @State private var errorMessage: String?

    enum PortForwardType: String, CaseIterable, Identifiable {
        case local = "Local"
        case dynamic = "Dynamic (SOCKS)"
        case remote = "Remote"
        var id: String { rawValue }
    }

    private var activeForwards: [PortForwardingService.PortForward] {
        PortForwardingService.shared.getActiveForwards().filter { $0.sshClient === SSHSessionManager.shared.session(for: viewModel.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if activeForwards.isEmpty {
                    ContentUnavailableView {
                        Label("No Port Forwards", systemImage: "network")
                    } description: {
                        Text("Add a port forward to route traffic through this SSH connection.")
                    } actions: {
                        Button("Add Port Forward") { showingAddForward = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(activeForwards) { forward in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: forward.type == .dynamic ? "antenna.radiowaves.left.and.right" :
                                          forward.type == .local ? "arrow.right.circle" : "arrow.left.circle")
                                        .foregroundStyle(.blue)
                                    Text(forward.type.rawValue)
                                        .font(.headline)
                                }
                                if forward.type == .dynamic {
                                    Text("SOCKS proxy on localhost:\(forward.localPort)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if forward.type == .local {
                                    Text("localhost:\(forward.localPort) → \(forward.remoteHost ?? ""):\(forward.remotePort ?? 0)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if forward.type == .remote {
                                    Text("\(forward.remoteHost ?? ""):\(forward.remotePort ?? 0) → localhost:\(forward.localPort)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(forward.isRunning ? "Running" : "Stopped")
                                    .font(.caption2)
                                    .foregroundStyle(forward.isRunning ? .green : .red)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await PortForwardingService.shared.stopForward(forwardID: forward.id) }
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let forward = activeForwards[index]
                            Task { await PortForwardingService.shared.stopForward(forwardID: forward.id) }
                        }
                    }
                }
            }
            .navigationTitle("Port Forwarding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddForward = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAddForward) {
                AddPortForwardView(viewModel: viewModel)
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private struct AddPortForwardView: View {
    @ObservedObject var viewModel: TerminalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var forwardType: PortForwardingView.PortForwardType = .dynamic
    @State private var localPort = ""
    @State private var remoteHost = ""
    @State private var remotePort = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Forward Type", selection: $forwardType) {
                        ForEach(PortForwardingView.PortForwardType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Local Port") {
                    TextField("Local Port (e.g., 1080)", text: $localPort)
                        .keyboardType(.numberPad)
                }

                if forwardType != .dynamic {
                    Section("Remote Host") {
                        TextField("Remote Host", text: $remoteHost)
                    }

                    Section("Remote Port") {
                        TextField("Remote Port", text: $remotePort)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Text(forwardType == .dynamic
                        ? "Creates a SOCKS5 proxy on localhost:port. Use in browser/proxy settings."
                        : forwardType == .local
                        ? "Forwards localhost:localPort to remoteHost:remotePort through SSH."
                        : "Forwards remoteHost:remotePort to localhost:localPort through SSH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Port Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addForward() }
                    }
                    .disabled(localPort.isEmpty || (forwardType != .dynamic && (remoteHost.isEmpty || remotePort.isEmpty)))
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func addForward() async {
        guard let port = Int(localPort) else {
            errorMessage = "Invalid local port"
            return
        }

        guard let sshClient = await SSHSessionManager.shared.session(for: viewModel.id) else {
            errorMessage = "Not connected"
            return
        }

        do {
            switch forwardType {
            case .dynamic:
                try await PortForwardingService.shared.startDynamicForward(
                    connectionID: viewModel.id,
                    localPort: port,
                    sshClient: sshClient
                )
            case .local:
                guard let rPort = Int(remotePort), !remoteHost.isEmpty else {
                    errorMessage = "Invalid remote host/port"
                    return
                }
                try await PortForwardingService.shared.startLocalForward(
                    connectionID: viewModel.id,
                    localPort: port,
                    remoteHost: remoteHost,
                    remotePort: rPort,
                    sshClient: sshClient
                )
            case .remote:
                guard let rPort = Int(remotePort), !remoteHost.isEmpty else {
                    errorMessage = "Invalid remote host/port"
                    return
                }
                try await PortForwardingService.shared.startRemoteForward(
                    connectionID: viewModel.id,
                    remoteHost: remoteHost,
                    remotePort: rPort,
                    localHost: "127.0.0.1",
                    localPort: port,
                    sshClient: sshClient
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}