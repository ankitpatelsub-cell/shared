package dev.termvault.app.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Update
import dev.termvault.app.data.model.HostAuthMethod
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/** Mirrors iOS `Host.swift` (`@Model final class Host`). */
@Entity(tableName = "hosts")
data class HostEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val label: String,
    val address: String,
    val port: Int = 22,
    val username: String,
    val authMethodRaw: String = HostAuthMethod.PASSWORD.rawValue,
    val identityId: UUID? = null,
    val jumpHostId: UUID? = null,
    val startupSnippet: String? = null,
    val groupName: String? = null,
    val tags: List<String> = emptyList(),
    val themeName: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val authMethod: HostAuthMethod get() = HostAuthMethod.from(authMethodRaw)
    val connectionSubtitle: String get() = "$username@$address:$port"
}

@Dao
interface HostDao {
    @Query("SELECT * FROM hosts ORDER BY label ASC")
    fun observeAll(): Flow<List<HostEntity>>

    @Query("SELECT * FROM hosts ORDER BY label ASC")
    suspend fun getAll(): List<HostEntity>

    @Query("SELECT * FROM hosts WHERE id = :id")
    suspend fun getById(id: UUID): HostEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(host: HostEntity)

    @Update
    suspend fun update(host: HostEntity)

    @Delete
    suspend fun delete(host: HostEntity)
}
