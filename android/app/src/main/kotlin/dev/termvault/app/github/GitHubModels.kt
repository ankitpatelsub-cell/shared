package dev.termvault.app.github

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class GitHubUser(val login: String)

@Serializable
data class GitHubIssue(
    val id: Long,
    val number: Int,
    val title: String,
    val state: String,
    @SerialName("html_url") val htmlUrl: String,
    val user: GitHubUser,
    // Present (non-null) when GitHub's "issues" endpoint is actually
    // returning a pull request — mirrors iOS's empty `GitHubPullRequestMarker`
    // presence check, used to filter PRs out of the issues list.
    @SerialName("pull_request") val pullRequest: JsonElement? = null,
)

@Serializable
data class GitHubPullRequest(
    val id: Long,
    val number: Int,
    val title: String,
    val state: String,
    val draft: Boolean,
    @SerialName("html_url") val htmlUrl: String,
    val user: GitHubUser,
)
