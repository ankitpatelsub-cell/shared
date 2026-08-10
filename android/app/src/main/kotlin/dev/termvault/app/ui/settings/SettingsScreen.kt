package dev.termvault.app.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import dev.termvault.app.security.BiometricLockService

@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel,
    lockService: BiometricLockService,
) {
    val status by viewModel.status.collectAsState()
    val isBusy by viewModel.isBusy.collectAsState()

    var githubToken by remember { mutableStateOf(viewModel.currentGitHubToken().orEmpty()) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var biometricEnabled by remember { mutableStateOf(lockService.isBiometricLockEnabled) }

    Scaffold { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState())
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Security", style = MaterialTheme.typography.titleMedium)
            androidx.compose.foundation.layout.Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Require biometric unlock")
                Switch(
                    checked = biometricEnabled,
                    onCheckedChange = {
                        biometricEnabled = it
                        lockService.isBiometricLockEnabled = it
                    },
                )
            }

            Divider()

            Text("GitHub", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = githubToken,
                onValueChange = { githubToken = it },
                label = { Text("Personal access token") },
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(onClick = { viewModel.saveGitHubToken(githubToken) }, enabled = !isBusy && githubToken.isNotBlank()) {
                Text("Save & Validate")
            }

            Divider()

            Text("Cloud Vault", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(email, { email = it }, label = { Text("Email") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(
                password, { password = it },
                label = { Text("Password") },
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { viewModel.cloudSignIn(email, password, register = false) }, enabled = !isBusy) { Text("Sign In") }
                Button(onClick = { viewModel.cloudSignIn(email, password, register = true) }, enabled = !isBusy) { Text("Register") }
            }
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { viewModel.cloudUpload(password) }, enabled = !isBusy && password.isNotBlank()) { Text("Upload Vault") }
                Button(onClick = { viewModel.cloudRestore(password) }, enabled = !isBusy && password.isNotBlank()) { Text("Restore Vault") }
            }

            status?.let {
                Divider()
                Text(it, style = MaterialTheme.typography.bodyMedium)
            }

            Divider()
            Text("TermVault for Android — an unofficial Termius-style SSH client.", style = MaterialTheme.typography.bodySmall)
        }
    }
}
