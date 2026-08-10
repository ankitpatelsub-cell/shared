package dev.termvault.app.ui.hosts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.model.HostAuthMethod

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun HostEditorDialog(
    viewModel: HostListViewModel,
    existing: HostEntity?,
    onDismiss: () -> Unit,
    onDelete: (() -> Unit)?,
) {
    val identities by viewModel.identities.collectAsState()

    var label by remember { mutableStateOf(existing?.label.orEmpty()) }
    var address by remember { mutableStateOf(existing?.address.orEmpty()) }
    var port by remember { mutableStateOf((existing?.port ?: 22).toString()) }
    var username by remember { mutableStateOf(existing?.username.orEmpty()) }
    var authMethod by remember { mutableStateOf(existing?.authMethod ?: HostAuthMethod.PASSWORD) }
    var password by remember { mutableStateOf("") }
    var identityId by remember { mutableStateOf(existing?.identityId) }
    var groupName by remember { mutableStateOf(existing?.groupName.orEmpty()) }
    var tags by remember { mutableStateOf(existing?.tags?.joinToString(", ").orEmpty()) }
    var identityMenuExpanded by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) "Add Host" else "Edit Host") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(label, { label = it }, label = { Text("Label") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(address, { address = it }, label = { Text("Address") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(port, { port = it.filter(Char::isDigit) }, label = { Text("Port") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(username, { username = it }, label = { Text("Username") }, modifier = Modifier.fillMaxWidth())

                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    HostAuthMethod.entries.forEachIndexed { index, method ->
                        SegmentedButton(
                            selected = authMethod == method,
                            onClick = { authMethod = method },
                            shape = SegmentedButtonDefaultsShape(index, HostAuthMethod.entries.size),
                        ) { Text(method.displayName) }
                    }
                }

                when (authMethod) {
                    HostAuthMethod.PASSWORD -> OutlinedTextField(
                        password, { password = it },
                        label = { Text(if (existing != null) "New Password (leave blank to keep)" else "Password") },
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    HostAuthMethod.PRIVATE_KEY -> ExposedDropdownMenuBox(
                        expanded = identityMenuExpanded,
                        onExpandedChange = { identityMenuExpanded = it },
                    ) {
                        OutlinedTextField(
                            value = identities.firstOrNull { it.id == identityId }?.label ?: "Select a key",
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("SSH Key") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = identityMenuExpanded) },
                            modifier = Modifier.fillMaxWidth().menuAnchor(),
                        )
                        DropdownMenu(expanded = identityMenuExpanded, onDismissRequest = { identityMenuExpanded = false }) {
                            identities.forEach { identity ->
                                DropdownMenuItem(
                                    text = { Text(identity.label) },
                                    onClick = {
                                        identityId = identity.id
                                        identityMenuExpanded = false
                                    },
                                )
                            }
                        }
                    }
                    HostAuthMethod.NONE -> {}
                }

                OutlinedTextField(groupName, { groupName = it }, label = { Text("Group (optional)") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(tags, { tags = it }, label = { Text("Tags, comma separated") }, modifier = Modifier.fillMaxWidth())

                if (onDelete != null) {
                    TextButton(onClick = onDelete) {
                        Text("Delete Host", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    viewModel.save(
                        existing = existing,
                        label = label.ifBlank { address },
                        address = address,
                        port = port.toIntOrNull() ?: 22,
                        username = username,
                        authMethod = authMethod,
                        identityId = identityId,
                        password = password.ifBlank { null },
                        groupName = groupName,
                        tags = tags.split(",").map { it.trim() }.filter { it.isNotEmpty() },
                    )
                    onDismiss()
                },
                enabled = address.isNotBlank() && username.isNotBlank(),
            ) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
private fun SegmentedButtonDefaultsShape(index: Int, count: Int) =
    androidx.compose.material3.SegmentedButtonDefaults.itemShape(index = index, count = count)
