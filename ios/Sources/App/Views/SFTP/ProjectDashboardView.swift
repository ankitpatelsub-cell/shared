import SwiftUI

struct ProjectDashboardView: View {
    @StateObject private var viewModel: ProjectDashboardViewModel
    @AppStorage("dev.termvault.savedCommands") private var savedCommandsData = "[]"
    @State private var command = ""

    init(host: Host, path: String) {
        _viewModel = StateObject(wrappedValue: ProjectDashboardViewModel(host: host, path: path))
    }

    var body: some View {
        List {
            Section("Project") {
                LabeledContent("Host", value: viewModel.host.label)
                LabeledContent("Folder", value: viewModel.path)
                LabeledContent("Branch", value: viewModel.branch)
                if let repository = viewModel.githubRepository {
                    NavigationLink {
                        GitHubRepositoryView(repository: repository)
                    } label: {
                        Label(repository, systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
            }

            Section("Git Status") {
                Text(viewModel.gitStatus).font(.system(.caption, design: .monospaced))
                if !viewModel.recentCommits.isEmpty {
                    Text(viewModel.recentCommits).font(.system(.caption, design: .monospaced))
                }
                HStack {
                    taskButton("Pull", command: "git pull --ff-only")
                    taskButton("Fetch", command: "git fetch --all --prune")
                    taskButton("Diff", command: "git diff --stat")
                }
            }

            Section("Remote Tools") {
                ForEach(viewModel.tools) { tool in
                    HStack {
                        Label(tool.name, systemImage: tool.isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(tool.isInstalled ? .green : .secondary)
                        Spacer()
                        Text(tool.version ?? "Not installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Agent Sessions") {
                if viewModel.tmuxSessions.isEmpty {
                    Text("No remote tmux sessions").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.tmuxSessions, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)) }
                }
            }

            Section("Run Project Command") {
                TextField("npm test, swift test, make…", text: $command)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Run") { Task { await viewModel.run(command) } }
                    .disabled(command.isEmpty || viewModel.isLoading)
                ForEach(savedCommands, id: \.self) { saved in
                    Button(saved) { Task { await viewModel.run(saved) } }
                }
                if !command.isEmpty && !savedCommands.contains(command) {
                    Button("Save Command") { saveCommand(command) }
                }
            }

            if !viewModel.commandOutput.isEmpty {
                Section("Output") {
                    Text(viewModel.commandOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Project Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .overlay { if viewModel.isLoading { ProgressView() } }
        .task { await viewModel.refresh() }
        .alert("Command Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK") {} } message: { Text(viewModel.errorMessage ?? "") }
    }

    private func taskButton(_ title: String, command: String) -> some View {
        Button(title) { Task { await viewModel.run(command) } }
            .buttonStyle(.bordered)
    }

    private var savedCommands: [String] {
        guard let data = savedCommandsData.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }

    private func saveCommand(_ value: String) {
        var values = savedCommands
        values.append(value)
        if let data = try? JSONEncoder().encode(Array(values.suffix(12))),
           let text = String(data: data, encoding: .utf8) {
            savedCommandsData = text
        }
    }
}
