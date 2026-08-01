import SwiftUI

@MainActor
private final class GitHubRepositoryViewModel: ObservableObject {
    let repository: String
    @Published var issues: [GitHubIssue] = []
    @Published var pullRequests: [GitHubPullRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init(repository: String) { self.repository = repository }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let issues = GitHubService.shared.issues(repository: repository)
            async let pulls = GitHubService.shared.pullRequests(repository: repository)
            self.issues = try await issues
            self.pullRequests = try await pulls
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GitHubRepositoryView: View {
    @StateObject private var viewModel: GitHubRepositoryViewModel

    init(repository: String) {
        _viewModel = StateObject(wrappedValue: GitHubRepositoryViewModel(repository: repository))
    }

    var body: some View {
        List {
            Section("Pull Requests") {
                if viewModel.pullRequests.isEmpty { Text("No open pull requests").foregroundStyle(.secondary) }
                ForEach(viewModel.pullRequests) { pull in
                    Link(destination: pull.htmlURL) {
                        GitHubRow(number: pull.number, title: pull.title, author: pull.user.login, badge: pull.draft ? "Draft" : "Open")
                    }
                }
            }
            Section("Issues") {
                if viewModel.issues.isEmpty { Text("No open issues").foregroundStyle(.secondary) }
                ForEach(viewModel.issues) { issue in
                    Link(destination: issue.htmlURL) {
                        GitHubRow(number: issue.number, title: issue.title, author: issue.user.login, badge: "Open")
                    }
                }
            }
        }
        .navigationTitle(viewModel.repository)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .overlay { if viewModel.isLoading { ProgressView() } }
        .task { await viewModel.load() }
        .alert("GitHub", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK") {} } message: { Text(viewModel.errorMessage ?? "") }
    }
}

private struct GitHubRow: View {
    let number: Int
    let title: String
    let author: String
    let badge: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("#\(number) \(title)").foregroundStyle(.primary)
            Text("\(badge) · \(author)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
