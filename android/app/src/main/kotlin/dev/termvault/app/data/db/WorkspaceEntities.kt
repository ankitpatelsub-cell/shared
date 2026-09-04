package dev.termvault.app.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import dev.termvault.app.data.model.AgentTool
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Mirrors iOS `WorkspaceSession` — a durable bookmark (host + remote path +
 * tool + deterministic tmux name) to a persistent, agent-hosting tmux
 * session that lives on the remote host, not a local UI/session snapshot.
 * See [dev.termvault.app.workspace.WorkspaceStore.tmuxName] for the hash
 * that must match the iOS client's exactly, since it's what lets both
 * clients reattach to the same remote tmux session.
 */
@Entity(tableName = "workspace_sessions")
data class WorkspaceSessionEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val hostId: UUID,
    val hostLabel: String,
    val path: String,
    val toolRaw: String,
    val tmuxName: String,
    val lastOpenedAt: Long,
    val customName: String? = null,
    val pinnedAt: Long? = null,
    val arguments: List<String>? = null,
    val environment: Map<String, String>? = null,
    val startupPrompt: String? = null,
) {
    val tool: AgentTool get() = AgentTool.from(toolRaw)
    val displayName: String
        get() = customName?.takeIf { it.isNotBlank() }
            ?: path.trimEnd('/').substringAfterLast('/').takeIf { it.isNotBlank() }
            ?: path
}

@Dao
interface WorkspaceSessionDao {
    @Query("SELECT * FROM workspace_sessions ORDER BY (pinnedAt IS NOT NULL) DESC, pinnedAt DESC, lastOpenedAt DESC")
    fun observeAll(): Flow<List<WorkspaceSessionEntity>>

    @Query("SELECT * FROM workspace_sessions ORDER BY (pinnedAt IS NOT NULL) DESC, pinnedAt DESC, lastOpenedAt DESC")
    suspend fun getAll(): List<WorkspaceSessionEntity>

    @Query("SELECT * FROM workspace_sessions WHERE hostId = :hostId AND tmuxName = :tmuxName LIMIT 1")
    suspend fun findByHostAndTmuxName(hostId: UUID, tmuxName: String): WorkspaceSessionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(session: WorkspaceSessionEntity)

    @Delete
    suspend fun delete(session: WorkspaceSessionEntity)

    @Query("SELECT COUNT(*) FROM workspace_sessions")
    suspend fun count(): Int

    @Query(
        "DELETE FROM workspace_sessions WHERE id NOT IN (" +
            "SELECT id FROM workspace_sessions ORDER BY (pinnedAt IS NOT NULL) DESC, pinnedAt DESC, lastOpenedAt DESC LIMIT :keep" +
            ")"
    )
    suspend fun trimTo(keep: Int)
}

/** Mirrors iOS `WorkspaceProject` — a user-organized folder/tag of workspace bookmarks. */
@Entity(tableName = "workspace_projects")
data class WorkspaceProjectEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val name: String,
    val details: String? = null,
    val icon: String = "folder",
    val color: String = "blue",
    val createdAt: Long = System.currentTimeMillis(),
    val workspaceIds: List<UUID> = emptyList(),
) {
    companion object {
        val colors = listOf("red", "orange", "yellow", "green", "blue", "purple", "pink", "gray")
        val icons = listOf("folder", "star", "bolt", "gear", "database", "cube", "hammer", "wrench")
    }
}

@Dao
interface WorkspaceProjectDao {
    @Query("SELECT * FROM workspace_projects ORDER BY name ASC")
    fun observeAll(): Flow<List<WorkspaceProjectEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(project: WorkspaceProjectEntity)

    @Delete
    suspend fun delete(project: WorkspaceProjectEntity)
}

/** Mirrors iOS `AgentPreset` — a reusable named tool configuration. */
@Entity(tableName = "agent_presets")
data class AgentPresetEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val name: String,
    val toolRaw: String,
    val arguments: List<String> = emptyList(),
    val environment: Map<String, String> = emptyMap(),
    val startupPrompt: String = "",
) {
    val tool: AgentTool get() = AgentTool.from(toolRaw)
}

@Dao
interface AgentPresetDao {
    @Query("SELECT * FROM agent_presets ORDER BY name ASC")
    fun observeAll(): Flow<List<AgentPresetEntity>>

    @Query("SELECT * FROM agent_presets ORDER BY name ASC")
    suspend fun getAll(): List<AgentPresetEntity>

    @Query("SELECT COUNT(*) FROM agent_presets")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(preset: AgentPresetEntity)

    @Delete
    suspend fun delete(preset: AgentPresetEntity)
}

/** Mirrors iOS `WorkspaceFavorite`. */
@Entity(tableName = "workspace_favorites")
data class WorkspaceFavoriteEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val workspaceId: UUID,
    val hostId: UUID,
    val workspaceName: String,
    val hostLabel: String,
    val toolType: String,
    val addedAt: Long = System.currentTimeMillis(),
    val order: Int = 0,
) {
    val displayName: String get() = "$workspaceName on $hostLabel"
}

@Dao
interface WorkspaceFavoriteDao {
    @Query("SELECT * FROM workspace_favorites ORDER BY `order` ASC")
    fun observeAll(): Flow<List<WorkspaceFavoriteEntity>>

    @Query("SELECT * FROM workspace_favorites ORDER BY `order` ASC")
    suspend fun getAll(): List<WorkspaceFavoriteEntity>

    @Query("SELECT * FROM workspace_favorites WHERE workspaceId = :workspaceId AND hostId = :hostId LIMIT 1")
    suspend fun find(workspaceId: UUID, hostId: UUID): WorkspaceFavoriteEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(favorite: WorkspaceFavoriteEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(favorites: List<WorkspaceFavoriteEntity>)

    @Delete
    suspend fun delete(favorite: WorkspaceFavoriteEntity)
}
