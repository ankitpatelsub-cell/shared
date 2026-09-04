package dev.termvault.app.workspace

import dev.termvault.app.data.db.WorkspaceFavoriteDao
import dev.termvault.app.data.db.WorkspaceFavoriteEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import java.util.UUID

/** Mirrors iOS `WorkspaceFavoritesStore`, backed by Room. */
class WorkspaceFavoritesStore(private val dao: WorkspaceFavoriteDao, scope: CoroutineScope) {
    val favorites: StateFlow<List<WorkspaceFavoriteEntity>> =
        dao.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())

    fun isFavorite(workspaceId: UUID, hostId: UUID): Boolean =
        favorites.value.any { it.workspaceId == workspaceId && it.hostId == hostId }

    suspend fun toggleFavorite(workspaceId: UUID, hostId: UUID, workspaceName: String, hostLabel: String, toolType: String) {
        val existing = dao.find(workspaceId, hostId)
        if (existing != null) {
            dao.delete(existing)
            reorder()
        } else {
            dao.upsert(
                WorkspaceFavoriteEntity(
                    workspaceId = workspaceId,
                    hostId = hostId,
                    workspaceName = workspaceName,
                    hostLabel = hostLabel,
                    toolType = toolType,
                    order = favorites.value.size,
                )
            )
        }
    }

    suspend fun reorder(newOrder: List<WorkspaceFavoriteEntity>) {
        dao.upsertAll(newOrder.mapIndexed { index, favorite -> favorite.copy(order = index) })
    }

    private suspend fun reorder() {
        dao.upsertAll(dao.getAll().mapIndexed { index, favorite -> favorite.copy(order = index) })
    }
}
