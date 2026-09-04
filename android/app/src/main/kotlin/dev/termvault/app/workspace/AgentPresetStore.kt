package dev.termvault.app.workspace

import dev.termvault.app.data.db.AgentPresetDao
import dev.termvault.app.data.db.AgentPresetEntity
import dev.termvault.app.data.model.AgentTool
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Mirrors iOS `AgentPresetStore`, backed by Room; seeds one default preset per built-in tool on first launch. */
class AgentPresetStore(private val dao: AgentPresetDao, scope: CoroutineScope) {
    val presets: StateFlow<List<AgentPresetEntity>> =
        dao.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())

    init {
        scope.launch(Dispatchers.IO) {
            if (dao.count() == 0) {
                dao.upsert(AgentPresetEntity(name = "Codex", toolRaw = AgentTool.CODEX.rawValue))
                dao.upsert(AgentPresetEntity(name = "Claude", toolRaw = AgentTool.CLAUDE.rawValue))
                dao.upsert(AgentPresetEntity(name = "Hermes", toolRaw = AgentTool.HERMES.rawValue))
                dao.upsert(AgentPresetEntity(name = "Project Shell", toolRaw = AgentTool.SHELL.rawValue))
            }
        }
    }

    suspend fun save(preset: AgentPresetEntity) {
        dao.upsert(preset)
    }

    suspend fun delete(preset: AgentPresetEntity) {
        dao.delete(preset)
    }
}
