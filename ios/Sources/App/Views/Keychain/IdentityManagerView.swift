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
                    IdentityRow(identity: identity)
                        .cardBackground()
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.delete(identity, context: modelContext)
                            } label: { Label("Delete", systemImage: "trash") }

                            ShareLink(item: identity.publicKey) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
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
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
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

private struct IdentityRow: View {
    let identity: Identity

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(identity.label)
                    .font(.system(.body, weight: .semibold))
                HStack(spacing: 6) {
                    Text(identity.keyType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(identity.fingerprint)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)
        }
    }
}
