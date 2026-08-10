package dev.termvault.app.github

import dev.termvault.app.security.SecretStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory

sealed class GitHubServiceError(message: String) : Exception(message) {
    object MissingToken : GitHubServiceError("Add a GitHub personal access token in Settings.")
    class Api(status: Int, apiMessage: String) : GitHubServiceError("GitHub error $status: $apiMessage")
}

/** Mirrors iOS `GitHubService.swift` — validate a PAT, list open issues/PRs for a `owner/repo` slug. */
class GitHubService(private val secretStore: SecretStore) {
    private val json = Json { ignoreUnknownKeys = true }

    private val client = OkHttpClient.Builder()
        .addInterceptor(Interceptor { chain ->
            val request = chain.request().newBuilder()
                .header("Accept", "application/vnd.github+json")
                .header("X-GitHub-Api-Version", "2026-03-10")
                .header("User-Agent", "TermVault-Android")
                .build()
            chain.proceed(request)
        })
        .build()

    private val api: GitHubApi = Retrofit.Builder()
        .baseUrl("https://api.github.com/")
        .client(client)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(GitHubApi::class.java)

    suspend fun validateToken(): GitHubUser = withContext(Dispatchers.IO) {
        perform { api.user(bearerToken()) }
    }

    suspend fun issues(repository: String): List<GitHubIssue> = withContext(Dispatchers.IO) {
        val (owner, repo) = splitRepository(repository)
        perform { api.issues(owner, repo, bearerToken()) }.filter { it.pullRequest == null }
    }

    suspend fun pullRequests(repository: String): List<GitHubPullRequest> = withContext(Dispatchers.IO) {
        val (owner, repo) = splitRepository(repository)
        perform { api.pullRequests(owner, repo, bearerToken()) }
    }

    private fun splitRepository(repository: String): Pair<String, String> {
        val parts = repository.trim().trimStart('/').split("/")
        require(parts.size == 2) { "Repository must be in \"owner/repo\" form." }
        return parts[0] to parts[1]
    }

    private fun bearerToken(): String {
        val token = secretStore.githubToken() ?: throw GitHubServiceError.MissingToken
        return "Bearer $token"
    }

    private suspend fun <T> perform(call: suspend () -> T): T {
        try {
            return call()
        } catch (e: HttpException) {
            val body = e.response()?.errorBody()?.string()
            val message = body?.let { runCatching { json.parseToJsonElement(it).jsonObject["message"]?.jsonPrimitive?.content }.getOrNull() }
            throw GitHubServiceError.Api(e.code(), message ?: "Request failed")
        }
    }
}
