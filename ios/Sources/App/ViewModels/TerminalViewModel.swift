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
    @Published var pendingModifier: TerminalModifier?

    // SwiftTerm can emit several small delegate callbacks during a fast typing
    // burst. Keep one ordered drain alive instead of creating an unstructured
    // task (and SSH write) for every callback.
    private var pendingInput: [UInt8] = []
    private var inputDrainTask: Task<Void, Never>?
    private var pendingOutput: [UInt8] = []
    private var outputFlushTask: Task<Void, Never>?
    private var responseStartedAt: Date?

    init(host: Host, identity: Identity?) {
        self.host = host
        self.identity = identity
        super.init()
        terminalView.terminalDelegate = self
    }

    func connect() async {
        guard status != .connecting, status != .connected else { return }
        status = .connecting
        responseLatencyMilliseconds = nil
        do {
            try await SSHSessionManager.shared.connect(
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
        try await SSHSessionManager.shared.send(text, hostID: host.id)
    }

    /// Fire-and-forget path for the extra-keys bar's fixed byte sequences
    /// (Esc, Tab, arrows, Home/End/PgUp/PgDn/Delete) — these are app
    /// -injected control sequences, not characters the user typed, so they
    /// deliberately bypass `pendingModifier` entirely rather than routing
    /// through the `TerminalViewDelegate.send` keystroke path below.
    func sendRawBytes(_ bytes: [UInt8]) {
        enqueueInput(bytes)
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
        let hostID = host.id
        Task { await SSHSessionManager.shared.disconnect(hostID: hostID) }
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
                    try await SSHSessionManager.shared.send(bytes, hostID: self.host.id)
                } catch {
                    self.pendingInput.removeAll(keepingCapacity: true)
                    self.inputDrainTask = nil
                    self.status = .disconnected
                    await SSHSessionManager.shared.disconnect(hostID: self.host.id)
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
        if !preserveFailure {
            status = .disconnected
        }
    }
}

extension TerminalViewModel: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = applyPendingModifier(to: Array(data))
        enqueueInput(bytes)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let hostID = host.id
        Task { try? await SSHSessionManager.shared.resize(hostID: hostID, cols: newCols, rows: newRows) }
    }

    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
    }
}
