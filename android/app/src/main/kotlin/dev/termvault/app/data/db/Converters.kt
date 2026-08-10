package dev.termvault.app.data.db

import androidx.room.TypeConverter
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

/**
 * Room only stores primitives natively, so every richer type used across
 * the entities below (UUID, String lists/maps used for tags, macro
 * command lists, workspace env vars, etc.) needs an explicit converter.
 * JSON (via kotlinx.serialization) rather than a delimiter-joined string
 * avoids ambiguity if a value itself contains the delimiter.
 */
class Converters {
    private val json = Json { ignoreUnknownKeys = true }

    @TypeConverter
    fun uuidToString(value: UUID?): String? = value?.toString()

    @TypeConverter
    fun stringToUuid(value: String?): UUID? = value?.let(UUID::fromString)

    @TypeConverter
    fun stringListToJson(value: List<String>?): String? = value?.let { json.encodeToString(it) }

    @TypeConverter
    fun jsonToStringList(value: String?): List<String>? =
        value?.let { json.decodeFromString<List<String>>(it) }

    @TypeConverter
    fun uuidListToJson(value: List<UUID>?): String? =
        value?.let { json.encodeToString(it.map(UUID::toString)) }

    @TypeConverter
    fun jsonToUuidList(value: String?): List<UUID>? =
        value?.let { json.decodeFromString<List<String>>(it).map(UUID::fromString) }

    @TypeConverter
    fun stringMapToJson(value: Map<String, String>?): String? = value?.let { json.encodeToString(it) }

    @TypeConverter
    fun jsonToStringMap(value: String?): Map<String, String>? =
        value?.let { json.decodeFromString<Map<String, String>>(it) }
}
