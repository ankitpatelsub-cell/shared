import Foundation
import SwiftTerm
import UIKit
import UniformTypeIdentifiers

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

/// OSC (Operating System Command) sequences for terminal integration
enum OSCSequence {
    /// OSC 52 - Clipboard operations
    /// Format: ESC ] 52 ; <base64> ; <data> BEL/ST
    static func clipboardSet(base64Data: String) -> String {
        "\u{1B}]52;c;\(base64Data)\u{07}"
    }
    
    /// OSC 8 - Hyperlinks
    /// Format: ESC ] 8 ; id=<id> ; <url> ST ... ESC ] 8 ; ; ST
    static func hyperlinkStart(url: String, id: String? = nil) -> String {
        if let id {
            return "\u{1B}]8;id=\(id);\(url)\u{1B}\\"
        }
        return "\u{1B}]8;;\(url)\u{1B}\\"
    }
    
    static func hyperlinkEnd() -> String {
        "\u{1B}]8;;\u{1B}\\"
    }
    
    /// Parse OSC 52 from incoming data
    static func parseClipboard(from data: Data) -> String? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        // Look for OSC 52 sequences: ESC ] 52 ; c ; <base64> BEL/ST
        let pattern = #"\u{1B}\](?:52);[^;]*;([^\u{07}\u{1B}]+)(?:\u{07}|\u{1B}\\\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let range1 = Range(match.range(at: 1), in: string) else { return nil }
        let base64 = String(string[range1])
        guard let decoded = Data(base64Encoded: base64),
              let text = String(data: decoded, encoding: .utf8) else { return nil }
        return text
    }
    
    /// Parse OSC 8 hyperlinks from incoming data
    static func parseHyperlinks(from data: Data) -> [(url: String, id: String?, range: NSRange)] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        // Look for OSC 8 sequences: ESC ] 8 ; [id=xxx;] url ST ... ESC ] 8 ; ; ST
        let pattern = #"\u{1B}\]8;(?:id=([^;]+);)?([^\u{1B}]+)\u{1B}\\[^\u{1B}]*\u{1B}\]8;;\u{1B}\\"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            let id = match.range(at: 1).location != NSNotFound ? Range(match.range(at: 1), in: string).map { String(string[$0]) } : nil
            guard let urlRange = Range(match.range(at: 2), in: string) else { return nil }
            return (url: String(string[urlRange]), id: id, range: match.range)
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
    let jumpHosts: [SSHJumpHop] // Support multiple jump hosts
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
    @Published private(set) var scrollPosition: Double = 1.0
    @Published private(set) var autoReconnectStatus: String?
    @Published private(set) var sessionDataTransferred: Int64 = 0
    @Published private(set) var sessionCommandCount: Int = 0
        @Published private(set) var attachmentUploadProgress: String?
        var connectionSnippetCommands: [String] = []

        private var reconnectAttempt = 0
        private let maxReconnectAttempts = 5
        private var reconnectTask: Task<Void, Never>? = nil
        private var latencyHistory: [Int] = []
    
        // Per-host terminal settings
        @Published var terminalFontSize: Double = 14
        @Published var terminalFontName: String = "system"
        @Published var terminalThemeName: String = "midnight"
        @Published var bellEnabled: Bool = true
        @Published var cursorBlink: Bool = true
    
        // OSC 52 clipboard
        @Published private(set) var remoteClipboard: String?
        // OSC 8 hyperlinks
        @Published private(set) var detectedHyperlinks: [(url: String, id: String?)] = []

        // SwiftTerm can emit several small delegate callbacks during a fast typing
            // burst. Keep one ordered drain alive instead of creating an unstructured
            // task (and SSH write) for every callback.
            private var pendingInput: [UInt8] = []
            private var inputDrainTask: Task<Void, Never>? = nil
            private var pendingOutput: [UInt8] = []
            private var outputFlushTask: Task<Void, Never>? = nil
            private var resizeTask: Task<Void, Never>? = nil
            private var responseStartedAt: Date? = nil
            private var attachedTmuxName: String? = nil
            private var terminalSize: (cols: Int, rows: Int)? = nil

            // Transcript persistence - save periodically to survive crashes
            private var transcriptSaveTask: Task<Void, Never>? = nil
            private let transcriptSaveInterval: TimeInterval = 30 // seconds
            private let maxTranscriptSize = 5_000_000 // 5M chars (increased from 2M)
            private let transcriptTrimSize = 2_500_000 // trim to 2.5M (increased from 1M)

            init(
                host: Host, identity: Identity?, jumpHosts: [SSHJumpHop] = [],
                persistenceKey: String? = nil
            ) {
                self.host = host
                self.identity = identity
                self.jumpHosts = jumpHosts
                self.persistenceKey = persistenceKey ?? "host:\(host.id.uuidString)"
                super.init()
                terminalView.terminalDelegate = self
                loadTerminalSettings()
                applyTerminalSettings()
                loadPersistedTranscript()
                startTranscriptAutoSave()
            }
    
    // MARK: - Per-Host Terminal Settings
    
    private func settingsKey(_ key: String) -> String {
        "dev.termvault.terminal.\(host.id.uuidString).\(key)"
    }
    
    private func loadTerminalSettings() {
        terminalFontSize = UserDefaults.standard.double(forKey: settingsKey("fontSize"))
        if terminalFontSize == 0 { terminalFontSize = 14 }
        
        terminalFontName = UserDefaults.standard.string(forKey: settingsKey("fontName")) ?? "system"
        terminalThemeName = UserDefaults.standard.string(forKey: settingsKey("themeName")) ?? "midnight"
        bellEnabled = UserDefaults.standard.bool(forKey: settingsKey("bellEnabled"))
        cursorBlink = UserDefaults.standard.bool(forKey: settingsKey("cursorBlink"))
        if !UserDefaults.standard.bool(forKey: settingsKey("cursorBlinkSet")) {
            cursorBlink = true // default
        }
    }
    
    private func saveTerminalSettings() {
        UserDefaults.standard.set(terminalFontSize, forKey: settingsKey("fontSize"))
        UserDefaults.standard.set(terminalFontName, forKey: settingsKey("fontName"))
        UserDefaults.standard.set(terminalThemeName, forKey: settingsKey("themeName"))
        UserDefaults.standard.set(bellEnabled, forKey: settingsKey("bellEnabled"))
        UserDefaults.standard.set(cursorBlink, forKey: settingsKey("cursorBlink"))
        UserDefaults.standard.set(true, forKey: settingsKey("cursorBlinkSet"))
    }
    
    func applyTerminalSettings() {
        let font: UIFont
        if terminalFontName == "system" {
            font = UIFont.monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
        } else if let customFont = UIFont(name: terminalFontName, size: terminalFontSize) {
            font = customFont
        } else {
            font = UIFont.monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
        }
        terminalView.font = font
        // terminalView.cursorBlink = cursorBlink  // Not available in SwiftTerm
        // Theme colors would be applied here based on terminalThemeName
        applyTerminalTheme()
        saveTerminalSettings()
    }
    
    func updateFontSize(_ size: Double) {
        terminalFontSize = max(10, min(24, size))
        applyTerminalSettings()
    }
    
    func updateFontName(_ name: String) {
        terminalFontName = name
        applyTerminalSettings()
    }
    
    func updateThemeName(_ name: String) {
        terminalThemeName = name
        applyTerminalSettings()
    }
    
    func toggleBell() {
        bellEnabled.toggle()
        applyTerminalSettings()
    }
    
    func toggleCursorBlink() {
        cursorBlink.toggle()
        applyTerminalSettings()
    }
    
    private func applyTerminalTheme() {
        // Apply color theme based on terminalThemeName
        // This would set foreground, background, cursor, selection colors
        // For now, we'll use the global theme from AppStorage
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
                jumpHosts: jumpHosts,
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
            reconnectAttempt = 0
            autoReconnectStatus = nil

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
        if text.hasSuffix("\n") {
            CommandHistoryStore.shared.record(text, hostID: host.id)
            sessionCommandCount += 1
        }
    }

    var averageLatency: Int {
        guard !latencyHistory.isEmpty else { return 0 }
        let sum = latencyHistory.reduce(0, +)
        return sum / latencyHistory.count
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
        reconnectTask?.cancel()
        reconnectTask = nil
        pendingInput.removeAll(keepingCapacity: true)
        attachedTmuxName = nil

        // Record session history on explicit disconnect
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { @MainActor in
                SessionHistoryStore.shared.record(self)
            }
        }

        stopTranscriptAutoSave()

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

        sessionDataTransferred += Int64(data.count)

        // Parse OSC 52 clipboard from remote
        if let clipboardText = OSCSequence.parseClipboard(from: data) {
            remoteClipboard = clipboardText
            UIPasteboard.general.string = clipboardText
        }

        // Parse OSC 8 hyperlinks from remote
        let hyperlinks = OSCSequence.parseHyperlinks(from: data)
        if !hyperlinks.isEmpty {
            detectedHyperlinks = hyperlinks.map { (url: $0.url, id: $0.id) }
        }

        transcript.append(String(decoding: data, as: UTF8.self))
        // Trim transcript if it exceeds max size
        if transcript.utf8.count > maxTranscriptSize {
            transcript = String(transcript.suffix(transcriptTrimSize))
        }
        if let startedAt = responseStartedAt {
            let latency = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            responseLatencyMilliseconds = latency
            latencyHistory.append(latency)
            if latencyHistory.count > 100 {
                latencyHistory.removeFirst()
            }
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
    
    // MARK: - OSC 52 Clipboard
    
    /// Send local clipboard to remote via OSC 52
    func syncClipboardToRemote() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        let base64 = Data(text.utf8).base64EncodedString()
        let osc52 = OSCSequence.clipboardSet(base64Data: base64)
        sendRawBytes(Array(osc52.utf8))
    }
    
    /// Request remote clipboard (some terminals support this)
    func requestRemoteClipboard() {
        // OSC 52 query: ESC ] 52 ; c ; ? BEL
        let query = "\u{1B}]52;c;?\u{07}"
        sendRawBytes(Array(query.utf8))
    }
    
    // MARK: - OSC 8 Hyperlinks
    
    /// Handle hyperlink tap - open URL or handle file paths
    func handleHyperlinkTap(_ url: String) {
        if url.hasPrefix("file://") {
            // Handle local file paths - could open in SFTP browser
            let path = String(url.dropFirst("file://".count))
            // Navigate to path in SFTP browser if available
        } else if url.hasPrefix("http://") || url.hasPrefix("https://") {
            // Open in Safari
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        } else if url.hasPrefix("ssh://") {
            // Handle SSH links - could parse and connect
        }
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
    
    // MARK: - Transcript Persistence
    
    private func transcriptFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermVault", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(persistenceKey).transcript")
    }
    
    private func loadPersistedTranscript() {
        let url = transcriptFileURL()
        if let data = try? Data(contentsOf: url),
           let saved = String(data: data, encoding: .utf8) {
            transcript = saved
        }
    }
    
    private func savePersistedTranscript() {
        let url = transcriptFileURL()
        try? transcript.data(using: .utf8)?.write(to: url, options: .atomic)
    }
    
    private func startTranscriptAutoSave() {
        transcriptSaveTask?.cancel()
        transcriptSaveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.transcriptSaveInterval))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.savePersistedTranscript()
                }
            }
        }
    }
    
    private func stopTranscriptAutoSave() {
        transcriptSaveTask?.cancel()
        transcriptSaveTask = nil
        savePersistedTranscript() // Final save
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

        // Record session history on disconnect (not just explicit close)
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { @MainActor in
                SessionHistoryStore.shared.record(self)
            }
        }

        stopTranscriptAutoSave()

        if !preserveFailure {
            status = .disconnected
            attemptAutoReconnect()
        }
    }

    private func attemptAutoReconnect() {
        reconnectTask?.cancel()
        guard reconnectAttempt < maxReconnectAttempts else {
            autoReconnectStatus = nil
            return
        }

        reconnectAttempt += 1
        let delaySeconds = min(30, pow(2.0, Double(reconnectAttempt - 1)))

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            self.autoReconnectStatus = "Reconnecting in \(Int(delaySeconds))s… (attempt \(self.reconnectAttempt)/\(self.maxReconnectAttempts))"
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.autoReconnectStatus = "Reconnecting… (attempt \(self.reconnectAttempt)/\(self.maxReconnectAttempts))"
            }
            await self.reconnect()
        }
    }

    func cancelAutoReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        autoReconnectStatus = nil
    }
}

private extension ConnectionStatus {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
extension TerminalViewModel: @preconcurrency TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = applyPendingModifier(to: Array(data))
        let pasteProtectionEnabled = UserDefaults.standard.object(forKey: "dev.termvault.settings.pasteProtection") as? Bool ?? true
        let isMultilinePaste = bytes.count > 1 && (bytes.contains(0x0A) || bytes.contains(0x0D))

        if pasteProtectionEnabled && isMultilinePaste {
            if AutoApproveSettings.shared.autoApproveMultilinePaste {
                enqueueInput(bytes)
            } else {
                pendingMultilinePaste = bytes
            }
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

        let totalHeight = max(source.contentSize.height - source.bounds.height, 1)
        scrollPosition = max(0, min(1, source.contentOffset.y / totalHeight))
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
    }
}
