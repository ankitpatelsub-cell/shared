import Foundation
import SwiftTerm
import UIKit

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// A one-shot "sticky" modifier armed by the extra-keys bar's Ctrl/Alt
/// toggle buttons: tap the toggle, then the *next* keystroke typed on the
/// soft keyboard gets transformed, mirroring how Ctrl/Alt keys work in
/// other mobile terminal apps (Termius, Blink) since there's no physical
/// modifier key to hold down.
enum TerminalModifier: Equatable {
    case ctrl
    case alt
}

enum TerminalAttachmentError: Error, LocalizedError {
    case notConnected
    case tooManyFiles(Int)
    case fileTooLarge(String, Int64)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect the terminal before attaching files."
        case .tooManyFiles(let maximum):
            return "Select no more than \(maximum) files at once."
        case .fileTooLarge(let name, let maximumBytes):
            return "\(name) exceeds the \(maximumBytes / 1_048_576) MB attachment limit."
        }
    }
}

/// Bridges one SwiftTerm `TerminalView` to one `SSHSessionManager` session.
/// Keystrokes flow out via `TerminalViewDelegate.send`, remote output flows
/// in via the `onOutput` callback registered at connect time.
@MainActor
final class TerminalViewModel: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let host: Host
    let identity: Identity?
    let jumpHost: Host?
    let jumpIdentity: Identity?
    let terminalView = TerminalView(frame: .zero)
    let persistenceKey: String
    let startedAt = Date()

    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var responseLatencyMilliseconds: Int?
    @Published private(set) var activeWorkspace: WorkspaceSession?
    @Published private(set) var transcript = ""
    @Published var pendingMultilinePaste: [UInt8]?
    @Published var pendingModifier: TerminalModifier?
    @Published var customTitle: String?
    @Published var isPinned = false
    @Published private(set) var isViewingHistory = false
    @Published private(set) var attachmentUploadProgress: String?
    var connectionSnippetCommands: [String] = []

    // SwiftTerm can emit several small delegate callbacks during a fast typing
    // burst. Keep one ordered drain alive instead of creating an unstructured
    // task (and SSH write) for every callback.
    private var pendingInput: [UInt8] = []
    private var inputDrainTask: Task<Void, Never>?
    private var pendingOutput: [UInt8] = []
    private var outputFlushTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var responseStartedAt: Date?
    private var attachedTmuxName: String?
    private var terminalSize: (cols: Int, rows: Int)?

    init(
        host: Host, identity: Identity?, jumpHost: Host? = nil,
        jumpIdentity: Identity? = nil, persistenceKey: String? = nil
    ) {
        self.host = host
        self.identity = identity
        self.jumpHost = jumpHost
        self.jumpIdentity = jumpIdentity
        self.persistenceKey = persistenceKey ?? "host:\(host.id.uuidString)"
        super.init()
        terminalView.terminalDelegate = self
        let configuredSize = UserDefaults.standard.double(forKey: "dev.termvault.settings.fontSize")
        terminalView.font = UIFont.monospacedSystemFont(
            ofSize: configuredSize == 0 ? 14 : configuredSize,
            weight: .regular
        )
    }

    var displayTitle: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        guard let workspace = activeWorkspace else { return host.label }
        return "\(workspace.displayName) · \(workspace.tool.title)"
    }

    func scrollToLatestOutput() {
        let maximumY = max(0, terminalView.contentSize.height - terminalView.bounds.height)
        terminalView.setContentOffset(CGPoint(x: terminalView.contentOffset.x, y: maximumY), animated: true)
        isViewingHistory = false
    }

    func scrollPage(_ direction: Int) {
        let maximumY = max(0, terminalView.contentSize.height - terminalView.bounds.height)
        let page = max(44, terminalView.bounds.height * 0.8)
        let targetY = min(maximumY, max(0, terminalView.contentOffset.y + CGFloat(direction) * page))
        terminalView.setContentOffset(
            CGPoint(x: terminalView.contentOffset.x, y: targetY),
            animated: true
        )
        isViewingHistory = targetY < maximumY - 20
    }

    func connect() async {
        guard status != .connecting, status != .connected else { return }
        status = .connecting
        responseLatencyMilliseconds = nil
        do {
            try await SSHSessionManager.shared.connect(
                connectionID: id,
                host: host,
                identity: identity,
                jumpHost: jumpHost,
                jumpIdentity: jumpIdentity,
                onOutput: { [weak self] data in
                    Task { @MainActor in
                        self?.receiveRemoteOutput(data)
                    }
                },
                onClose: { [weak self] in
                    Task { @MainActor in
                        self?.handleConnectionClosed()
                    }
                }
            )
            status = .connected

            // The first SwiftTerm layout often happens while the SSH PTY is
            // still being created. Re-send the measured viewport after the
            // writer is ready so reconnects and existing tmux sessions also
            // adopt the visible width instead of remaining at 80 columns.
            if let terminalSize {
                try? await SSHSessionManager.shared.resize(
                    connectionID: id,
                    cols: terminalSize.cols,
                    rows: terminalSize.rows
                )
            }

            if let snippet = host.startupSnippet, !snippet.isEmpty {
                try? await send(snippet + "\n")
            }
            for command in connectionSnippetCommands where !command.isEmpty {
                try? await send(command + "\n")
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Restores the logical session, not merely the SSH transport. Workspace
    /// terminals must reattach their tmux session after a dropped connection;
    /// otherwise reconnect leaves the user at the host's home-directory shell.
    func reconnect() async {
        if let workspace = activeWorkspace {
            attachedTmuxName = nil
            await attach(to: workspace)
        } else {
            await connect()
        }
    }

    func send(_ text: String) async throws {
        try await SSHSessionManager.shared.send(text, connectionID: id)
    }

    /// Fire-and-forget path for the extra-keys bar's fixed byte sequences
    /// (Esc, Tab, arrows, Home/End/PgUp/PgDn/Delete) — these are app
    /// -injected control sequences, not characters the user typed, so they
    /// deliberately bypass `pendingModifier` entirely rather than routing
    /// through the `TerminalViewDelegate.send` keystroke path below.
    func sendRawBytes(_ bytes: [UInt8]) {
        enqueueInput(bytes)
    }

    /// Uploads files over the existing SSH connection and returns paths that
    /// the remote AI CLI can read. Files live beside the active workspace
    /// when possible, or in /tmp for a host-only shell session.
    func uploadAttachments(_ urls: [URL]) async throws -> [String] {
        let maximumFiles = 10
        let maximumBytes: Int64 = 50 * 1_048_576
        guard urls.count <= maximumFiles else { throw TerminalAttachmentError.tooManyFiles(maximumFiles) }
        for url in urls {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if Int64(values.fileSize ?? 0) > maximumBytes {
                throw TerminalAttachmentError.fileTooLarge(url.lastPathComponent, maximumBytes)
            }
        }
        guard status == .connected,
              let sshClient = await SSHSessionManager.shared.session(for: id) else {
            throw TerminalAttachmentError.notConnected
        }
        let basePath = activeWorkspace?.path ?? "/tmp"
        let directory = (basePath as NSString).appendingPathComponent(".termvault-attachments")
        _ = try await RemoteCommandService.shared.run(
            hostID: host.id,
            command: "mkdir -p -- \(Self.shellQuote(directory)); find \(Self.shellQuote(directory)) -type f -mtime +7 -delete 2>/dev/null || true"
        )

        var remotePaths: [String] = []
        defer { attachmentUploadProgress = nil }
        for (index, url) in urls.enumerated() {
            attachmentUploadProgress = "Uploading \(index + 1) of \(urls.count): \(url.lastPathComponent)"
            let safeName = Self.safeAttachmentName(url.lastPathComponent)
            let uniqueName = "\(UUID().uuidString.prefix(8))-\(safeName)"
            let remotePath = (directory as NSString).appendingPathComponent(uniqueName)
            try await SFTPService.shared.upload(
                hostID: id,
                sshClient: sshClient,
                localURL: url,
                remotePath: remotePath
            )
            remotePaths.append(remotePath)
        }
        return remotePaths
    }

    func insertAttachmentReferences(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let references = paths.map(Self.shellQuote).joined(separator: " ")
        let insertion: String
        switch activeWorkspace?.tool {
        case .codex:
            insertion = "Inspect and use these local files as context: \(references). "
        case .claude:
            insertion = "Read these files before answering: \(references). "
        case .hermes:
            insertion = "Use the following file context: \(references). "
        case .shell, .none:
            insertion = references + " "
        }
        sendRawBytes(Array(insertion.utf8))
    }

    func attach(to workspace: WorkspaceSession) async {
        if attachedTmuxName == workspace.tmuxName, status == .connected { return }
        activeWorkspace = workspace
        if status == .disconnected || status.isFailure {
            await connect()
        }
        if status == .connecting {
            for _ in 0..<150 where status == .connecting {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard status == .connected else { return }

        if attachedTmuxName != nil {
            // Detach from the current remote tmux client before asking the
            // underlying shell to attach to a different workspace.
            try? await SSHSessionManager.shared.send([0x02, 0x64], connectionID: id) // Ctrl-B, D
            try? await Task.sleep(for: .milliseconds(250))
        }

        let path = Self.shellQuote(workspace.path)
        let name = Self.shellQuote(workspace.tmuxName)
        let tmuxCommand: String
        if let executable = workspace.tool.executable {
            let tool = Self.shellQuote(executable)
            let arguments = (workspace.arguments ?? []).map(Self.shellQuote).joined(separator: " ")
            let environment = (workspace.environment ?? [:])
                .filter { Self.isValidEnvironmentName($0.key) }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(Self.shellQuote($0.value))" }
                .joined(separator: " ")
            let launch = ([environment, tool, arguments].filter { !$0.isEmpty }).joined(separator: " ")
            tmuxCommand = "if ! command -v \(tool) >/dev/null 2>&1; then printf '\\nTermVault: \(executable) is not installed on this host.\\n'; else tmux new-session -A -s \(name) -c \(path) \(Self.shellQuote(launch)); fi"
        } else {
            tmuxCommand = "tmux new-session -A -s \(name) -c \(path)"
        }
        let command = "if ! command -v tmux >/dev/null 2>&1; then printf '\\nTermVault: tmux is required for resumable sessions.\\n'; else \(tmuxCommand); fi\n"
        do {
            try await send(command)
            attachedTmuxName = workspace.tmuxName
            if let prompt = workspace.startupPrompt, !prompt.isEmpty {
                try? await Task.sleep(for: .milliseconds(800))
                try await send(prompt + "\n")
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func safeAttachmentName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let sanitized = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(sanitized)
        return result.isEmpty ? "attachment" : result
    }

    private static func isValidEnvironmentName(_ value: String) -> Bool {
        guard let first = value.utf8.first,
              first == UInt8(ascii: "_") || first >= UInt8(ascii: "A") && first <= UInt8(ascii: "Z") || first >= UInt8(ascii: "a") && first <= UInt8(ascii: "z") else { return false }
        return value.utf8.dropFirst().allSatisfy {
            $0 == UInt8(ascii: "_") || $0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z") || $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z") || $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")
        }
    }

    /// Sends a Ctrl-chord immediately, independent of the toggle in the
    /// extra-keys bar — used by the quick-shortcuts sheet (Ctrl+C, Ctrl+D, …).
    func sendControlChord(_ letter: Character) {
        guard let ascii = letter.asciiValue, let code = Self.controlCode(for: ascii) else { return }
        sendRawBytes([code])
    }

    /// Toggles a one-shot Ctrl/Alt modifier: tapping the active modifier
    /// again clears it; tapping the other one switches to it. Only one
    /// pending modifier at a time, matching a physical sticky-shift key.
    func toggleModifier(_ modifier: TerminalModifier) {
        pendingModifier = (pendingModifier == modifier) ? nil : modifier
    }

    private func applyPendingModifier(to bytes: [UInt8]) -> [UInt8] {
        guard let modifier = pendingModifier else { return bytes }
        pendingModifier = nil // one-shot, consumed regardless of whether it could apply

        switch modifier {
        case .ctrl:
            guard bytes.count == 1, let code = Self.controlCode(for: bytes[0]) else { return bytes }
            return [code]
        case .alt:
            // Standard "Meta sends Escape" encoding most terminals use.
            return [0x1B] + bytes
        }
    }

    /// Maps a byte to its C0 control code the way a real Ctrl key does:
    /// letters fold to 1-26, and a handful of punctuation keys (used for
    /// less common chords like Ctrl+[ == Esc) fold per the standard ASCII
    /// control-code table.
    private static func controlCode(for byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"):
            return byte - UInt8(ascii: "a") + 1
        case UInt8(ascii: "A")...UInt8(ascii: "Z"):
            return byte - UInt8(ascii: "A") + 1
        case UInt8(ascii: "@"), UInt8(ascii: " "):
            return 0x00
        case UInt8(ascii: "["):
            return 0x1B
        case UInt8(ascii: "\\"):
            return 0x1C
        case UInt8(ascii: "]"):
            return 0x1D
        case UInt8(ascii: "^"):
            return 0x1E
        case UInt8(ascii: "_"):
            return 0x1F
        default:
            return nil
        }
    }

    func disconnect() {
        inputDrainTask?.cancel()
        inputDrainTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        pendingInput.removeAll(keepingCapacity: true)
        attachedTmuxName = nil
        let connectionID = id
        Task { await SSHSessionManager.shared.disconnect(connectionID: connectionID) }
        status = .disconnected
    }

    /// Preserve keystroke ordering and coalesce any input that arrives while
    /// the previous network write is in flight.
    private func enqueueInput(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, status == .connected else { return }
        pendingInput.append(contentsOf: bytes)
        guard inputDrainTask == nil else { return }

        inputDrainTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard !self.pendingInput.isEmpty else {
                    self.inputDrainTask = nil
                    return
                }

                let bytes = self.pendingInput
                self.pendingInput.removeAll(keepingCapacity: true)
                do {
                    if self.responseStartedAt == nil {
                        self.responseStartedAt = Date()
                    }
                    try await SSHSessionManager.shared.send(bytes, connectionID: self.id)
                } catch {
                    self.pendingInput.removeAll(keepingCapacity: true)
                    self.inputDrainTask = nil
                    self.status = .disconnected
                    await SSHSessionManager.shared.disconnect(connectionID: self.id)
                    return
                }
            }
        }
    }

    /// Network reads can arrive as many tiny SSH packets. Feed SwiftTerm once
    /// per main-actor turn so output-heavy commands do less layout work and
    /// keyboard handling remains responsive.
    private func receiveRemoteOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        transcript.append(String(decoding: data, as: UTF8.self))
        if transcript.utf8.count > 1_000_000 {
            transcript = String(transcript.suffix(500_000))
        }
        if let startedAt = responseStartedAt {
            responseLatencyMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            responseStartedAt = nil
        }

        pendingOutput.append(contentsOf: data)
        guard outputFlushTask == nil else { return }
        outputFlushTask = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            let bytes = self.pendingOutput
            self.pendingOutput.removeAll(keepingCapacity: true)
            self.outputFlushTask = nil
            guard !bytes.isEmpty else { return }
            self.terminalView.feed(byteArray: bytes[...])
        }
    }

    func clearTranscript() {
        transcript = ""
    }

    var plainTextTranscript: String {
        let pattern = "\u{001B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{0007}]*(?:\u{0007}|\u{001B}\\\\))"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return transcript }
        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        return expression.stringByReplacingMatches(in: transcript, range: range, withTemplate: "")
    }

    func confirmMultilinePaste() {
        guard let bytes = pendingMultilinePaste else { return }
        pendingMultilinePaste = nil
        enqueueInput(bytes)
    }

    private func handleConnectionClosed() {
        let preserveFailure: Bool
        if case .failed = status {
            preserveFailure = true
        } else {
            preserveFailure = false
        }
        inputDrainTask?.cancel()
        inputDrainTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        pendingInput.removeAll(keepingCapacity: true)
        responseStartedAt = nil
        attachedTmuxName = nil
        if !preserveFailure {
            status = .disconnected
        }
    }
}

private extension ConnectionStatus {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension TerminalViewModel: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = applyPendingModifier(to: Array(data))
        if UserDefaults.standard.object(forKey: "dev.termvault.settings.pasteProtection") as? Bool ?? true,
           bytes.count > 1, bytes.contains(0x0A) || bytes.contains(0x0D) {
            pendingMultilinePaste = bytes
            return
        }
        enqueueInput(bytes)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        terminalSize = (newCols, newRows)
        let connectionID = id
        // SwiftUI produces several intermediate heights while the software
        // keyboard animates. Sending every frame to tmux makes it repeatedly
        // reflow its history and visibly pushes the prompt upward. Apply only
        // the settled viewport size.
        resizeTask?.cancel()
        resizeTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            try? await SSHSessionManager.shared.resize(
                connectionID: connectionID,
                cols: newCols,
                rows: newRows
            )
        }
    }

    func scrolled(source: TerminalView, position: Double) {
        let visibleBottom = source.contentOffset.y + source.bounds.height
        isViewingHistory = visibleBottom < source.contentSize.height - 20
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
    }
}
