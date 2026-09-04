package dev.termvault.app.ssh

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import net.schmizz.sshj.connection.channel.direct.LocalPortForwarder
import net.schmizz.sshj.connection.channel.direct.Parameters
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

enum class ForwardType { LOCAL, DYNAMIC, REMOTE }

data class PortForward(
    val id: UUID = UUID.randomUUID(),
    val connectionId: UUID,
    val type: ForwardType,
    val localPort: Int,
    val remoteHost: String?,
    val remotePort: Int?,
)

class PortForwardingNotSupportedException(type: ForwardType) :
    Exception(
        when (type) {
            ForwardType.DYNAMIC -> "Dynamic (SOCKS) forwarding isn't implemented yet."
            ForwardType.REMOTE -> "Remote forwarding isn't implemented yet."
            ForwardType.LOCAL -> "Local forwarding failed to start."
        }
    )

/**
 * Local (`-L`) port forwarding, genuinely implemented via sshj's
 * `newLocalPortForwarder` — unlike iOS, where Citadel doesn't expose a
 * forwarding API at all and the feature is a UI-visible "not supported"
 * stub. Dynamic (SOCKS) and remote (`-R`) forwarding are left unimplemented
 * here too for now — real, scoped follow-up work, not faked.
 */
class PortForwardingService(private val sessionManager: SshSessionManager) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val forwards = ConcurrentHashMap<UUID, PortForward>()
    private val sockets = ConcurrentHashMap<UUID, ServerSocket>()
    private val jobs = ConcurrentHashMap<UUID, Job>()

    fun activeForwards(): List<PortForward> = forwards.values.toList()

    suspend fun startLocalForward(connectionId: UUID, localPort: Int, remoteHost: String, remotePort: Int): PortForward {
        val client = sessionManager.session(connectionId) ?: throw SshNotConnectedException()
        val serverSocket = ServerSocket()
        serverSocket.bind(InetSocketAddress("127.0.0.1", localPort))

        val parameters = Parameters("127.0.0.1", localPort, remoteHost, remotePort)
        val forwarder = client.newLocalPortForwarder(parameters, serverSocket)

        val forward = PortForward(
            connectionId = connectionId,
            type = ForwardType.LOCAL,
            localPort = localPort,
            remoteHost = remoteHost,
            remotePort = remotePort,
        )
        forwards[forward.id] = forward
        sockets[forward.id] = serverSocket
        jobs[forward.id] = scope.launch {
            runCatching { forwarder.listen() }
            stopForward(forward.id)
        }
        return forward
    }

    suspend fun startDynamicForward(connectionId: UUID, localPort: Int): PortForward {
        throw PortForwardingNotSupportedException(ForwardType.DYNAMIC)
    }

    suspend fun startRemoteForward(connectionId: UUID, remoteHost: String, remotePort: Int, localPort: Int): PortForward {
        throw PortForwardingNotSupportedException(ForwardType.REMOTE)
    }

    fun stopForward(forwardId: UUID) {
        jobs.remove(forwardId)?.cancel()
        runCatching { sockets.remove(forwardId)?.close() }
        forwards.remove(forwardId)
    }

    fun stopAllForConnection(connectionId: UUID) {
        forwards.values.filter { it.connectionId == connectionId }.forEach { stopForward(it.id) }
    }
}
