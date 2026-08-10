package dev.termvault.app

import android.app.Application
import android.content.Context
import dev.termvault.app.cloud.CloudVaultService
import dev.termvault.app.data.db.AppDatabase
import dev.termvault.app.diagnostics.ErrorLogger
import dev.termvault.app.github.GitHubService
import dev.termvault.app.history.CommandHistoryStore
import dev.termvault.app.history.CommandMacroStore
import dev.termvault.app.history.SessionHistoryStore
import dev.termvault.app.notifications.NotificationService
import dev.termvault.app.notifications.NotificationWorkspaceNotifier
import dev.termvault.app.security.BiometricLockService
import dev.termvault.app.security.SecretStore
import dev.termvault.app.ssh.HostKeyStore
import dev.termvault.app.ssh.PortForwardingService
import dev.termvault.app.ssh.RemoteCommandService
import dev.termvault.app.ssh.SftpService
import dev.termvault.app.ssh.SshSessionManager
import dev.termvault.app.workspace.AgentPresetStore
import dev.termvault.app.workspace.WorkspaceFavoritesStore
import dev.termvault.app.workspace.WorkspaceStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Small hand-rolled DI container (the app is too small to justify a
 * Hilt/Dagger dependency graph) — every long-lived service is constructed
 * once here and handed out to ViewModels and [dev.termvault.app.notifications.NotificationActionReceiver] alike.
 */
class TermVaultApplication : Application() {

    val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    lateinit var database: AppDatabase
        private set

    lateinit var errorLogger: ErrorLogger
        private set

    lateinit var lockService: BiometricLockService
        private set

    lateinit var secretStore: SecretStore
        private set

    lateinit var hostKeyStore: HostKeyStore
        private set

    lateinit var sshSessionManager: SshSessionManager
        private set

    lateinit var remoteCommandService: RemoteCommandService
        private set

    lateinit var sftpService: SftpService
        private set

    lateinit var portForwardingService: PortForwardingService
        private set

    lateinit var cloudVaultService: CloudVaultService
        private set

    lateinit var gitHubService: GitHubService
        private set

    lateinit var workspaceStore: WorkspaceStore
        private set

    lateinit var commandHistoryStore: CommandHistoryStore
        private set

    lateinit var commandMacroStore: CommandMacroStore
        private set

    lateinit var sessionHistoryStore: SessionHistoryStore
        private set

    lateinit var workspaceFavoritesStore: WorkspaceFavoritesStore
        private set

    lateinit var agentPresetStore: AgentPresetStore
        private set

    override fun onCreate() {
        super.onCreate()
        errorLogger = ErrorLogger(this)
        database = AppDatabase.build(this, errorLogger)
        lockService = BiometricLockService(this)
        secretStore = SecretStore(this)
        hostKeyStore = HostKeyStore(this)
        sshSessionManager = SshSessionManager(secretStore, hostKeyStore)
        remoteCommandService = RemoteCommandService(sshSessionManager)
        sftpService = SftpService()
        portForwardingService = PortForwardingService(sshSessionManager)
        cloudVaultService = CloudVaultService(secretStore, database.hostDao(), database.identityDao(), database.snippetDao())
        gitHubService = GitHubService(secretStore)
        workspaceStore = WorkspaceStore(
            database.workspaceSessionDao(),
            remoteCommandService,
            NotificationWorkspaceNotifier(this),
            getSharedPreferences("dev.termvault.settings", Context.MODE_PRIVATE),
            applicationScope,
        )
        commandHistoryStore = CommandHistoryStore(database.commandHistoryDao(), applicationScope)
        commandMacroStore = CommandMacroStore(database.commandMacroDao(), applicationScope)
        sessionHistoryStore = SessionHistoryStore(database.sessionHistoryDao(), applicationScope)
        workspaceFavoritesStore = WorkspaceFavoritesStore(database.workspaceFavoriteDao(), applicationScope)
        agentPresetStore = AgentPresetStore(database.agentPresetDao(), applicationScope)
        NotificationService.registerChannels(this)
    }

    companion object {
        fun from(context: Context): TermVaultApplication = context.applicationContext as TermVaultApplication
    }
}
