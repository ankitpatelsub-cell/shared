package dev.termvault.app.ui.hosts

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Card
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.termvault.app.data.db.HostEntity

@Composable
fun HostListScreen(
    viewModel: HostListViewModel,
    onOpenTerminal: (HostEntity) -> Unit,
) {
    val hosts by viewModel.hosts.collectAsState()
    var editingHost by remember { mutableStateOf<HostEntity?>(null) }
    var showEditor by remember { mutableStateOf(false) }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(onClick = {
                editingHost = null
                showEditor = true
            }) {
                Icon(Icons.Filled.Add, contentDescription = "Add host")
            }
        }
    ) { padding ->
        if (hosts.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    "No hosts yet — tap + to add one.",
                    modifier = Modifier.padding(24.dp),
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.padding(padding),
                contentPadding = PaddingValues(vertical = 8.dp, horizontal = 8.dp),
            ) {
                items(hosts, key = { it.id }) { host ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                            .clickable {
                                editingHost = host
                                showEditor = true
                            },
                    ) {
                        ListItem(
                            headlineContent = { Text(host.label) },
                            supportingContent = { Text(host.connectionSubtitle) },
                            trailingContent = {
                                IconButton(onClick = { onOpenTerminal(host) }) {
                                    Icon(Icons.Filled.PlayArrow, contentDescription = "Connect")
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    if (showEditor) {
        HostEditorDialog(
            viewModel = viewModel,
            existing = editingHost,
            onDismiss = { showEditor = false },
            onDelete = editingHost?.let { host ->
                {
                    viewModel.delete(host)
                    showEditor = false
                }
            },
        )
    }
}
