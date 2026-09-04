package dev.termvault.app.data.model

import java.util.UUID

data class SftpEntry(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val path: String,
    val isDirectory: Boolean,
    val size: Long,
    val permissions: String,
    val modifiedAt: Long?,
)
