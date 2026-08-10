package dev.termvault.app.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import dev.termvault.app.data.model.IdentityKeyType
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Mirrors iOS `Identity.swift`. Metadata only — the private key PEM and
 * passphrase live exclusively in [dev.termvault.app.security.SecretStore],
 * never here.
 */
@Entity(tableName = "identities")
data class IdentityEntity(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val label: String,
    val keyTypeRaw: String,
    val fingerprint: String,
    val publicKey: String,
    val hasPassphrase: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val keyType: IdentityKeyType get() = IdentityKeyType.from(keyTypeRaw)
}

@Dao
interface IdentityDao {
    @Query("SELECT * FROM identities ORDER BY label ASC")
    fun observeAll(): Flow<List<IdentityEntity>>

    @Query("SELECT * FROM identities ORDER BY label ASC")
    suspend fun getAll(): List<IdentityEntity>

    @Query("SELECT * FROM identities WHERE id = :id")
    suspend fun getById(id: UUID): IdentityEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(identity: IdentityEntity)

    @Delete
    suspend fun delete(identity: IdentityEntity)
}
