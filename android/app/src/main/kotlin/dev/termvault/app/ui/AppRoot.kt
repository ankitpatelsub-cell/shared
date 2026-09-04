package dev.termvault.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import dev.termvault.app.TermVaultApplication
import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.navigation.AppNavigationStore
import dev.termvault.app.navigation.RootTab
import dev.termvault.app.ssh.JumpHop
import dev.termvault.app.ui.browser.BrowserScreen
import dev.termvault.app.ui.browser.SftpBrowserViewModel
import dev.termvault.app.ui.hosts.HostListScreen
import dev.termvault.app.ui.hosts.HostListViewModel
import dev.termvault.app.ui.keys.IdentityManagerScreen
import dev.termvault.app.ui.keys.IdentityManagerViewModel
import dev.termvault.app.ui.lock.LockScreen
import dev.termvault.app.ui.sessions.SessionsScreen
import dev.termvault.app.ui.settings.SettingsScreen
import dev.termvault.app.ui.settings.SettingsViewModel
import dev.termvault.app.ui.terminal.TerminalScreen
import dev.termvault.app.ui.terminal.TerminalViewModel

@Composable
fun AppRoot(app: TermVaultApplication, activity: FragmentActivity) {
    val isUnlocked by app.lockService.isUnlocked.collectAsState()

    LaunchedEffect(Unit) {
        app.lockService.authenticateIfNeeded(activity)
    }

    if (!isUnlocked) {
        LockScreen(app.lockService, activity)
        return
    }

    val navStore = remember { AppNavigationStore() }
    val selectedTab by navStore.selectedTab.collectAsState()

    val hostListViewModel: HostListViewModel = viewModel(factory = viewModelFactory {
        initializer { HostListViewModel(app.database.hostDao(), app.database.identityDao(), app.secretStore) }
    })
    val identityViewModel: IdentityManagerViewModel = viewModel(factory = viewModelFactory {
        initializer { IdentityManagerViewModel(app.database.identityDao(), app.secretStore) }
    })
    val settingsViewModel: SettingsViewModel = viewModel(factory = viewModelFactory {
        initializer { SettingsViewModel(app.secretStore, app.cloudVaultService, app.gitHubService) }
    })
    val sftpBrowserViewModel: SftpBrowserViewModel = viewModel(factory = viewModelFactory {
        initializer { SftpBrowserViewModel(app.sshSessionManager, app.sftpService, app.applicationScope) }
    })

    val hosts by hostListViewModel.hosts.collectAsState()
    val identities by hostListViewModel.identities.collectAsState()

    var activeTerminalHost by remember { mutableStateOf<HostEntity?>(null) }
    val terminalHost = activeTerminalHost

    if (terminalHost != null) {
        val identity = identities.firstOrNull { it.id == terminalHost.identityId }
        val jumpHost = hosts.firstOrNull { it.id == terminalHost.jumpHostId }
        val jumpHops = if (jumpHost != null) {
            listOf(JumpHop(jumpHost, identities.firstOrNull { it.id == jumpHost.identityId }))
        } else {
            emptyList()
        }
        val terminalViewModel = remember(terminalHost.id) {
            TerminalViewModel(
                terminalHost, identity, jumpHops, app.sshSessionManager,
                app.commandHistoryStore, app.sessionHistoryStore, app.applicationScope,
            )
        }
        DisposableEffect(terminalHost.id) {
            onDispose { terminalViewModel.dispose() }
        }
        TerminalScreen(terminalHost, terminalViewModel, onBack = { activeTerminalHost = null })
        return
    }

    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == RootTab.HOSTS,
                    onClick = { navStore.navigate(RootTab.HOSTS) },
                    icon = { Icon(Icons.Filled.List, contentDescription = null) },
                    label = { Text("Hosts") },
                )
                NavigationBarItem(
                    selected = selectedTab == RootTab.BROWSER,
                    onClick = { navStore.navigate(RootTab.BROWSER) },
                    icon = { Icon(Icons.Filled.Folder, contentDescription = null) },
                    label = { Text("Browser") },
                )
                NavigationBarItem(
                    selected = selectedTab == RootTab.SESSIONS,
                    onClick = { navStore.navigate(RootTab.SESSIONS) },
                    icon = { Icon(Icons.Filled.Storage, contentDescription = null) },
                    label = { Text("Sessions") },
                )
                NavigationBarItem(
                    selected = selectedTab == RootTab.KEYS,
                    onClick = { navStore.navigate(RootTab.KEYS) },
                    icon = { Icon(Icons.Filled.Key, contentDescription = null) },
                    label = { Text("Keys") },
                )
                NavigationBarItem(
                    selected = selectedTab == RootTab.SETTINGS,
                    onClick = { navStore.navigate(RootTab.SETTINGS) },
                    icon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                    label = { Text("Settings") },
                )
            }
        },
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when (selectedTab) {
                RootTab.HOSTS -> HostListScreen(hostListViewModel, onOpenTerminal = { activeTerminalHost = it })
                RootTab.BROWSER -> BrowserScreen(sftpBrowserViewModel, hosts, identities)
                RootTab.SESSIONS -> SessionsScreen(app.workspaceStore)
                RootTab.KEYS -> IdentityManagerScreen(identityViewModel)
                RootTab.SETTINGS -> SettingsScreen(settingsViewModel, app.lockService)
            }
        }
    }
}
