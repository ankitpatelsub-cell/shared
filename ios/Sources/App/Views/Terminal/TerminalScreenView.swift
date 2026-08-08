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
    @State private var showingTranscript = false
    @State private var showingCloseConfirmation = false
    @State private var showingRename = false
    @State private var showingCommandPalette = false
    @State private var showingPortForwarding = false
    @State private var renameText = ""
    @State private var fontSizeAtGestureStart: Double?
    @State private var scrollRepeatTask: Task<Void, Never>?
    @State private var showingFileImporter = false
    @State private var showingPhotosPicker = false
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

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .trailing) {
                TerminalRepresentable(terminalView: viewModel.terminalView)
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
                    .modifier(GestureModifier(gesturesEnabled: gesturesEnabled, onSwipe: handleSwipe))

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
                scrollControlsOverlay
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
                autoReconnectOverlay
            }
        }
    }

    @ViewBuilder
    private var scrollControlsOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.caption.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ultraThinMaterial))
                .contentShape(Circle())
                .accessibilityLabel("Scroll up")
                .accessibilityAddTraits(.isButton)
                .pressAndHoldToRepeat { startRepeatingScroll(direction: -1) } onRelease: {
                    stopRepeatingScroll()
                }
            Button { viewModel.scrollToLatestOutput() } label: {
                VStack(spacing: 2) {
                    Label("Latest", systemImage: "arrow.down.to.line")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Image(systemName: "arrow.down")
                .font(.caption.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ultraThinMaterial))
                .contentShape(Circle())
                .accessibilityLabel("Scroll down")
                .accessibilityAddTraits(.isButton)
                .pressAndHoldToRepeat { startRepeatingScroll(direction: 1) } onRelease: {
                    stopRepeatingScroll()
                }
        }
        .padding(.trailing, 12)
        .padding(.bottom, 56)
        .transition(.scale.combined(with: .opacity))
    }

    // Standard "press and hold to repeat" behavior (as used for stepper/scrub
    // controls system-wide): the first scroll happens immediately on touch-down
    // so a quick tap still behaves like the old single-tap button, then after a
    // short delay it keeps scrolling every 120ms until the finger lifts.
    private func startRepeatingScroll(direction: Int) {
        guard scrollRepeatTask == nil else { return }
        viewModel.scrollPage(direction)
        scrollRepeatTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                viewModel.scrollPage(direction)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopRepeatingScroll() {
        scrollRepeatTask?.cancel()
        scrollRepeatTask = nil
    }

    // Pulled out of the `.task` closure inline: the Swift 6 type checker
    // was timing out trying to infer the combined async/boolean expression
    // in place ("unable to type-check this expression in reasonable time").
    private func handleAppear() async {
        applyFontSize()
        applyTerminalTheme()
        // `.failed` (e.g. auto-reconnect gave up after its 5 attempts while
        // the app sat backgrounded) was previously excluded here, so
        // reopening a long-stale session did nothing until the user found
        // the manual "Reconnect" menu item.
        if viewModel.status == .disconnected || viewModel.status.isFailure {
            await viewModel.reconnect()
        }
    }

    // Routes through SessionStore.openSFTP — the same tracked path
    // WorkspaceBrowserTabView uses — instead of the old SFTPGateView sheet,
    // which built its own untracked SFTPBrowserViewModel. That divergence
    // meant pinned folders, in-flight transfers, and the current path all
    // reset every time the sheet was dismissed and reopened, and it never
    // got the "launch Codex/Claude here" buttons the tracked path has.
    private func browseFiles() {
        let key = "sftp:\(viewModel.id.uuidString)"
        if let existing = sessionStore.sessions.first(where: { $0.sftp?.persistenceKey == key }) {
            sessionStore.activeSessionID = existing.id
            return
        }
        Task {
            for _ in 0..<50 {
                if let sshClient = await SSHSessionManager.shared.session(for: viewModel.id) {
                    sessionStore.openSFTP(host: viewModel.host, connectionID: viewModel.id, sshClient: sshClient)
                    return
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    @ViewBuilder
    private var autoReconnectOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8, anchor: .center)
            Text(viewModel.autoReconnectStatus ?? "")
                .font(.caption.weight(.semibold))
            Spacer()
            Button { viewModel.cancelAutoReconnect() } label: {
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

    var body: some View {
        mainContent
            .background(Color.black)
        .toolbar(.hidden, for: .tabBar)
        .task { await handleAppear() }
        .onDisappear { stopRepeatingScroll() }
        .onChange(of: fontSize) { _, _ in applyFontSize() }
        .onChange(of: terminalFont) { _, _ in applyFontSize() }
        .onChange(of: terminalTheme) { _, _ in applyTerminalTheme() }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await uploadPhotos(items) }
        }
        // A `PhotosPicker` placed directly inside a `Menu` (as this was)
        // doesn't reliably present on iOS — the menu swallows the tap
        // before the picker's own presentation can run. Trigger it instead
        // via a plain Button inside the menu setting `showingPhotosPicker`,
        // with the actual picker attached out here, same pattern as the
        // file importer below.
        .photosPicker(isPresented: $showingPhotosPicker, selection: $selectedPhotos, maxSelectionCount: 5, matching: .images)
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

            topBarButton("folder") { browseFiles() }
                .accessibilityLabel("Browse remote files")
            agentModeMenu

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
                Button { showingPhotosPicker = true } label: {
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

    /// One-tap access to the mode/approval switches Claude Code and Codex
    /// expose inside their own REPL — otherwise reaching them means typing
    /// the slash command or hunting for the Shift+Tab chord on a soft
    /// keyboard. Only shown for sessions actually running one of those
    /// tools; hidden for plain shell/Hermes sessions where it's meaningless.
    @ViewBuilder
    private var agentModeMenu: some View {
        switch viewModel.activeWorkspace?.tool {
        case .claude:
            Menu {
                Button {
                    // Shift+Tab: Claude Code's own chord for cycling
                    // default → auto-accept edits → plan mode.
                    viewModel.sendRawBytes(Array("\u{1B}[Z".utf8))
                } label: {
                    Label("Cycle Permission Mode (Shift+Tab)", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    viewModel.sendRawBytes(Array("/model".utf8))
                } label: {
                    Label("Switch Model (/model)", systemImage: "cpu")
                }
            } label: {
                topBarIcon("sparkles")
            }
            .accessibilityLabel("Claude Mode")
        case .codex:
            Menu {
                Button {
                    viewModel.sendRawBytes(Array("/approvals".utf8))
                } label: {
                    Label("Change Approval Mode (/approvals)", systemImage: "checkmark.shield")
                }
                Button {
                    viewModel.sendRawBytes(Array("/model".utf8))
                } label: {
                    Label("Switch Model (/model)", systemImage: "cpu")
                }
            } label: {
                topBarIcon("chevron.left.forwardslash.chevron.right")
            }
            .accessibilityLabel("Codex Mode")
        default:
            EmptyView()
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
        if sessionStore.terminalSessions.count > 1 {
            Menu("Switch Session") {
                ForEach(sessionStore.terminalSessions) { session in
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

extension View {
    /// Fires `onPress` the instant the finger goes down and `onRelease` when it
    /// lifts (or the touch is cancelled) — `DragGesture(minimumDistance: 0)` is
    /// the standard SwiftUI way to get press/release edges on a plain view
    /// without a `Button` fighting a second gesture recognizer for the touch.
    func pressAndHoldToRepeat(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

private struct GestureModifier: ViewModifier {
    let gesturesEnabled: Bool
    let onSwipe: (DragGesture.Value) -> Void

    func body(content: Content) -> some View {
        if gesturesEnabled {
            content.gesture(DragGesture(minimumDistance: 50).onEnded(onSwipe))
        } else {
            content
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
        while let range = textLower.range(of: searchTerm, options: .caseInsensitive, range: searchRange) {
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
