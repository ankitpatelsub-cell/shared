package dev.termvault.app.history

import dev.termvault.app.data.db.CommandMacroDao
import dev.termvault.app.data.db.CommandMacroEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Mirrors iOS `CommandMacroStore`, backed by Room; seeds the same five default macros on first launch. */
class CommandMacroStore(private val dao: CommandMacroDao, scope: CoroutineScope) {
    val macros: StateFlow<List<CommandMacroEntity>> =
        dao.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())

    init {
        scope.launch(Dispatchers.IO) {
            if (dao.count() == 0) {
                dao.upsertAll(defaultMacros())
            }
        }
    }

    suspend fun addMacro(macro: CommandMacroEntity) {
        if (macros.value.any { it.name == macro.name }) return
        dao.upsert(macro)
    }

    suspend fun updateMacro(macro: CommandMacroEntity) {
        dao.upsert(macro)
    }

    suspend fun deleteMacro(macro: CommandMacroEntity) {
        dao.delete(macro)
    }

    private fun defaultMacros() = listOf(
        CommandMacroEntity(name = "Clear Screen", commands = listOf("clear"), icon = "eraser", description = "Clear terminal screen"),
        CommandMacroEntity(name = "System Info", commands = listOf("uname -a", "whoami"), icon = "info.circle", description = "Show system information"),
        CommandMacroEntity(name = "List Files", commands = listOf("ls -lah"), icon = "folder", description = "List all files with details"),
        CommandMacroEntity(name = "Git Status", commands = listOf("git status"), icon = "square.and.pencil", description = "Check git status"),
        CommandMacroEntity(
            name = "Update System",
            commands = listOf("sudo apt update", "sudo apt upgrade -y"),
            icon = "arrow.up.square",
            description = "Update system packages",
        ),
    )
}
