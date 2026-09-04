package dev.termvault.app.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/** Mirrors iOS `CommandHistoryRecord` (`CommandHistoryStore.swift`). */
@Entity(tableName = "command_history")
data class CommandHistoryEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val hostId: UUID,
    val command: String,
    val timestamp: Long = System.currentTimeMillis(),
    val status: String? = null,
    val isFavorite: Boolean = false,
) {
    val displayCommand: String
        get() {
            val trimmed = command.trim()
            return if (trimmed.length > 80) trimmed.take(77) + "…" else trimmed
        }
}

@Dao
interface CommandHistoryDao {
    @Query("SELECT * FROM command_history ORDER BY timestamp DESC")
    fun observeAll(): Flow<List<CommandHistoryEntity>>

    @Query("SELECT * FROM command_history WHERE hostId = :hostId ORDER BY timestamp DESC")
    fun observeForHost(hostId: UUID): Flow<List<CommandHistoryEntity>>

    @Insert
    suspend fun insert(record: CommandHistoryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: CommandHistoryEntity)

    @Delete
    suspend fun delete(record: CommandHistoryEntity)

    @Query("SELECT COUNT(*) FROM command_history")
    suspend fun count(): Int

    @Query(
        "DELETE FROM command_history WHERE id NOT IN (" +
            "SELECT id FROM command_history ORDER BY timestamp DESC LIMIT :keep" +
            ")"
    )
    suspend fun trimTo(keep: Int)
}

/** Mirrors iOS `CommandMacro`. `delay` stays fixed at 0.5s, matching the iOS quirk where every macro shares one delay. */
@Entity(tableName = "command_macros")
data class CommandMacroEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val name: String,
    val commands: List<String>,
    val icon: String,
    val description: String? = null,
    val delaySeconds: Double = 0.5,
) {
    val displayCommands: String get() = commands.joinToString(" → ")
}

@Dao
interface CommandMacroDao {
    @Query("SELECT * FROM command_macros ORDER BY name ASC")
    fun observeAll(): Flow<List<CommandMacroEntity>>

    @Query("SELECT COUNT(*) FROM command_macros")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(macro: CommandMacroEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(macros: List<CommandMacroEntity>)

    @Delete
    suspend fun delete(macro: CommandMacroEntity)
}

/** Mirrors iOS `SessionHistoryRecord`. */
@Entity(tableName = "session_history")
data class SessionHistoryEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val hostId: UUID,
    val hostLabel: String,
    val workspaceName: String? = null,
    val startedAt: Long,
    val endedAt: Long,
    val transcript: String,
    val isBookmarked: Boolean = false,
    val tags: List<String> = emptyList(),
    val averageLatencyMs: Int = 0,
    val dataTransferredBytes: Long = 0,
    val commandCount: Int = 0,
) {
    val displayDataTransferred: String
        get() {
            val units = listOf("B", "KB", "MB", "GB")
            var value = dataTransferredBytes.toDouble()
            var unitIndex = 0
            while (value >= 1024 && unitIndex < units.lastIndex) {
                value /= 1024
                unitIndex++
            }
            return "%.1f %s".format(value, units[unitIndex])
        }
}

@Dao
interface SessionHistoryDao {
    @Query("SELECT * FROM session_history ORDER BY startedAt DESC")
    fun observeAll(): Flow<List<SessionHistoryEntity>>

    @Insert
    suspend fun insert(record: SessionHistoryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: SessionHistoryEntity)

    @Delete
    suspend fun delete(record: SessionHistoryEntity)

    @Query("SELECT COUNT(*) FROM session_history")
    suspend fun count(): Int

    @Query(
        "DELETE FROM session_history WHERE id NOT IN (" +
            "SELECT id FROM session_history ORDER BY startedAt DESC LIMIT :keep" +
            ")"
    )
    suspend fun trimTo(keep: Int)
}
