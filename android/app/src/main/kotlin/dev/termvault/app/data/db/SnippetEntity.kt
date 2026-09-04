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

/** Mirrors iOS `Snippet.swift`. */
@Entity(tableName = "snippets")
data class SnippetEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val name: String,
    val command: String,
    val runOnConnect: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
)

@Dao
interface SnippetDao {
    @Query("SELECT * FROM snippets ORDER BY name ASC")
    fun observeAll(): Flow<List<SnippetEntity>>

    @Query("SELECT * FROM snippets ORDER BY name ASC")
    suspend fun getAll(): List<SnippetEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(snippet: SnippetEntity)

    @Delete
    suspend fun delete(snippet: SnippetEntity)
}
