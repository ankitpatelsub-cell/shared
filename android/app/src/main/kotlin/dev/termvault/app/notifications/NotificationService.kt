package dev.termvault.app.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import dev.termvault.app.MainActivity
import dev.termvault.app.data.db.WorkspaceSessionEntity

/** Mirrors iOS `NotificationService` (a stateless namespace of static helpers there too). */
object NotificationService {
    const val WAITING_CHANNEL_ID = "agent_waiting"
    const val FINISHED_CHANNEL_ID = "agent_finished"

    const val CONTINUE_ACTION = "dev.termvault.app.action.AGENT_CONTINUE"
    const val CANCEL_ACTION = "dev.termvault.app.action.AGENT_CANCEL"

    const val EXTRA_WORKSPACE_ID = "workspaceId"
    const val EXTRA_HOST_ID = "hostId"
    const val EXTRA_TMUX_NAME = "tmuxName"

    fun registerChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(WAITING_CHANNEL_ID, "Agent waiting for input", NotificationManager.IMPORTANCE_HIGH)
        )
        manager.createNotificationChannel(
            NotificationChannel(FINISHED_CHANNEL_ID, "Agent finished", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    fun agentFinished(context: Context, workspace: WorkspaceSessionEntity) {
        val notification = NotificationCompat.Builder(context, FINISHED_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("${workspace.tool.title} finished")
            .setContentText("${workspace.displayName} on ${workspace.hostLabel} is ready to review.")
            .setAutoCancel(true)
            .setContentIntent(openWorkspacePendingIntent(context, workspace, showDiff = true))
            .build()
        post(context, "workspace-finished-${workspace.id}".hashCode(), notification)
    }

    fun agentWaiting(context: Context, workspace: WorkspaceSessionEntity) {
        val notification = NotificationCompat.Builder(context, WAITING_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("${workspace.tool.title} is waiting for you")
            .setContentText("${workspace.displayName} on ${workspace.hostLabel} has gone idle — it may need your input.")
            .setAutoCancel(true)
            .setContentIntent(openWorkspacePendingIntent(context, workspace, showDiff = false))
            .addAction(0, "Continue", actionPendingIntent(context, CONTINUE_ACTION, workspace))
            .addAction(0, "Cancel", actionPendingIntent(context, CANCEL_ACTION, workspace))
            .build()
        post(context, "workspace-waiting-${workspace.id}".hashCode(), notification)
    }

    private fun post(context: Context, id: Int, notification: android.app.Notification) {
        // POST_NOTIFICATIONS is a runtime-requested permission on API 33+
        // (the manifest <uses-permission> alone doesn't grant it) — skip
        // posting rather than crash if the user hasn't granted it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        runCatching { NotificationManagerCompat.from(context).notify(id, notification) }
    }

    private fun openWorkspacePendingIntent(context: Context, workspace: WorkspaceSessionEntity, showDiff: Boolean): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_WORKSPACE_ID, workspace.id.toString())
            putExtra("showDiff", showDiff)
        }
        return PendingIntent.getActivity(
            context, workspace.id.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionPendingIntent(context: Context, action: String, workspace: WorkspaceSessionEntity): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_HOST_ID, workspace.hostId.toString())
            putExtra(EXTRA_TMUX_NAME, workspace.tmuxName)
        }
        return PendingIntent.getBroadcast(
            context, (action + workspace.id).hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
