package dev.termvault.app.cloud

import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.PUT

/** Mirrors the real `backend/termvault/server.py` contract exactly (verified by reading its source). */
interface CloudVaultApi {
    @POST("v1/register")
    suspend fun register(@Body body: AuthRequest): AuthResponse

    @POST("v1/login")
    suspend fun login(@Body body: AuthRequest): AuthResponse

    @GET("v1/vault")
    suspend fun getVault(@Header("Authorization") authorization: String): VaultReadResponse

    @PUT("v1/vault")
    suspend fun putVault(@Header("Authorization") authorization: String, @Body body: VaultWriteRequest): VaultWriteResponse
}
