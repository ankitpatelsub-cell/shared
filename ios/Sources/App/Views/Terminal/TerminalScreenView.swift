import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct TerminalScreenView: View {
    @Query(sort: \Snippet.name) private var snippets: [Snippet]
    @ObservedObject var viewModel: TerminalViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var navigationStore: AppNavigationStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingSFTP = false
    @State private var showingTranscript = false
    @State private var showingCloseConfirmation = false
    @State private var showingRename = false
    @State private var showingCommandPalette = false
    @State private var showingPortForwarding = false
    @State private var renameText = ""
    @State private var fontSizeAtGestureStart: Double?
    @State private var showingFileImporter = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isUploadingAttachments = false
    @State private var attachmentMessage: String?
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var showingCommandHistory = false
    @State private var showingMacros = false
    @State private var showingOutputFilter = false
    @State private var showingWorkspaceFavorites = false
    @State private var showingTerminalSettings = false
    @AppStorage("dev.termvault.settings.fontSize") private var fontSize: Double = 14
    @AppStorage("dev.termvault.settings.gesturesEnabled") private var gesturesEnabled = true
    @AppStorage("dev.termvault.settings.terminalFont") private var terminalFont = "system"
    @AppStorage("dev.termvault.settings.terminalTheme") private var terminalTheme = "midnight"

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .trailing) {
                TerminalRepresentable(terminalView: viewModel.terminalView)
                    // Keep edge glyphs clear of the display boundary. Without a
                    // gutter, SwiftTerm's first column can be visibly clipped.
                    .padding(.horizontal, 6)
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                let start = fontSizeAtGestureStart ?? fontSize
                                fontSizeAtGestureStart = start
                                fontSize = min(24, max(10, start * Double(scale)))
                            }
                            .onEnded { _ in fontSizeAtGestureStart = nil }
                    )
                    .gesture(gesturesEnabled ? AnyGesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                handleSwipe(value)
                            }
                    ) : AnyGesture(TapGesture().onEnded { }))

                if viewModel.isViewingHistory {
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(.white.opacity(0.5))
                            .frame(width: 2, height: CGFloat(viewModel.scrollPosition * 60))

                        Spacer(minLength: 0)
                    }
                    .frame(height: 80)
                    .padding(.vertical, 12)
                    .padding(.trailing, 4)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExtraKeysAccessoryView(viewModel: viewModel)
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isViewingHistory {
                VStack(spacing: 8) {
                    Button {
                        viewModel.scrollPage(-1)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.caption.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.ultraThinMaterial))
                    }

                    Button {
                        viewModel.scrollToLatestOutput()
                    } label: {
                        VStack(spacing: 2) {
                            Label("Latest", systemImage: "arrow.down.to.line")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button {
                        viewModel.scrollPage(1)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 56)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            if isUploadingAttachments {
                ProgressView(viewModel.attachmentUploadProgress ?? "Preparing attachment…")
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .overlay(alignment: .top) {
            if let status = viewModel.autoReconnectStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8, anchor: .center)

                    Text(status)
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Button {
                        viewModel.cancelAutoReconnect()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .cornerRadius(8)
                .padding(12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .tabBar)
        .task {
            applyFontSize()
            applyTerminalTheme()
            if viewModel.status == .disconnected {
                await viewModel.reconnect()
            }
        }
        .onChange(of: fontSize) { _, _ in applyFontSize() }
        .onChange(of: terminalFont) { _, _ in applyFontSize() }
        .onChange(of: terminalTheme) { _, _ in applyTerminalTheme() }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await uploadPhotos(items) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): Task { await uploadSecurityScopedFiles(urls) }
            case .failure(let error): attachmentMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingSFTP) {
            NavigationStack {
                SFTPGateView(host: viewModel.host, connectionID: viewModel.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showingSFTP = false } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingTranscript) {
            TerminalTranscriptView(viewModel: viewModel)
        }
        .alert("Paste Multiple Lines?", isPresented: Binding(
            get: { viewModel.pendingMultilinePaste != nil },
            set: { if !$0 { viewModel.pendingMultilinePaste = nil } }
        )) {
            Button("Cancel", role: .cancel) { viewModel.pendingMultilinePaste = nil }
            Button("Paste", role: .destructive) { viewModel.confirmMultilinePaste() }
        } message: {
            Text("Pasting multiple lines can execute commands immediately on the remote host.")
        }
        .alert("Close Session?", isPresented: $showingCloseConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Close", role: .destructive) { sessionStore.close(viewModel) }
        } message: {
            Text("The SSH connection will be disconnected. Remote tmux work will remain available.")
        }
        .alert("Rename Session", isPresented: $showingRename) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let value = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                sessionStore.rename(viewModel, to: value.isEmpty ? nil : value)
            }
        }
        .alert("Attachment", isPresented: Binding(
            get: { attachmentMessage != nil },
            set: { if !$0 { attachmentMessage = nil } }
        )) {
            Button("OK") { attachmentMessage = nil }
        } message: {
            Text(attachmentMessage ?? "")
        }
        .sheet(isPresented: $showingCommandPalette) {
            CommandPaletteView(isPresented: $showingCommandPalette) { action in
                handleCommandPaletteAction(action)
            }
        }
        .sheet(isPresented: $showingPortForwarding) {
            PortForwardingView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSearch) {
            TerminalSearchView(transcript: viewModel.plainTextTranscript, isPresented: $showingSearch)
        }
        .sheet(isPresented: $showingCommandHistory) {
            CommandHistoryView(hostID: viewModel.host.id)
        }
        .sheet(isPresented: $showingMacros) {
            CommandMacroView { commands in
                Task {
                    for command in commands {
                        try? await viewModel.send(command)
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
        }
        .sheet(isPresented: $showingOutputFilter) {
            OutputFilterView(transcript: viewModel.plainTextTranscript, isPresented: $showingOutputFilter)
        }
        .sheet(isPresented: $showingTerminalSettings) {
            TerminalSettingsView()
        }
        .sheet(isPresented: $showingWorkspaceFavorites) {
            WorkspaceFavoritesView()
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            topBarButton("chevron.left") {
                if navigationStore.selectedTab == .sessions {
                    navigationStore.goBack(fallback: viewModel.activeWorkspace == nil ? .hosts : .browser)
                } else {
                    dismiss()
                }
            }
            .accessibilityLabel("Back")

            HostAvatarView(label: viewModel.host.label, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayTitle)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 8) {
                    statusBadge

                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                        .font(.caption)

                    Text(viewModel.startedAt, style: .relative)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 4)

            topBarButton("folder") { showingSFTP = true }
                .accessibilityLabel("Browse remote files")
            Menu {
                sessionSwitcher
                Divider()
                Button { showingSearch = true } label: {
                    Label("Find in Output", systemImage: "magnifyingglass")
                }
                Button { showingOutputFilter = true } label: {
                    Label("Filter Output", systemImage: "line.3.horizontal.decrease.circle")
                }
                Button { showingCommandHistory = true } label: {
                    Label("Command History", systemImage: "clock.arrow.circlepath")
                }
                Button { showingMacros = true } label: {
                    Label("Macros", systemImage: "hammer")
                }
                Button { showingTranscript = true } label: {
                    Label("View Transcript", systemImage: "doc.text.magnifyingglass")
                }
                if !snippets.isEmpty {
                    Menu("Insert Snippet") {
                        ForEach(snippets) { snippet in
                            Button(snippet.name) {
                                viewModel.sendRawBytes(Array(snippet.command.utf8))
                            }
                        }
                    }
                }
                Button { showingFileImporter = true } label: {
                    Label("Attach File", systemImage: "paperclip")
                }
                .accessibilityHint("Uploads a local file to the connected host and inserts its path")
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 5, matching: .images) {
                    Label("Attach Photo", systemImage: "photo")
                }
                .accessibilityHint("Uploads photos to the connected host and inserts their paths")
                Button {
                    renameText = viewModel.customTitle ?? viewModel.displayTitle
                    showingRename = true
                } label: { Label("Rename Session", systemImage: "pencil") }
                Button {
                    sessionStore.togglePin(viewModel)
                } label: {
                    Label(viewModel.isPinned ? "Unpin Session" : "Pin Session", systemImage: "pin")
                }
                if canReconnect {
                    Button { Task { await viewModel.reconnect() } } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                }
                Divider()
                Button {
                    sessionStore.openNewTab(for: viewModel.host, identity: nil)
                } label: {
                    Label("New Tab", systemImage: "plus.rectangle.on.rectangle")
                }
                Button {
                    showingPortForwarding = true
                } label: {
                    Label("Port Forwarding", systemImage: "network")
                }
                Button(role: .destructive) { showingCloseConfirmation = true } label: {
                    Label("Close Session", systemImage: "xmark")
                }
                Divider()
                Button { showingTerminalSettings = true } label: {
                    Label("Terminal Settings", systemImage: "gear")
                }
                Button { showingWorkspaceFavorites = true } label: {
                    Label("Workspace Favorites", systemImage: "star")
                }
            } label: {
                topBarIcon("ellipsis")
            }
            .accessibilityLabel("Session Actions")

            // Command palette button
            Button {
                showingCommandPalette = true
            } label: {
                topBarIcon("command")
            }
            .accessibilityLabel("Command Palette")
            .keyboardShortcut("k", modifiers: [.command])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
        }
    }

    private var statusBadge: some View {
        let color = Theme.Status.color(for: viewModel.status)
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: viewModel.status == .connecting ? 4 : 0)
            Text(statusLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private func topBarButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            topBarIcon(systemImage)
        }
    }

    private func topBarIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(.white.opacity(0.12)))
    }

    @ViewBuilder
    private var sessionSwitcher: some View {
        if sessionStore.sessions.count > 1 {
            Menu("Switch Session") {
                ForEach(sessionStore.sessions) { session in
                    Button {
                        sessionStore.activeSessionID = session.id
                    } label: {
                        Label(session.displayTitle, systemImage: session.id == viewModel.id ? "checkmark" : "terminal")
                    }
                }
            }
            Button { sessionStore.move(viewModel, by: -1) } label: {
                Label("Move Session Left", systemImage: "arrow.left")
            }
            Button { sessionStore.move(viewModel, by: 1) } label: {
                Label("Move Session Right", systemImage: "arrow.right")
            }
            Divider()
            Button {
                sessionStore.openNewTab(for: viewModel.host, identity: nil)
            } label: {
                Label("New Tab for This Host", systemImage: "plus.rectangle.on.rectangle")
            }
        }
    }

    private func applyFontSize() {
        switch terminalFont {
        case "menlo": viewModel.terminalView.font = UIFont(name: "Menlo-Regular", size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        case "courier": viewModel.terminalView.font = UIFont(name: "Courier", size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        default: viewModel.terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    private func applyTerminalTheme() {
        let colors: (foreground: String, background: String, uiBackground: UIColor)
        switch terminalTheme {
        case "solarized": colors = ("#839496", "#002b36", UIColor(red: 0, green: 0.17, blue: 0.21, alpha: 1))
        case "dracula": colors = ("#f8f8f2", "#282a36", UIColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1))
        case "paper": colors = ("#202124", "#f5f5f5", UIColor(white: 0.96, alpha: 1))
        default: colors = ("#f2f2f2", "#000000", .black)
        }
        viewModel.terminalView.backgroundColor = colors.uiBackground
        let sequence = "\u{1B}]10;\(colors.foreground)\u{07}\u{1B}]11;\(colors.background)\u{07}"
        viewModel.terminalView.feed(byteArray: Array(sequence.utf8)[...])
    }

    private func uploadSecurityScopedFiles(_ urls: [URL]) async {
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        await uploadAttachments(urls)
    }

    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        var temporaryURLs: [URL] = []
        do {
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("termvault-\(UUID().uuidString).\(fileExtension)")
                try data.write(to: url, options: .atomic)
                temporaryURLs.append(url)
            }
            await uploadAttachments(temporaryURLs)
        } catch {
            attachmentMessage = error.localizedDescription
        }
        temporaryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        selectedPhotos = []
    }

    private func uploadAttachments(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isUploadingAttachments = true
        defer { isUploadingAttachments = false }
        do {
            let paths = try await viewModel.uploadAttachments(urls)
            viewModel.insertAttachmentReferences(paths)
            attachmentMessage = paths.count == 1
                ? "Uploaded \(urls[0].lastPathComponent) and inserted its remote path."
                : "Uploaded \(paths.count) files and inserted their remote paths."
        } catch {
            attachmentMessage = error.localizedDescription
        }
    }

    private var statusLabel: String {
        switch viewModel.status {
        case .connected:
            if let latency = viewModel.responseLatencyMilliseconds {
                return "Connected · \(latency) ms"
            }
            return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .failed(let message): return message
        }
    }

    private var canReconnect: Bool {
        switch viewModel.status {
        case .disconnected, .failed: return true
        case .connecting, .connected: return false
        }
    }

    private func handleCommandPaletteAction(_ action: CommandAction) {
        switch action {
        case .openHost(let host):
            let _ = sessionStore.open(host: host, identity: nil)
        case .openSnippet(let snippet):
            viewModel.sendRawBytes(Array(snippet.command.utf8))
        case .newTabForHost(let host):
            let _ = sessionStore.openNewTab(for: host, identity: nil)
        case .newSession:
            navigationStore.navigate(to: .hosts)
        case .openSettings:
            navigationStore.navigate(to: .settings)
        case .openKeys:
            navigationStore.navigate(to: .keys)
        }
    }

    private func handleSwipe(_ gesture: DragGesture.Value) {
        let horizontalAmount = gesture.translation.width
        let verticalAmount = gesture.translation.height

        if abs(horizontalAmount) > abs(verticalAmount) {
            if horizontalAmount > 0 {
                // Swipe right: send Ctrl+C (interrupt)
                viewModel.sendControlChord("c")
            } else {
                // Swipe left: send Ctrl+D (exit/EOF)
                viewModel.sendControlChord("d")
            }
        } else {
            if verticalAmount > 0 {
                // Swipe down: scroll to bottom
                viewModel.scrollToLatestOutput()
            } else {
                // Swipe up: scroll to top
                viewModel.scrollPage(-5)
            }
        }
    }
}

