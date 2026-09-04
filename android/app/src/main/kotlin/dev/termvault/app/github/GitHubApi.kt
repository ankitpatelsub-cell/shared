package dev.termvault.app.github

import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path
import retrofit2.http.Query

interface GitHubApi {
    @GET("user")
    suspend fun user(@Header("Authorization") authorization: String): GitHubUser

    @GET("repos/{owner}/{repo}/issues")
    suspend fun issues(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Header("Authorization") authorization: String,
        @Query("state") state: String = "open",
        @Query("per_page") perPage: Int = 30,
    ): List<GitHubIssue>

    @GET("repos/{owner}/{repo}/pulls")
    suspend fun pullRequests(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Header("Authorization") authorization: String,
        @Query("state") state: String = "open",
        @Query("per_page") perPage: Int = 30,
    ): List<GitHubPullRequest>
}
