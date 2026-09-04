package dev.termvault.app.ssh

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.schmizz.sshj.common.IOUtils
import java.util.UUID

class RemoteCommandNotConnectedException :
    Exception("Connect to the host before running project commands.")

/**
 * Fire-and-forget "run one command over an existing SSH connection and get
 * back the merged stdout+stderr as a trimmed string" — mirrors iOS
 * `RemoteCommandService.swift`, used for one-off/utility commands rather
 * than the interactive terminal pty stream.
 */
class RemoteCommandService(private val sessionManager: SshSessionManager) {
    suspend fun run(connectionId: UUID, command: String, maxResponseSize: Int = 1_048_576): String =
        withContext(Dispatchers.IO) {
            val client = sessionManager.session(connectionId) ?: throw RemoteCommandNotConnectedException()
            val session = client.startSession()
            try {
                val exec = session.exec(command)
                val stdout = IOUtils.readFully(exec.inputStream).toByteArray()
                val stderr = IOUtils.readFully(exec.errorStream).toByteArray()
                exec.close()
                val combined = (stdout + stderr).let {
                    if (it.size > maxResponseSize) it.copyOfRange(0, maxResponseSize) else it
                }
                String(combined, Charsets.UTF_8).trim()
            } finally {
                runCatching { session.close() }
            }
        }
}
