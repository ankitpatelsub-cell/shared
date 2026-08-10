package dev.termvault.app.ui.browser

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.InsertDriveFile
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.IdentityEntity

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowserScreen(
    viewModel: SftpBrowserViewModel,
    hosts: List<HostEntity>,
    identities: List<IdentityEntity>,
) {
    var selectedHost by remember { mutableStateOf<HostEntity?>(null) }
    var expanded by remember { mutableStateOf(false) }
    val state by viewModel.state.collectAsState()

    Scaffold { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(12.dp)) {
            ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                OutlinedTextField(
                    value = selectedHost?.label ?: "Choose a host",
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Host") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    hosts.forEach { host ->
                        DropdownMenuItem(
                            text = { Text(host.label) },
                            onClick = {
                                selectedHost = host
                                expanded = false
                                viewModel.open(host, identities.firstOrNull { it.id == host.identityId })
                            },
                        )
                    }
                }
            }

            when (val current = state) {
                is BrowserState.Idle -> Text(
                    "Pick a host above to browse its files over SFTP.",
                    modifier = Modifier.padding(top = 24.dp),
                    style = MaterialTheme.typography.bodyLarge,
                )

                is BrowserState.Connecting, is BrowserState.Loading -> Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                    horizontalArrangement = Arrangement.Center,
                ) { CircularProgressIndicator() }

                is BrowserState.Failed -> Text(
                    current.message,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 24.dp),
                )

                is BrowserState.Loaded -> Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = viewModel::navigateUp) {
                            Icon(Icons.Filled.ArrowUpward, contentDescription = "Up")
                        }
                        Text(current.path, style = MaterialTheme.typography.bodyMedium)
                    }
                    LazyColumn {
                        items(current.entries, key = { it.path }) { entry ->
                            ListItem(
                                headlineContent = { Text(entry.name) },
                                leadingContent = {
                                    Icon(
                                        if (entry.isDirectory) Icons.Filled.Folder else Icons.Filled.InsertDriveFile,
                                        contentDescription = null,
                                    )
                                },
                                supportingContent = { Text(entry.permissions) },
                                modifier = if (entry.isDirectory) {
                                    Modifier.clickable { viewModel.listDirectory(entry.path) }
                                } else {
                                    Modifier
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}
