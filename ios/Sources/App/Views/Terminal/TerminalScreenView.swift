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
    @State private var renameText = ""
    @State private var fontSizeAtGestureStart: Double?
    @State private var showingFileImporter = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isUploadingAttachments = false
    @State private var attachmentMessage: String?
    @AppStorage("dev.termvault.settings.fontSize") private var fontSize: Double = 14

    var body: some View {
        VStack(spacing: 0) {
            topBar
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExtraKeysAccessoryView(viewModel: viewModel)
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isViewingHistory {
                Button {
                    viewModel.scrollToLatestOutput()
                } label: {
                    Label("Latest", systemImage: "arrow.down.to.line")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
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
        .background(Color.black)
        .toolbar(.hidden, for: .tabBar)
        .task {
            applyFontSize()
            if viewModel.status == .disconnected {
                await viewModel.reconnect()
            }
        }
        .onChange(of: fontSize) { _, _ in applyFontSize() }
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
                statusBadge
            }

            Spacer(minLength: 4)

            topBarButton("folder") { showingSFTP = true }
                .accessibilityLabel("Browse remote files")
            Menu {
                sessionSwitcher
                Divider()
                Button { showingTranscript = true } label: {
                    Label("Search Output", systemImage: "doc.text.magnifyingglass")
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
                Button(role: .destructive) { showingCloseConfirmation = true } label: {
                    Label("Close Session", systemImage: "xmark")
                }
            } label: {
                topBarIcon("ellipsis")
            }
            .accessibilityLabel("Session Actions")
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
        }
    }

    private func applyFontSize() {
        viewModel.terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
