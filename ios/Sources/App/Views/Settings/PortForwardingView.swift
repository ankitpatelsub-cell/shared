import SwiftData
import SwiftUI

struct PortForwardingView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var store = PortForwardingStore.shared
    @Query(sort: \Host.label) private var hosts: [Host]
    @State private var editing: PortForwardRule?
    @State private var adding = false

    var body: some View {
        List {
            if store.rules.isEmpty {
                ContentUnavailableView(
                    "No Port Forwards", systemImage: "arrow.left.arrow.right",
                    description: Text("Expose a remote TCP service securely on this device.")
                )
            }
            ForEach(store.rules) { rule in
                HStack {
                    VStack(alignment: .leading) {
                        Text(rule.name).fontWeight(.semibold)
                        Text("127.0.0.1:\(rule.localPort) → \(rule.targetHost):\(rule.targetPort)")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.activeRuleIDs.contains(rule.id) ? "Stop" : "Start") {
                        Task { await store.toggle(rule, sessionStore: sessionStore) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.activeRuleIDs.contains(rule.id) ? .red : .green)
                }
                .contentShape(Rectangle()).onTapGesture { editing = rule }
                .swipeActions { Button(role: .destructive) { store.delete(rule) } label: { Label("Delete", systemImage: "trash") } }
            }
        }
        .navigationTitle("Port Forwarding")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { PortForwardEditorView(hosts: hosts) }
        .sheet(item: $editing) { PortForwardEditorView(hosts: hosts, rule: $0) }
        .alert("Tunnel Error", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(store.errorMessage ?? "") }
    }
}

private struct PortForwardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let hosts: [Host]
    let existingID: UUID
    @State private var name: String
    @State private var hostID: UUID?
    @State private var localPort: Int
    @State private var targetHost: String
    @State private var targetPort: Int

    init(hosts: [Host], rule: PortForwardRule? = nil) {
        self.hosts = hosts; existingID = rule?.id ?? UUID()
        _name = State(initialValue: rule?.name ?? "")
        _hostID = State(initialValue: rule?.hostID ?? hosts.first?.id)
        _localPort = State(initialValue: rule?.localPort ?? 8080)
        _targetHost = State(initialValue: rule?.targetHost ?? "127.0.0.1")
        _targetPort = State(initialValue: rule?.targetPort ?? 80)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("SSH Host", selection: $hostID) {
                    ForEach(hosts) { Text($0.label).tag(Optional($0.id)) }
                }
                TextField("Local Port", value: $localPort, format: .number).keyboardType(.numberPad)
                TextField("Remote Host", text: $targetHost).textInputAutocapitalization(.never)
                TextField("Remote Port", value: $targetPort, format: .number).keyboardType(.numberPad)
            }
            .navigationTitle("Port Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let hostID else { return }
                        PortForwardingStore.shared.save(PortForwardRule(
                            id: existingID, name: name, hostID: hostID, localPort: localPort,
                            targetHost: targetHost, targetPort: targetPort
                        )); dismiss()
                    }.disabled(name.isEmpty || hostID == nil || !(1...65535).contains(localPort) || !(1...65535).contains(targetPort))
                }
            }
        }
    }
}
