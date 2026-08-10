package dev.termvault.app.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import dev.termvault.app.diagnostics.ErrorLogger

@Database(
    entities = [
        HostEntity::class,
        IdentityEntity::class,
        SnippetEntity::class,
        WorkspaceSessionEntity::class,
        WorkspaceProjectEntity::class,
        AgentPresetEntity::class,
        WorkspaceFavoriteEntity::class,
        CommandHistoryEntity::class,
        CommandMacroEntity::class,
        SessionHistoryEntity::class,
        FileSyncRecordEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun hostDao(): HostDao
    abstract fun identityDao(): IdentityDao
    abstract fun snippetDao(): SnippetDao
    abstract fun workspaceSessionDao(): WorkspaceSessionDao
    abstract fun workspaceProjectDao(): WorkspaceProjectDao
    abstract fun agentPresetDao(): AgentPresetDao
    abstract fun workspaceFavoriteDao(): WorkspaceFavoriteDao
    abstract fun commandHistoryDao(): CommandHistoryDao
    abstract fun commandMacroDao(): CommandMacroDao
    abstract fun sessionHistoryDao(): SessionHistoryDao
    abstract fun fileSyncRecordDao(): FileSyncRecordDao

    companion object {
        private const val DB_NAME = "termvault.db"

        /**
         * Mirrors the resilience the iOS `ModelContainer` init grew: a
         * corrupted or otherwise unopenable on-disk store (full storage, a
         * force-quit mid-write, etc.) is a reachable real-world condition,
         * not something to `fatalError`/crash-loop on. Try a normal open;
         * on failure, delete the on-disk files and retry once; only fall
         * back to an in-memory database (data won't persist, but the app
         * stays usable for the session) if that retry also fails.
         */
        fun build(context: Context, errorLogger: ErrorLogger): AppDatabase {
            return runCatching { openOnDisk(context) }
                .recoverCatching {
                    context.deleteDatabase(DB_NAME)
                    openOnDisk(context)
                }
                .getOrElse { error ->
                    errorLogger.log(
                        ErrorLogger.Category.GENERAL,
                        "Local database could not be opened; falling back to in-memory storage for this session.",
                        technicalDetails = error.message,
                    )
                    Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
                        .fallbackToDestructiveMigration()
                        .build()
                }
        }

        private fun openOnDisk(context: Context): AppDatabase =
            Room.databaseBuilder(context, AppDatabase::class.java, DB_NAME)
                .fallbackToDestructiveMigration()
                .build()
                .also { it.openHelper.writableDatabase }
    }
}
