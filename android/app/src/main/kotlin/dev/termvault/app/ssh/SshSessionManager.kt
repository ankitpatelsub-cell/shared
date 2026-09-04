package dev.termvault.app.ssh

import dev.termvault.app.data.db.HostEntity
import dev.termvault.app.data.db.IdentityEntity
import dev.termvault.app.data.model.HostAuthMethod
import dev.termvault.app.security.SecretStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.schmizz.sshj.AndroidConfig
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.connection.channel.direct.Session
import net.schmizz.sshj.userauth.password.PasswordUtils
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** One hop in a jump/bastion chain — mirrors iOS `SSHJumpHop`. */
data class JumpHop(val host: HostEntity, val identity: IdentityEntity?)

class NoAuthenticationConfiguredException :
    Exception("This host has no password or SSH key configured.")

class SshNotConnectedException : Exception("Not connected.")

/**
 * Owns every live SSH connection, keyed by a caller-chosen connection ID
 * (usually the target host's UUID, but a distinct ID per tab/session is
 * also valid — mirrors iOS `SSHSessionManager`). Built on sshj's real,
 * blocking API (verified against the actual hierynomus/sshj 0.40.0
 * source): `SSHClient.connect`/`authPassword`/`authPublickey`,
 * `startSession().allocatePTY(...).startShell()` for the interactive
 * shell, and `newDirectConnection`/`connectVia` for jump-host chaining —
 * sshj's own doc comment on `newDirectConnection` literally calls this out
 * as "opening an SSH connection via a 'jump' server."
 */
class SshSessionManager(private val secretStore: SecretStore, private val hostKeyStore: HostKeyStore) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val targetClients = ConcurrentHashMap<UUID, SSHClient>()
    private val jumpChains = ConcurrentHashMap<UUID, List<SSHClient>>()
    private val shells = ConcurrentHashMap<UUID, Session.Shell>()
    private val readerJobs = ConcurrentHashMap<UUID, Job>()

    fun isConnected(connectionId: UUID): Boolean = targetClients[connectionId]?.isConnected == true

    fun session(connectionId: UUID): SSHClient? = targetClients[connectionId]

    suspend fun connect(
        connectionId: UUID,
        host: HostEntity,
        identity: IdentityEntity?,
        jumpHosts: List<JumpHop> = emptyList(),
        onOutput: (ByteArray) -> Unit,
        onClose: () -> Unit,
    ) = withContext(Dispatchers.IO) {
        if (targetClients.containsKey(connectionId)) return@withContext

        // Hop order matches iOS `SessionStore.buildJumpHosts`: hops[0] is
        // the host nearest the target, hops.last is the one dialed first
        // (directly reachable). Walk it in reverse to actually connect.
        val chain = jumpHosts.asReversed()
        val chainClients = mutableListOf<SSHClient>()
        var tunnelSource: SSHClient? = null

        for (hop in chain) {
            val client = SSHClient(AndroidConfig())
            client.addHostKeyVerifier(TofuHostKeyVerifier(hop.host.address, hop.host.port, hostKeyStore))
            val source = tunnelSource
            if (source == null) {
                client.connect(hop.host.address, hop.host.port)
            } else {
                client.connectVia(source.newDirectConnection(hop.host.address, hop.host.port))
            }
            authenticate(client, hop.host, hop.identity)
            chainClients.add(client)
            tunnelSource = client
        }
        if (chainClients.isNotEmpty()) {
            jumpChains[connectionId] = chainClients
        }

        val targetClient = SSHClient(AndroidConfig())
        targetClient.addHostKeyVerifier(TofuHostKeyVerifier(host.address, host.port, hostKeyStore))
        val source = tunnelSource
        if (source == null) {
            targetClient.connect(host.address, host.port)
        } else {
            targetClient.connectVia(source.newDirectConnection(host.address, host.port))
        }
        authenticate(targetClient, host, identity)
        targetClients[connectionId] = targetClient

        val session = targetClient.startSession()
        session.allocatePTY(
            "xterm-256color",
            80,
            24,
            0,
            0,
            emptyMap(),
        )
        val shell = session.startShell()
        shells[connectionId] = shell

        readerJobs[connectionId] = scope.launch {
            try {
                val buffer = ByteArray(8192)
                val input = shell.inputStream
                while (true) {
                    val read = input.read(buffer)
                    if (read == -1) break
                    onOutput(buffer.copyOf(read))
                }
            } catch (_: IOException) {
                // Channel closed — fall through to teardown below.
            } finally {
                disconnect(connectionId)
                onClose()
            }
        }
    }

    suspend fun send(connectionId: UUID, text: String) = withContext(Dispatchers.IO) {
        val shell = shells[connectionId] ?: throw SshNotConnectedException()
        shell.outputStream.write(text.toByteArray(Charsets.UTF_8))
        shell.outputStream.flush()
    }

    suspend fun resize(connectionId: UUID, cols: Int, rows: Int) = withContext(Dispatchers.IO) {
        val shell = shells[connectionId] ?: throw SshNotConnectedException()
        shell.changeWindowDimensions(cols, rows, 0, 0)
    }

    suspend fun disconnect(connectionId: UUID) = withContext(Dispatchers.IO) {
        readerJobs.remove(connectionId)?.cancel()
        shells.remove(connectionId)
        runCatching { targetClients.remove(connectionId)?.disconnect() }
        jumpChains.remove(connectionId)?.asReversed()?.forEach { client ->
            runCatching { client.disconnect() }
        }
    }

    suspend fun disconnectAll() {
        for (id in targetClients.keys.toList()) {
            disconnect(id)
        }
    }

    private fun authenticate(client: SSHClient, host: HostEntity, identity: IdentityEntity?) {
        when (host.authMethod) {
            HostAuthMethod.PASSWORD -> {
                val password = secretStore.password(host) ?: throw NoAuthenticationConfiguredException()
                client.authPassword(host.username, PasswordUtils.createOneOff(password.toCharArray()))
            }
            HostAuthMethod.PRIVATE_KEY -> {
                // sshj's PKCS8KeyFile (despite the name) auto-detects and
                // parses both legacy PKCS#1 RSA PEMs and openssh-key-v1
                // Ed25519 PEMs via KeyProviderUtil.detectKeyFileFormat, so
                // both key types share this one code path — unlike Citadel
                // on iOS, RSA private-key auth is genuinely supported here.
                if (identity == null) throw NoAuthenticationConfiguredException()
                val pem = secretStore.privateKeyPem(identity) ?: throw NoAuthenticationConfiguredException()
                val passphrase = secretStore.passphrase(identity)
                val keyProvider = if (passphrase != null) {
                    client.loadKeys(pem, null, PasswordUtils.createOneOff(passphrase.toCharArray()))
                } else {
                    client.loadKeys(pem, null, null)
                }
                client.authPublickey(host.username, keyProvider)
            }
            HostAuthMethod.NONE -> throw NoAuthenticationConfiguredException()
        }
    }
}
