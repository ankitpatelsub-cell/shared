package dev.termvault.app.ssh

import dev.termvault.app.data.model.SftpEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.sftp.OpenMode
import net.schmizz.sshj.sftp.SFTPClient
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * SFTP file browser backend, riding the existing SSH connection
 * [SshSessionManager] already holds open. Verified against sshj 0.40.0's
 * real `SFTPClient`/`RemoteFile` API. Mirrors iOS `SFTPService.swift`.
 */
class SftpService {
    private val clients = ConcurrentHashMap<UUID, SFTPClient>()

    private suspend fun client(connectionId: UUID, sshClient: SSHClient): SFTPClient = withContext(Dispatchers.IO) {
        clients.getOrPut(connectionId) { sshClient.newSFTPClient() }
    }

    suspend fun listDirectory(connectionId: UUID, sshClient: SSHClient, path: String): List<SftpEntry> =
        withContext(Dispatchers.IO) {
            val sftp = client(connectionId, sshClient)
            sftp.ls(path)
                .filter { it.name != "." && it.name != ".." }
                .map { info ->
                    val mode = info.attributes.mode
                    SftpEntry(
                        name = info.name,
                        path = joinPath(path, info.name),
                        isDirectory = info.isDirectory,
                        size = info.attributes.size,
                        permissions = permissionsString(mode.permissionsMask),
                        modifiedAt = info.attributes.mtime.let { if (it > 0) it * 1000L else null },
                    )
                }
                .sortedWith(
                    compareByDescending<SftpEntry> { it.isDirectory }
                        .thenBy { it.name.lowercase() }
                )
        }

    suspend fun download(
        connectionId: UUID,
        sshClient: SSHClient,
        remotePath: String,
        to: File,
        progress: ((Double) -> Unit)? = null,
    ) = withContext(Dispatchers.IO) {
        val sftp = client(connectionId, sshClient)
        sftp.open(remotePath, setOf(OpenMode.READ)).use { remote ->
            val total = remote.length().coerceAtLeast(1)
            to.outputStream().use { out ->
                val buffer = ByteArray(64 * 1024)
                var offset = 0L
                while (true) {
                    val read = remote.read(offset, buffer, 0, buffer.size)
                    if (read == -1) break
                    out.write(buffer, 0, read)
                    offset += read
                    progress?.invoke(offset.toDouble() / total.toDouble())
                }
            }
        }
    }

    suspend fun upload(
        connectionId: UUID,
        sshClient: SSHClient,
        localFile: File,
        remotePath: String,
        progress: ((Double) -> Unit)? = null,
    ) = withContext(Dispatchers.IO) {
        val sftp = client(connectionId, sshClient)
        val total = localFile.length().coerceAtLeast(1)
        sftp.open(remotePath, setOf(OpenMode.WRITE, OpenMode.CREAT, OpenMode.TRUNC)).use { remote ->
            localFile.inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                var offset = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read == -1) break
                    remote.write(offset, buffer, 0, read)
                    offset += read
                    progress?.invoke(offset.toDouble() / total.toDouble())
                }
            }
        }
    }

    suspend fun createDirectory(connectionId: UUID, sshClient: SSHClient, path: String) = withContext(Dispatchers.IO) {
        client(connectionId, sshClient).mkdir(path)
    }

    suspend fun rename(connectionId: UUID, sshClient: SSHClient, from: String, to: String) = withContext(Dispatchers.IO) {
        client(connectionId, sshClient).rename(from, to)
    }

    suspend fun delete(connectionId: UUID, sshClient: SSHClient, path: String, isDirectory: Boolean) =
        withContext(Dispatchers.IO) {
            val sftp = client(connectionId, sshClient)
            if (isDirectory) sftp.rmdir(path) else sftp.rm(path)
        }

    suspend fun setPermissions(connectionId: UUID, sshClient: SSHClient, path: String, octalMode: Int) =
        withContext(Dispatchers.IO) {
            client(connectionId, sshClient).chmod(path, octalMode)
        }

    fun disconnect(connectionId: UUID) {
        runCatching { clients.remove(connectionId)?.close() }
    }

    private fun joinPath(parent: String, child: String): String =
        if (parent.endsWith("/")) "$parent$child" else "$parent/$child"

    /** Same rwxrwxrwx formatting as iOS `SFTPService.permissionsString(posixMode:)`. */
    private fun permissionsString(mode: Int): String {
        if (mode == 0) return "—"
        val bits = mode and 0x1FF
        val sb = StringBuilder()
        for (shift in intArrayOf(6, 3, 0)) {
            val triplet = (bits shr shift) and 0x7
            sb.append(if (triplet and 0b100 != 0) 'r' else '-')
            sb.append(if (triplet and 0b010 != 0) 'w' else '-')
            sb.append(if (triplet and 0b001 != 0) 'x' else '-')
        }
        return sb.toString()
    }
}
