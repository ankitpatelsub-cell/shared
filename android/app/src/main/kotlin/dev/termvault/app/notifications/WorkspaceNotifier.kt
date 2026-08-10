package dev.termvault.app.notifications

import dev.termvault.app.data.db.WorkspaceSessionEntity

/** Decouples [dev.termvault.app.workspace.WorkspaceStore]'s polling loop from the concrete notification transport. */
interface WorkspaceNotifier {
    suspend fun agentFinished(session: WorkspaceSessionEntity)
    suspend fun agentWaiting(session: WorkspaceSessionEntity)
}
