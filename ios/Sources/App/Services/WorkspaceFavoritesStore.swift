import Foundation

struct WorkspaceFavorite: Codable, Identifiable, Equatable {
    let id: UUID
    let workspaceID: UUID
    let hostID: UUID
    let workspaceName: String
    let hostLabel: String
    let toolType: String
    let addedAt: Date
    var order: Int = 0

    var displayName: String {
        "\(workspaceName) on \(hostLabel)"
    }
}

@MainActor
final class WorkspaceFavoritesStore: ObservableObject {
    static let shared = WorkspaceFavoritesStore()
    @Published private(set) var favorites: [WorkspaceFavorite] = []

    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("workspace-favorites.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([WorkspaceFavorite].self, from: data) {
            favorites = decoded.sorted { $0.order < $1.order }
        }
    }

    func addFavorite(_ favorite: WorkspaceFavorite) {
        guard !favorites.contains(where: { $0.workspaceID == favorite.workspaceID && $0.hostID == favorite.hostID }) else { return }
        var newFavorite = favorite
        newFavorite.order = favorites.count
        favorites.append(newFavorite)
        save()
    }

    func removeFavorite(_ favorite: WorkspaceFavorite) {
        favorites.removeAll { $0.id == favorite.id }
        reorderFavorites()
        save()
    }

    func isFavorite(workspaceID: UUID, hostID: UUID) -> Bool {
        favorites.contains { $0.workspaceID == workspaceID && $0.hostID == hostID }
    }

    func toggleFavorite(workspaceID: UUID, hostID: UUID, workspaceName: String, hostLabel: String, toolType: String) {
        if let index = favorites.firstIndex(where: { $0.workspaceID == workspaceID && $0.hostID == hostID }) {
            favorites.remove(at: index)
            reorderFavorites()
        } else {
            let favorite = WorkspaceFavorite(
                id: UUID(),
                workspaceID: workspaceID,
                hostID: hostID,
                workspaceName: workspaceName,
                hostLabel: hostLabel,
                toolType: toolType,
                addedAt: Date(),
                order: favorites.count
            )
            favorites.append(favorite)
        }
        save()
    }

    func reorder(_ favorites: [WorkspaceFavorite]) {
        self.favorites = favorites
        reorderFavorites()
        save()
    }

    private func reorderFavorites() {
        for (index, _) in favorites.enumerated() {
            favorites[index].order = index
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
