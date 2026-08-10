package dev.termvault.app.notifications

import dev.termvault.app.navigation.RootTab
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/**
 * Bridges a notification tap (handled by [NotificationActionReceiver] /
 * `MainActivity.onNewIntent`, outside Compose) into the navigation layer.
 * Mirrors iOS `NotificationRouter`.
 */
object NotificationRouter {
    private val _pendingWorkspaceId = MutableStateFlow<UUID?>(null)
    val pendingWorkspaceId: StateFlow<UUID?> = _pendingWorkspaceId.asStateFlow()

    // Set alongside pendingWorkspaceId only for a "finished" (not "waiting")
    // notification tap — the natural next action after an agent finishes is
    // almost always "show me what changed".
    private val _pendingDiffWorkspaceId = MutableStateFlow<UUID?>(null)
    val pendingDiffWorkspaceId: StateFlow<UUID?> = _pendingDiffWorkspaceId.asStateFlow()

    private val _pendingTab = MutableStateFlow<RootTab?>(null)
    val pendingTab: StateFlow<RootTab?> = _pendingTab.asStateFlow()

    fun routeToWorkspace(workspaceId: UUID, showDiff: Boolean) {
        _pendingWorkspaceId.value = workspaceId
        _pendingDiffWorkspaceId.value = if (showDiff) workspaceId else null
    }

    fun routeToTab(tab: RootTab) {
        _pendingTab.value = tab
    }

    fun consumeWorkspace() {
        _pendingWorkspaceId.value = null
        _pendingDiffWorkspaceId.value = null
    }

    fun consumeTab() {
        _pendingTab.value = null
    }
}
