package dev.termvault.app.ui.sessions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.termvault.app.workspace.WorkspaceStore
import kotlinx.coroutines.launch

@Composable
fun SessionsScreen(workspaceStore: WorkspaceStore) {
    val sessions by workspaceStore.recentSessions.collectAsState()
    val scope = rememberCoroutineScope()

    Scaffold { padding ->
        if (sessions.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    "No workspace sessions yet. Open a project shell or agent session from a host to see it here.",
                    modifier = Modifier.padding(24.dp),
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        } else {
            LazyColumn(modifier = Modifier.padding(padding).fillMaxWidth()) {
                items(sessions, key = { it.id }) { session ->
                    ListItem(
                        headlineContent = { Text(session.displayName) },
                        supportingContent = { Text("${session.tool.title} on ${session.hostLabel}") },
                        trailingContent = {
                            Row {
                                IconButton(onClick = { scope.launch { workspaceStore.togglePin(session) } }) {
                                    Icon(
                                        Icons.Filled.PushPin,
                                        contentDescription = "Pin",
                                        tint = if (session.pinnedAt != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                IconButton(onClick = { scope.launch { workspaceStore.delete(session) } }) {
                                    Icon(Icons.Filled.Delete, contentDescription = "Remove")
                                }
                            }
                        },
                    )
                }
            }
        }
    }
}
