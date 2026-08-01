import SwiftUI
import Citadel

struct SFTPBrowserView: View {
    @StateObject private var viewModel: SFTPBrowserViewModel
    let onLaunch: ((String, AgentTool) -> Void)?
    let onLaunchPreset: ((String, AgentPreset) -> Void)?
    @EnvironmentObject private var presetStore: AgentPresetStore
    @State private var showingImporter = false
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renamingEntry: SFTPEntry?
    @State private var renameText = ""
    @State private var downloadedURL: URL?
    @State private var editingFile: SFTPEntry?
    @State private var operatingOnEntry: SFTPEntry?
    @State private var deletingEntry: SFTPEntry?

    init(host: Host, connectionID: UUID, sshClient: SSHClient, onLaunch: ((String, AgentTool) -> Void)? = nil, onLaunchPreset: ((String, AgentPreset) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: SFTPBrowserViewModel(host: host, connectionID: connectionID, sshClient: sshClient))
        self.onLaunch = onLaunch
        self.onLaunchPreset = onLaunchPreset
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            List {
                ForEach(viewModel.entries) { entry in
                    SFTPEntryRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await viewModel.open(entry) }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deletingEntry = entry
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .contextMenu {
                            if entry.isDirectory, let onLaunch {
                                Menu("Start Agent Here") {
                                    ForEach(AgentTool.allCases) { tool in
                                        Button(tool.title) { onLaunch(entry.path, tool) }
                                    }
                                }
                            }
                            Button("Rename") {
                                renameText = entry.name
                                renamingEntry = entry
                            }
                            Button("Copy, Move or Permissions") { operatingOnEntry = entry }
                            if !entry.isDirectory {
                                Button("Preview / Edit") { editingFile = entry }
                                Button("Download") {
                                    Task { downloadedURL = await viewModel.download(entry) }
                                }
                            }
                        }
                }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading { ProgressView() }
            }
        }
        .navigationTitle(viewModel.currentPath)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink {
                    ProjectDashboardView(host: viewModel.host, path: viewModel.currentPath)
                } label: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
                .accessibilityLabel("Project dashboard")
                if let onLaunch {
                    Menu {
                        if let onLaunchPreset, !presetStore.presets.isEmpty {
                            Section("Presets") {
                                ForEach(presetStore.presets) { preset in
                                    Button { onLaunchPreset(viewModel.currentPath, preset) } label: {
                                        Label(preset.name, systemImage: preset.tool.icon)
                                    }
                                }
                            }
                        }
                        Section("Tools") {
                        ForEach(AgentTool.allCases) { tool in
                            Button {
                                onLaunch(viewModel.currentPath, tool)
                            } label: {
                                Label("Start \(tool.title)", systemImage: tool.icon)
                            }
                        }
                        }
                    } label: {
                        Image(systemName: "play.rectangle.on.rectangle")
                    }
                    .accessibilityLabel("Start tool in this folder")
                }
                Button { showingImporter = true } label: { Image(systemName: "square.and.arrow.up") }
                Button { showingNewFolderAlert = true } label: { Image(systemName: "folder.badge.plus") }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await viewModel.upload(localURL: url) }
            }
        }
        .alert("New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task {
                    await viewModel.createFolder(named: newFolderName)
                    newFolderName = ""
                }
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renamingEntry != nil },
            set: { if !$0 { renamingEntry = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingEntry = nil }
            Button("Rename") {
                guard let entry = renamingEntry else { return }
                Task { await viewModel.rename(entry, to: renameText) }
                renamingEntry = nil
            }
        }
        .alert("Delete \(deletingEntry?.name ?? "Item")?", isPresented: Binding(
            get: { deletingEntry != nil },
            set: { if !$0 { deletingEntry = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let entry = deletingEntry else { return }
                Task { await viewModel.delete(entry) }
                deletingEntry = nil
            }
        } message: {
            Text(deletingEntry?.isDirectory == true ? "The folder must be empty. This cannot be undone." : "This cannot be undone.")
        }
        .sheet(isPresented: Binding(
            get: { downloadedURL != nil },
            set: { if !$0 { downloadedURL = nil } }
        )) {
            if let downloadedURL {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                        Text(downloadedURL.lastPathComponent)
                        ShareLink(item: downloadedURL) { Label("Share or Save File", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                    }
                    .navigationTitle("Download Complete")
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(item: $editingFile) { entry in
            RemoteFileEditorView(browser: viewModel, entry: entry)
        }
        .sheet(item: $operatingOnEntry) { entry in
            RemoteFileOperationsView(browser: viewModel, entry: entry)
        }
        .overlay(alignment: .bottom) {
            if let text = viewModel.transferProgressText {
                ProgressBanner(text: text)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
    }

    private var breadcrumbBar: some View {
        HStack {
            Button { Task { await viewModel.goUp() } } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(viewModel.currentPath == "/")
            Text(viewModel.currentPath)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct SFTPEntryRow: View {
    let entry: SFTPEntry

    var body: some View {
        HStack {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
            VStack(alignment: .leading) {
                Text(entry.name)
                Text("\(entry.permissions) · \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct ProgressBanner: View {
    let text: String

    var body: some View {
        HStack {
            ProgressView()
            Text(text)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}
