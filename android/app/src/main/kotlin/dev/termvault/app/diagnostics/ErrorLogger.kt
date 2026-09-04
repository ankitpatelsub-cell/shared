package dev.termvault.app.diagnostics

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * App-wide, disk-persisted error/event log. Mirrors iOS `ErrorLogger.swift`
 * — same categories, same disk-backed `LogEntry` shape, same
 * error-message-sniffing `suggestedAction` heuristic.
 */
class ErrorLogger(context: Context) {
    enum class Category(val label: String) {
        NETWORK("Network"),
        AUTHENTICATION("Authentication"),
        HOST_KEY("Host Key"),
        FILE_OPERATION("File Operation"),
        GENERAL("General"),
    }

    @Serializable
    data class LogEntry(
        val id: String = UUID.randomUUID().toString(),
        val timestamp: Long,
        val category: String,
        val message: String,
        val technicalDetails: String? = null,
        val suggestion: String? = null,
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val file = File(File(context.filesDir, "TermVaultLogs"), "errors.json")
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _logs = MutableStateFlow<List<LogEntry>>(emptyList())
    val logs: StateFlow<List<LogEntry>> = _logs.asStateFlow()

    init {
        scope.launch { loadFromDisk() }
    }

    fun log(category: Category, message: String, technicalDetails: String? = null, suggestion: String? = null) {
        Log.e("TermVault/${category.label}", message + (technicalDetails?.let { " ($it)" } ?: ""))
        scope.launch {
            mutex.withLock {
                val entry = LogEntry(
                    timestamp = System.currentTimeMillis(),
                    category = category.name,
                    message = message,
                    technicalDetails = technicalDetails,
                    suggestion = suggestion,
                )
                _logs.value = _logs.value + entry
                saveToDisk(_logs.value)
            }
        }
    }

    fun clearLogs() {
        scope.launch {
            mutex.withLock {
                _logs.value = emptyList()
                saveToDisk(emptyList())
            }
        }
    }

    fun exportAsText(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        return _logs.value.joinToString("\n\n") { entry ->
            buildString {
                append(formatter.format(Date(entry.timestamp)))
                append(" [").append(entry.category).append("] ")
                append(entry.message)
                entry.technicalDetails?.let { append("\n").append(it) }
                entry.suggestion?.let { append("\nSuggestion: ").append(it) }
            }
        }
    }

    private fun loadFromDisk() {
        if (!file.exists()) return
        runCatching {
            val entries = json.decodeFromString<List<LogEntry>>(file.readText())
            _logs.value = entries
        }
    }

    private fun saveToDisk(entries: List<LogEntry>) {
        runCatching {
            file.parentFile?.mkdirs()
            file.writeText(json.encodeToString(entries))
        }
    }

    companion object {
        /** Same string-sniffing heuristic as the iOS `suggestedAction(for:)` extension. */
        fun suggestedAction(error: Throwable): String? {
            val message = (error.message ?: error.toString()).lowercase()
            return when {
                "timed out" in message || "unable to connect" in message ->
                    "Check that the host address and port are correct, and that the device has network access."
                "connection refused" in message ->
                    "Make sure the SSH service is running on the remote host."
                "permission denied" in message || "authentication failed" in message ->
                    "Check the username, password, or SSH key — and that the key file has the correct permissions (600) on the remote host."
                "host key verification failed" in message ->
                    "The remote host's key has changed. Verify this is expected before trusting the new key."
                "no such file" in message ->
                    "Check that the remote path exists."
                else -> null
            }
        }
    }
}
