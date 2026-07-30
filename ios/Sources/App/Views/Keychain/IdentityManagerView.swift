import SwiftUI
import SwiftData

struct IdentityManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Identity.label) private var identities: [Identity]
    @StateObject private var viewModel = IdentityManagerViewModel()

    @State private var showingGenerate = false
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(identities) { identity in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(identity.label).font(.body)
                        Text(identity.keyType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(identity.fingerprint)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.delete(identity, context: modelContext)
                        } label: { Label("Delete", systemImage: "trash") }

                        ShareLink(item: identity.publicKey) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                }
            }
            .overlay {
                if identities.isEmpty {
                    ContentUnavailableView(
                        "No Keys",
                        systemImage: "key",
                        description: Text("Generate or import an SSH key to use with your hosts.")
                    )
                }
            }
            .navigationTitle("Keys")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Generate New Key") { showingGenerate = true }
                        Button("Import Key") { showingImport = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingGenerate) {
                GenerateKeyView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingImport) {
                ImportKeyView(viewModel: viewModel)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
