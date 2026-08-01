import Foundation

struct GitHubUser: Decodable {
    let login: String
}

struct GitHubIssue: Decodable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let htmlURL: URL
    let user: GitHubUser
    let pullRequest: GitHubPullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, user
        case htmlURL = "html_url"
        case pullRequest = "pull_request"
    }
}

struct GitHubPullRequestMarker: Decodable {}

struct GitHubPullRequest: Decodable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let draft: Bool
    let htmlURL: URL
    let user: GitHubUser

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, draft, user
        case htmlURL = "html_url"
    }
}

enum GitHubServiceError: Error, LocalizedError {
    case missingToken
    case invalidResponse
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Add a GitHub personal access token in Settings."
        case .invalidResponse: return "GitHub returned an invalid response."
        case .api(let status, let message): return "GitHub error \(status): \(message)"
        }
    }
}

actor GitHubService {
    static let shared = GitHubService()

    func validateToken() async throws -> GitHubUser {
        try await request(path: "/user")
    }

    func issues(repository: String) async throws -> [GitHubIssue] {
        let values: [GitHubIssue] = try await request(path: "/repos/\(repository)/issues?state=open&per_page=30")
        return values.filter { $0.pullRequest == nil }
    }

    func pullRequests(repository: String) async throws -> [GitHubPullRequest] {
        try await request(path: "/repos/\(repository)/pulls?state=open&per_page=30")
    }

    private func request<Value: Decodable>(path: String) async throws -> Value {
        let token: String
        do { token = try KeychainService.githubToken() } catch { throw GitHubServiceError.missingToken }
        guard let url = URL(string: "https://api.github.com\(path)") else { throw GitHubServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TermVault-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubServiceError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Request failed"
            throw GitHubServiceError.api(http.statusCode, message)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
