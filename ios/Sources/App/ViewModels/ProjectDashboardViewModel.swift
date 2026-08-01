import Foundation

struct ToolAvailability: Identifiable {
    let name: String
    let version: String?
    var id: String { name }
    var isInstalled: Bool { version != nil }
}

@MainActor
final class ProjectDashboardViewModel: ObservableObject {
    let host: Host
    let path: String

    @Published var branch = "—"
    @Published var gitStatus = "Not loaded"
    @Published var recentCommits = ""
    @Published var tools: [ToolAvailability] = []
    @Published var tmuxSessions: [String] = []
    @Published var commandOutput = ""
    @Published var githubRepository: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    init(host: Host, path: String) {
        self.host = host
        self.path = path
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let root = Self.quote(path)
            async let gitResult = RemoteCommandService.shared.run(
                hostID: host.id,
                command: "cd -- \(root) && printf '%s\\n' \"$(git branch --show-current 2>/dev/null || true)\" && git status --short --branch 2>/dev/null || true"
            )
            async let logResult = RemoteCommandService.shared.run(
                hostID: host.id,
                command: "cd -- \(root) && git log -5 --pretty=format:'%h  %s' 2>/dev/null || true"
            )
            async let toolResult = RemoteCommandService.shared.run(
                hostID: host.id,
                command: "for t in tmux git codex claude hermes; do if command -v \"$t\" >/dev/null 2>&1; then printf '%s\\t%s\\n' \"$t\" \"$(\"$t\" --version 2>/dev/null | head -n 1)\"; else printf '%s\\t\\n' \"$t\"; fi; done"
            )
            async let tmuxResult = RemoteCommandService.shared.run(
                hostID: host.id,
                command: "tmux list-sessions -F '#{session_name}\\t#{session_attached}\\t#{session_activity}' 2>/dev/null || true"
            )
            async let originResult = RemoteCommandService.shared.run(
                hostID: host.id,
                command: "cd -- \(root) && git remote get-url origin 2>/dev/null || true"
            )

            let git = try await gitResult
            let lines = git.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            branch = lines.first?.isEmpty == false ? lines[0] : "Not a Git repository"
            gitStatus = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if gitStatus.isEmpty { gitStatus = branch == "Not a Git repository" ? "No repository found" : "Working tree clean" }
            recentCommits = try await logResult
            tools = Self.parseTools(try await toolResult)
            tmuxSessions = (try await tmuxResult).split(separator: "\n").map(String.init)
            githubRepository = Self.githubSlug(from: try await originResult)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func run(_ command: String) async {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            commandOutput = try await RemoteCommandService.shared.run(
                hostID: host.id,
                command: "cd -- \(Self.quote(path)) && \(command)"
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func parseTools(_ output: String) -> [ToolAvailability] {
        output.split(separator: "\n").map { line in
            let values = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            return ToolAvailability(
                name: String(values[0]),
                version: values.count > 1 && !values[1].isEmpty ? String(values[1]) : nil
            )
        }
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func githubSlug(from remote: String) -> String? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@github.com:") {
            value.removeFirst("git@github.com:".count)
        } else if value.hasPrefix("https://github.com/") {
            value.removeFirst("https://github.com/".count)
        } else if value.hasPrefix("ssh://git@github.com/") {
            value.removeFirst("ssh://git@github.com/".count)
        } else {
            return nil
        }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value.split(separator: "/").count == 2 ? value : nil
    }
}
