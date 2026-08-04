import SwiftUI
import SwiftData

struct WorkspaceFavoritesView: View {
    @ObservedObject private var store = WorkspaceFavoritesStore.shared
    @EnvironmentObject private var sessionStore: SessionStore
    @Query(sort: \Host.label) private var hosts: [Host]
    @Environment(\.dismiss) private var dismiss
    @State private var isEditMode = false

    var body: some View {
        NavigationStack {
            if store.favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star",
                    description: Text("Pin workspace sessions for quick access")
                )
                .navigationTitle("Workspace Favorites")
            } else {
                List {
                    if isEditMode {
                        ForEach(store.favorites, id: \.id) { favorite in
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(favorite.workspaceName)
                                        .fontWeight(.semibold)

                                    HStack(spacing: 8) {
                                        Text(favorite.hostLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text("•")
                                            .foregroundStyle(.secondary)

                                        Text(favorite.toolType)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .onMove { indices, newOffset in
                            var favorites = store.favorites
                            favorites.move(fromOffsets: indices, toOffset: newOffset)
                            store.reorder(favorites)
                        }
                    } else {
                        ForEach(store.favorites) { favorite in
                            Button {
                                // Connect to workspace
                                if let host = hosts.first(where: { $0.id == favorite.hostID }) {
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "star.fill")
                                                .foregroundStyle(.yellow)
                                                .font(.caption)

                                            Text(favorite.workspaceName)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.primary)
                                        }

                                        HStack(spacing: 8) {
                                            Text(favorite.hostLabel)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Text("•")
                                                .foregroundStyle(.secondary)

                                            Text(favorite.toolType)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }

                                        Text(favorite.addedAt, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.removeFavorite(favorite)
                                } label: {
                                    Label("Remove", systemImage: "star.slash")
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Workspace Favorites")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(isEditMode ? "Done" : "Edit") {
                            isEditMode.toggle()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    WorkspaceFavoritesView()
}
