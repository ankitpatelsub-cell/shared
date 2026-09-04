package dev.termvault.app.workspace

import android.content.SharedPreferences
import dev.termvault.app.data.db.AgentPresetEntity
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.WorkspaceSessionDao
import dev.termvault.app.data.db.WorkspaceSessionEntity
import dev.termvault.app.data.model.AgentTool
import dev.termvault.app.notifications.WorkspaceNotifier
import dev.termvault.app.ssh.RemoteCommandService
import dev.termvault.app.util.ShellQuote
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import java.util.UUID

private const val MAX_RECENT_SESSIONS = 30
private const val AGENT_NOTIFICATIONS_KEY = "dev.termvault.settings.agentNotifications"

/**
 * Owns the "recent workspace sessions" list (host + remote path + agent
 * tool, bookmarking a persistent remote tmux session) and the background
 * poll that detects when a running agent finishes or goes idle waiting on
 * input. Mirrors iOS `WorkspaceStore`, but backed by Room instead of a
 * UserDefaults-encoded JSON blob.
 */
class WorkspaceStore(
    private val dao: WorkspaceSessionDao,
    private val remoteCommandService: RemoteCommandService,
    private val notifier: WorkspaceNotifier,
    private val prefs: SharedPreferences,
    scope: CoroutineScope,
) {
    val recentSessions: StateFlow<List<WorkspaceSessionEntity>> =
        dao.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())

    private val notifiedFinishedSessions = mutableSetOf<UUID>()
    private val observedRunningSessions = mutableSetOf<UUID>()
    private val lastPaneSnapshot = mutableMapOf<UUID, String>()

    private val _waitingWorkspaceIds = MutableStateFlow<Set<UUID>>(emptySet())
    val waitingWorkspaceIds: StateFlow<Set<UUID>> = _waitingWorkspaceIds

    suspend fun session(host: HostEntity, path: String, tool: AgentTool): WorkspaceSessionEntity {
        val key = tmuxName(host.id, path, tool)
        val existing = dao.findByHostAndTmuxName(host.id, key)
        if (existing != null) {
            val updated = existing.copy(lastOpenedAt = System.currentTimeMillis())
            dao.upsert(updated)
            return updated
        }
        val created = WorkspaceSessionEntity(
            hostId = host.id,
            hostLabel = host.label,
            path = path,
            toolRaw = tool.rawValue,
            tmuxName = key,
            lastOpenedAt = System.currentTimeMillis(),
        )
        dao.upsert(created)
        dao.trimTo(MAX_RECENT_SESSIONS)
        return created
    }

    suspend fun session(host: HostEntity, path: String, preset: AgentPresetEntity): WorkspaceSessionEntity {
        val base = session(host, path, preset.tool)
        val updated = base.copy(
            customName = preset.name,
            arguments = preset.arguments,
            environment = preset.environment,
            startupPrompt = preset.startupPrompt,
        )
        dao.upsert(updated)
        return updated
    }

    suspend fun duplicate(session: WorkspaceSessionEntity): WorkspaceSessionEntity {
        val copy = session.copy(
            id = UUID.randomUUID(),
            tmuxName = "${session.tmuxName}-${UUID.randomUUID().toString().take(6).lowercase()}",
            lastOpenedAt = System.currentTimeMillis(),
            customName = "${session.displayName} Copy",
            pinnedAt = null,
        )
        dao.upsert(copy)
        return copy
    }

    suspend fun terminate(session: WorkspaceSessionEntity) {
        remoteCommandService.run(session.hostId, "tmux kill-session -t ${ShellQuote.quote(session.tmuxName)}")
        dao.delete(session)
    }

    suspend fun togglePin(session: WorkspaceSessionEntity) {
        dao.upsert(session.copy(pinnedAt = if (session.pinnedAt == null) System.currentTimeMillis() else null))
    }

    suspend fun rename(session: WorkspaceSessionEntity, name: String) {
        dao.upsert(session.copy(customName = name))
    }

    suspend fun delete(session: WorkspaceSessionEntity) {
        dao.delete(session)
    }

    /** Polls every recent agent-tool workspace's tmux pane; call periodically (e.g. every 30s) from a foreground scope. */
    suspend fun checkForCompletions() {
        if (!prefs.getBoolean(AGENT_NOTIFICATIONS_KEY, false)) return
        for (workspace in dao.getAll()) {
            val executable = workspace.tool.executable ?: continue
            if (notifiedFinishedSessions.contains(workspace.id)) continue

            val name = ShellQuote.quote(workspace.tmuxName)
            val output = runCatching {
                remoteCommandService.run(
                    workspace.hostId,
                    "tmux display-message -p -t $name '#{pane_current_command}' 2>/dev/null || true",
                )
            }.getOrNull()?.takeIf { it.isNotEmpty() } ?: continue

            if (output == executable) {
                observedRunningSessions.add(workspace.id)
                checkForIdleInput(workspace)
            } else if (observedRunningSessions.contains(workspace.id)) {
                notifiedFinishedSessions.add(workspace.id)
                lastPaneSnapshot.remove(workspace.id)
                _waitingWorkspaceIds.value = _waitingWorkspaceIds.value - workspace.id
                notifier.agentFinished(workspace)
            }
        }
    }

    /**
     * A running agent whose tmux pane content hasn't changed between two
     * consecutive polls has gone quiet — almost always sitting at a
     * prompt/confirmation, not still churning. Fires once per idle period;
     * resets as soon as new output appears so it can fire again next time.
     */
    private suspend fun checkForIdleInput(workspace: WorkspaceSessionEntity) {
        val name = ShellQuote.quote(workspace.tmuxName)
        val pane = runCatching {
            remoteCommandService.run(
                workspace.hostId,
                "tmux capture-pane -p -t $name 2>/dev/null | tail -c 2000 || true",
            )
        }.getOrNull() ?: return

        if (lastPaneSnapshot[workspace.id] == pane) {
            if (_waitingWorkspaceIds.value.contains(workspace.id)) return
            _waitingWorkspaceIds.value = _waitingWorkspaceIds.value + workspace.id
            notifier.agentWaiting(workspace)
        } else {
            lastPaneSnapshot[workspace.id] = pane
            _waitingWorkspaceIds.value = _waitingWorkspaceIds.value - workspace.id
        }
    }

    companion object {
        /**
         * Exact port of iOS `WorkspaceStore.tmuxName(hostID:path:tool:)`: a
         * djb2-style hash (seed 5381, `hash = ((hash << 5) + hash) + byte`,
         * wrapping 64-bit arithmetic) over the UTF-8 bytes of
         * "<hostID>|<path>|<tool.rawValue>". Must stay byte-for-byte
         * identical to the iOS version — it's the primary key that lets
         * both clients reattach to the same remote tmux session. Critically,
         * `hostId` is formatted UPPERCASE (matching Swift's `UUID.uuidString`),
         * not Kotlin/Java's default lowercase `UUID.toString()`.
         */
        fun tmuxName(hostId: UUID, path: String, tool: AgentTool): String {
            var hash = 5381uL
            val input = "${hostId.toString().uppercase()}|$path|${tool.rawValue}"
            for (byte in input.toByteArray(Charsets.UTF_8)) {
                hash = (hash shl 5) + hash + byte.toUByte().toULong()
            }
            return "termvault-${tool.rawValue}-${hash.toString(16)}"
        }
    }
}
