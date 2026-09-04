package dev.termvault.app.ui.keys

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.termvault.app.data.model.IdentityKeyType

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdentityManagerScreen(viewModel: IdentityManagerViewModel) {
    val identities by viewModel.identities.collectAsState()
    var showGenerate by remember { mutableStateOf(false) }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(onClick = { showGenerate = true }) {
                Icon(Icons.Filled.Add, contentDescription = "Generate key")
            }
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding).fillMaxWidth()) {
            items(identities, key = { it.id }) { identity ->
                ListItem(
                    headlineContent = { Text(identity.label) },
                    supportingContent = { Text("${identity.keyType.displayName} · ${identity.fingerprint}") },
                    trailingContent = {
                        TextButton(onClick = { viewModel.delete(identity) }) { Text("Delete") }
                    },
                )
            }
        }
    }

    if (showGenerate) {
        var label by remember { mutableStateOf("") }
        var comment by remember { mutableStateOf("termvault") }
        var keyType by remember { mutableStateOf(IdentityKeyType.ED25519) }
        var expanded by remember { mutableStateOf(false) }

        AlertDialog(
            onDismissRequest = { showGenerate = false },
            title = { Text("Generate SSH Key") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(label, { label = it }, label = { Text("Label") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(comment, { comment = it }, label = { Text("Comment") }, modifier = Modifier.fillMaxWidth())
                    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                        OutlinedTextField(
                            value = keyType.displayName,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Key Type") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                            modifier = Modifier.fillMaxWidth().menuAnchor(),
                        )
                        androidx.compose.material3.DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                            IdentityKeyType.entries.forEach { type ->
                                DropdownMenuItem(text = { Text(type.displayName) }, onClick = { keyType = type; expanded = false })
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.generate(label.ifBlank { keyType.displayName }, keyType, comment)
                        showGenerate = false
                    },
                    enabled = label.isNotBlank(),
                ) { Text("Generate") }
            },
            dismissButton = { TextButton(onClick = { showGenerate = false }) { Text("Cancel") } },
        )
    }
}
