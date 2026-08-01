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

/// Bridges one SwiftTerm `TerminalView` to one `SSHSessionManager` session.
/// Keystrokes flow out via `TerminalViewDelegate.send`, remote output flows
/// in via the `onOutput` callback registered at connect time.
@MainActor
final class TerminalViewModel: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let host: Host
    let identity: Identity?
    let terminalView = TerminalView(frame: .zero)

    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var responseLatencyMilliseconds: Int?
    @Published private(set) var activeWorkspace: WorkspaceSession?
    @Published private(set) var transcript = ""
    @Published var pendingMultilinePaste: [UInt8]?
    @Published var pendingModifier: TerminalModifier?

    // SwiftTerm can emit several small delegate callbacks during a fast typing
    // burst. Keep one ordered drain alive instead of creating an unstructured
    // task (and SSH write) for every callback.
    private var pendingInput: [UInt8] = []
    private var inputDrainTask: Task<Void, Never>?
    private var pendingOutput: [UInt8] = []
    private var outputFlushTask: Task<Void, Never>?
    private var responseStartedAt: Date?
    private var attachedTmuxName: String?

    init(host: Host, identity: Identity?) {
        self.host = host
        self.identity = identity
        super.init()
        terminalView.terminalDelegate = self
        let configuredSize = UserDefaults.standard.double(forKey: "dev.termvault.settings.fontSize")
        terminalView.font = UIFont.monospacedSystemFont(
            ofSize: configuredSize == 0 ? 14 : configuredSize,
            weight: .regular
        )
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

            if let snippet = host.startupSnippet, !snippet.isEmpty {
                try? await send(snippet + "\n")
            }
        } catch {
            status = .failed(error.localizedDescription)
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
        let connectionID = id
        Task { try? await SSHSessionManager.shared.resize(connectionID: connectionID, cols: newCols, rows: newRows) }
    }

    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
    }
}
