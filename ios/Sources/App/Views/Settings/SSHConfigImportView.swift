import SwiftUI
import UniformTypeIdentifiers

struct SSHConfigImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingFileImporter = false
    @State private var parsedHosts: [SSHConfigParser.ParsedHost] = []
    @State private var parsedIdentities: [SSHConfigParser.ParsedIdentity] = []
    @State private var importError: String?
    @State private var showingPreview = false
    @State private var selectedHosts: Set<UUID> = []
    @State private var selectAll = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if parsedHosts.isEmpty {
                    // Empty state - show import button
                    ContentUnavailableView(
                        "Import SSH Config",
                        systemImage: "square.and.arrow.down.on.square",
                        description: Text("Select a ~/.ssh/config file to import hosts and identities")
                    )
                    .overlay(alignment: .bottom) {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Choose Config File", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                    }
                } else {
                    // Preview imported hosts
                    List {
                        Section {
                            Toggle("Select All", isOn: $selectAll)
                                .onChange(of: selectAll) { _, newValue in
                                    if newValue {
                                        selectedHosts = Set(parsedHosts.map(\.id))
                                    } else {
                                        selectedHosts.removeAll()
                                    }
                                }
                        }
                        
                        Section("Imported Hosts (\(selectedHosts.count)/\(parsedHosts.count) selected)") {
                            ForEach(parsedHosts) { host in
                                HostImportRow(
                                    host: host,
                                    isSelected: selectedHosts.contains(host.id),
                                    onToggle: { selected in
                                        if selected {
                                            selectedHosts.insert(host.id)
                                        } else {
                                            selectedHosts.remove(host.id)
                                        }
                                        selectAll = selectedHosts.count == parsedHosts.count
                                    }
                                )
                            }
                        }
                        
                        if !parsedIdentities.isEmpty {
                            Section("Identities (\(parsedIdentities.count))") {
                                ForEach(parsedIdentities) { identity in
                                    HStack {
                                        Image(systemName: identity.keyType == .ed25519 ? "key.fill" : "key.horizontal.fill")
                                            .foregroundStyle(.blue)
                                        VStack(alignment: .leading) {
                                            Text(identity.label)
                                            Text(identity.privateKeyPath)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    
                    // Import button
                    VStack(spacing: 12) {
                        if let error = importError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        
                        Button {
                            importSelected()
                        } label: {
                            Label("Import \(selectedHosts.count) Host(s)", systemImage: "arrow.down.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedHosts.isEmpty)
                        
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                    }
                    .padding()
                    .background(.bar)
                }
            }
            .navigationTitle("Import SSH Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !parsedHosts.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Re-import") {
                            showingFileImporter = true
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.data, .text, .item],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    importError = "Cannot access selected file"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let (hosts, identities) = try SSHConfigParser.parseFile(at: url)
                parsedHosts = hosts
                parsedIdentities = identities
                selectedHosts = Set(hosts.map(\.id))
                selectAll = true
                importError = nil
            } catch {
                importError = "Failed to parse config: \(error.localizedDescription)"
                parsedHosts = []
                parsedIdentities = []
            }
        case .failure(let error):
            importError = "File selection failed: \(error.localizedDescription)"
        }
    }
    
    private func importSelected() {
        _ = parsedHosts.filter { selectedHosts.contains($0.id) }
        // TODO: Convert to actual Host/Identity models and save
        // This would integrate with CloudVaultService or local SwiftData context
        dismiss()
    }
}

private struct HostImportRow: View {
    let host: SSHConfigParser.ParsedHost
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            Button {
                onToggle(!isSelected)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(host.label)
                        .font(.headline)
                    if host.authMethod == .privateKey {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                    if host.jumpHostLabel != nil {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 12) {
                    Label("\(host.address):\(host.port)", systemImage: "server.rack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(host.username, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let jumpHost = host.jumpHostLabel {
                    Label("Jump: \(jumpHost)", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
    }
}