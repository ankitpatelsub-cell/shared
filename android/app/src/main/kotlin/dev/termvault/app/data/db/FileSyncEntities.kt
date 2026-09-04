package dev.termvault.app.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import dev.termvault.app.data.model.SyncDirection
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Mirrors iOS `FileSyncRecord`. `localTreeUri` holds a persisted
 * Storage-Access-Framework tree URI string — the Android analog of iOS's
 * security-scoped bookmark data for a user-picked local folder.
 */
@Entity(tableName = "file_sync_records")
data class FileSyncRecordEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val hostId: UUID,
    val localPath: String,
    val localTreeUri: String? = null,
    val remotePath: String,
    val directionRaw: String,
    val lastSyncedAt: Long? = null,
    val autoSync: Boolean = false,
    val ignorePatterns: List<String> = emptyList(),
) {
    val direction: SyncDirection get() = SyncDirection.from(directionRaw)
}

@Dao
interface FileSyncRecordDao {
    @Query("SELECT * FROM file_sync_records ORDER BY lastSyncedAt DESC")
    fun observeAll(): Flow<List<FileSyncRecordEntity>>

    @Query("SELECT * FROM file_sync_records WHERE autoSync = 1")
    suspend fun getAutoSyncRecords(): List<FileSyncRecordEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: FileSyncRecordEntity)

    @Delete
    suspend fun delete(record: FileSyncRecordEntity)
}