private struct TerminalSearchView: View {
    let transcript: String
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var currentIndex = 0

    private var searchResults: [String.SubSequence] {
        guard !searchText.isEmpty else { return [] }
        let lines = transcript.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var resultCount: Int {
        searchResults.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Find text in output", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Search Terminal Output",
                        systemImage: "magnifyingglass",
                        description: Text("Type to find text in the terminal output")
                    )
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No matching lines found")
                    )
                } else {
                    VStack(spacing: 8) {
                        HStack {
                            Text("\(resultCount) result\(resultCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(searchResults.indices, id: \.self) { index in
                                    HighlightedSearchResult(
                                        text: String(searchResults[index]),
                                        searchTerm: searchText
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("Search Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

private struct HighlightedSearchResult: View {
    let text: String
    let searchTerm: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlightedText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(3)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
        }
    }

    private var highlightedText: AttributedString {
        var result = AttributedString(text)
        let searchLower = searchTerm.lowercased()
        let textLower = text.lowercased()

        var searchRange = textLower.startIndex..<textLower.endIndex
        while let range = textLower.range(of: searchTerm, range: searchRange, options: .caseInsensitive) {
            let attributeRange = result.range(of: String(text[range]))
            if let attributeRange = attributeRange {
                result[attributeRange].backgroundColor = .yellow
                result[attributeRange].foregroundColor = .black
            }
            searchRange = range.upperBound..<textLower.endIndex
        }

        return result
    }
}

private struct TerminalTranscriptView: View {
    @ObservedObject var viewModel: TerminalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(filteredTranscript)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .searchable(text: $searchText, prompt: "Find output")
            .navigationTitle("Terminal Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    ShareLink(item: viewModel.plainTextTranscript) { Image(systemName: "square.and.arrow.up") }
                    Button("Clear", role: .destructive) { viewModel.clearTranscript() }
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filteredTranscript: String {
        let transcript = viewModel.plainTextTranscript
        guard !searchText.isEmpty else { return transcript }
        return transcript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .joined(separator: "\n")
    }
}
