package dev.termvault.app.notifications

import android.content.Context
import dev.termvault.app.data.db.WorkspaceSessionEntity

/** Adapts the static [NotificationService] helpers to [WorkspaceNotifier], for injection into [dev.termvault.app.workspace.WorkspaceStore]. */
class NotificationWorkspaceNotifier(private val context: Context) : WorkspaceNotifier {
    override suspend fun agentFinished(session: WorkspaceSessionEntity) {
        NotificationService.agentFinished(context, session)
    }

    override suspend fun agentWaiting(session: WorkspaceSessionEntity) {
        NotificationService.agentWaiting(context, session)
    }
}
