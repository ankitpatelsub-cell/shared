package dev.termvault.app.history

import dev.termvault.app.data.db.SessionHistoryDao
import dev.termvault.app.data.db.SessionHistoryEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import java.util.UUID

private const val MAX_RECORDS = 500

/**
 * Mirrors iOS `SessionHistoryStore`, backed by Room. [record] takes the
 * finished session's fields directly rather than a `TerminalViewModel`
 * reference, since the Android terminal ViewModel calls this at teardown
 * with its own already-computed values.
 */
class SessionHistoryStore(private val dao: SessionHistoryDao, scope: CoroutineScope) {
    val records: StateFlow<List<SessionHistoryEntity>> =
        dao.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())

    suspend fun record(
        hostId: UUID,
        hostLabel: String,
        workspaceName: String?,
        startedAt: Long,
        transcript: String,
        averageLatencyMs: Int,
        dataTransferredBytes: Long,
        commandCount: Int,
    ) {
        val truncated = transcript.takeLast(1_000_000)
        if (truncated.isBlank()) return
        dao.insert(
            SessionHistoryEntity(
                hostId = hostId,
                hostLabel = hostLabel,
                workspaceName = workspaceName,
                startedAt = startedAt,
                endedAt = System.currentTimeMillis(),
                transcript = truncated,
                averageLatencyMs = averageLatencyMs,
                dataTransferredBytes = dataTransferredBytes,
                commandCount = commandCount,
            )
        )
        dao.trimTo(MAX_RECORDS)
    }

    suspend fun toggleBookmark(record: SessionHistoryEntity) {
        dao.upsert(record.copy(isBookmarked = !record.isBookmarked))
    }

    suspend fun addTag(tag: String, record: SessionHistoryEntity) {
        val trimmed = tag.trim().lowercase()
        if (trimmed.isEmpty() || record.tags.contains(trimmed)) return
        dao.upsert(record.copy(tags = record.tags + trimmed))
    }

    suspend fun removeTag(tag: String, record: SessionHistoryEntity) {
        dao.upsert(record.copy(tags = record.tags - tag.lowercase()))
    }

    fun filterByTag(tag: String): List<SessionHistoryEntity> =
        records.value.filter { it.tags.contains(tag.lowercase()) }

    fun allTags(): List<String> =
        records.value.flatMap { it.tags }.toSortedSet().toList()

    suspend fun delete(record: SessionHistoryEntity) {
        dao.delete(record)
    }
}
