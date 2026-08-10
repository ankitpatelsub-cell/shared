package dev.termvault.app.ui.terminal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.terminal.TerminalEmulatorView

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalScreen(
    host: HostEntity,
    viewModel: TerminalViewModel,
    onBack: () -> Unit,
) {
    val connectionState by viewModel.connectionState.collectAsState()
    val lastError by viewModel.lastError.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(host.label) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Box(modifier = Modifier.weight(1f).fillMaxSize()) {
                AndroidView(
                    factory = { context ->
                        TerminalEmulatorView(context).also { viewModel.attach(it) }
                    },
                    modifier = Modifier.fillMaxSize(),
                )

                when (connectionState) {
                    ConnectionState.CONNECTING -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) { CircularProgressIndicator() }

                    ConnectionState.FAILED -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(lastError ?: "Connection failed.", color = MaterialTheme.colorScheme.error)
                            TextButton(onClick = viewModel::retry) { Text("Retry") }
                        }
                    }

                    ConnectionState.DISCONNECTED -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                            Text("Disconnected")
                            TextButton(onClick = viewModel::retry) { Text("Reconnect") }
                        }
                    }

                    ConnectionState.CONNECTED -> Unit
                }
            }

            ExtraKeysBar(viewModel)
        }
    }
}
