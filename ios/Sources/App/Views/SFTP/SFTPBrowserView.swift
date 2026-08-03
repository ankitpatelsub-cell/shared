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
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .nameAsc
    @State private var isMultiSelectMode = false
    @State private var selectedEntries: Set<UUID> = []

    init(host: Host, connectionID: UUID, sshClient: SSHClient, onLaunch: ((String, AgentTool) -> Void)? = nil, onLaunchPreset: ((String, AgentPreset) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: SFTPBrowserViewModel(host: host, connectionID: connectionID, sshClient: sshClient))
        self.onLaunch = onLaunch
        self.onLaunchPreset = onLaunchPreset
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            
            // Search bar & Sort picker
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                // Sort picker
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            
            List {
                ForEach(filteredAndSortedEntries) { entry in
                    SFTPEntryRow(
                        entry: entry,
                        isSelected: selectedEntries.contains(entry.id),
                        isMultiSelectMode: isMultiSelectMode,
                        onTap: {
                            if isMultiSelectMode {
                                toggleSelection(entry.id)
                            } else {
                                Task { await viewModel.open(entry) }
                            }
                        },
                        onDownload: {
                            Task { downloadedURL = await viewModel.download(entry) }
                        }
                    )
                    .swipeActions {
                        if !isMultiSelectMode {
                            Button(role: .destructive) {
                                deletingEntry = entry
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .contextMenu {
                        if !isMultiSelectMode {
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
                if isMultiSelectMode {
                    Button("Cancel") {
                        isMultiSelectMode = false
                        selectedEntries.removeAll()
                    }
                    Menu {
                        Button("Select All") {
                            selectedEntries = Set(filteredAndSortedEntries.map(\.id))
                        }
                        Button("Deselect All") {
                            selectedEntries.removeAll()
                        }
                        Divider()
                        if !selectedEntries.isEmpty {
                            Button("Download Selected") {
                                Task { await downloadSelected() }
                            }
                            Button("Delete Selected", role: .destructive) {
                                Task { await deleteSelected() }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
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
                    Button {
                        isMultiSelectMode = true
                    } label: { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Select multiple")
                }
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

    private func toggleSelection(_ id: UUID) {
        if selectedEntries.contains(id) {
            selectedEntries.remove(id)
        } else {
            selectedEntries.insert(id)
        }
    }
    
    private func downloadSelected() async {
        let entriesToDownload = filteredAndSortedEntries.filter { selectedEntries.contains($0.id) }
        for entry in entriesToDownload {
            _ = await viewModel.download(entry)
        }
        isMultiSelectMode = false
        selectedEntries.removeAll()
    }
    
    private func deleteSelected() async {
        let entriesToDelete = filteredAndSortedEntries.filter { selectedEntries.contains($0.id) }
        for entry in entriesToDelete {
            await viewModel.delete(entry)
        }
        isMultiSelectMode = false
        selectedEntries.removeAll()
    }
    
    private var breadcrumbBar: some View {
        HStack {
            Button { Task { await viewModel.goUp() } } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(viewModel.currentPath == "/")
            
            // Breadcrumb path with tap-to-jump
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(breadcrumbSegments, id: \.self) { segment in
                        if segment == breadcrumbSegments.last {
                            Text(segment)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.primary)
                        } else {
                            Button(action: { navigateToBreadcrumb(segment) }) {
                                Text(segment)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .lineLimit(1)
            
            Spacer()
            
            if isMultiSelectMode {
                Text("\(selectedEntries.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
    
    private var breadcrumbSegments: [String] {
        let path = viewModel.currentPath
        if path == "/" { return ["/"] }
        let components = path.split(separator: "/").map(String.init)
        var segments = ["/"]
        var current = ""
        for comp in components {
            current += "/" + comp
            segments.append(comp)
        }
        return segments
    }
    
    private func navigateToBreadcrumb(_ segment: String) {
        if segment == "/" {
            Task { await viewModel.load(path: "/") }
        } else {
            let idx = breadcrumbSegments.firstIndex(of: segment) ?? 0
            let targetPath = breadcrumbSegments[1...idx].joined(separator: "/")
            Task { await viewModel.load(path: "/" + targetPath) }
        }
    }

    private var filteredAndSortedEntries: [SFTPEntry] {
        var entries = viewModel.entries
        
        // Filter by search text
        if !searchText.isEmpty {
            entries = entries.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Sort
        switch sortOrder {
        case .nameAsc:
            entries.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameDesc:
            entries.sort { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .sizeAsc:
            entries.sort { $0.size < $1.size }
        case .sizeDesc:
            entries.sort { $0.size > $1.size }
        case .dateAsc:
            entries.sort { ($0.modifiedAt ?? Date.distantPast) < ($1.modifiedAt ?? Date.distantPast) }
        case .dateDesc:
            entries.sort { ($0.modifiedAt ?? Date.distantPast) > ($1.modifiedAt ?? Date.distantPast) }
        }
        
        return entries
    }

enum SortOrder: String, CaseIterable, Identifiable {
    case nameAsc = "Name ↑"
    case nameDesc = "Name ↓"
    case sizeAsc = "Size ↑"
    case sizeDesc = "Size ↓"
    case dateAsc = "Date ↑"
    case dateDesc = "Date ↓"
    var id: String { rawValue }
}

private struct SFTPEntryRow: View {
    let entry: SFTPEntry
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let onTap: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack {
            if isMultiSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title2)
            }
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
            VStack(alignment: .leading) {
                Text(entry.name)
                Text("\(entry.permissions) · \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !entry.isDirectory && !isMultiSelectMode {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
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
}
