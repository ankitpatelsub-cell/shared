package dev.termvault.app.history

import dev.termvault.app.data.db.CommandHistoryDao
import dev.termvault.app.data.db.CommandHistoryEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import java.util.UUID

private const val MAX_RECORDS = 1000

/** Mirrors iOS `CommandHistoryStore`, backed by Room instead of a JSON file. */
class CommandHistoryStore(private val dao: CommandHistoryDao, scope: CoroutineScope) {
    val records: StateFlow<List<CommandHistoryEntity>> =
        dao.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())

    suspend fun record(command: String, hostId: UUID, status: String? = null) {
        if (command.isBlank()) return
        dao.insert(CommandHistoryEntity(hostId = hostId, command = command, status = status))
        dao.trimTo(MAX_RECORDS)
    }

    suspend fun toggleFavorite(record: CommandHistoryEntity) {
        dao.upsert(record.copy(isFavorite = !record.isFavorite))
    }

    suspend fun delete(record: CommandHistoryEntity) {
        dao.delete(record)
    }

    fun search(query: String, hostId: UUID? = null): List<CommandHistoryEntity> =
        records.value.filter { it.command.contains(query, ignoreCase = true) && (hostId == null || it.hostId == hostId) }

    fun favorites(hostId: UUID? = null): List<CommandHistoryEntity> =
        records.value.filter { it.isFavorite && (hostId == null || it.hostId == hostId) }
}
