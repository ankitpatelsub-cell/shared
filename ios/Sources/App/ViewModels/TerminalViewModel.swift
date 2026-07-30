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
    @Published var pendingModifier: TerminalModifier?

    init(host: Host, identity: Identity?) {
        self.host = host
        self.identity = identity
        super.init()
        terminalView.terminalDelegate = self
    }

    func connect() async {
        status = .connecting
        do {
            try await SSHSessionManager.shared.connect(
                host: host,
                identity: identity,
                onOutput: { [weak self] data in
                    Task { @MainActor in
                        self?.terminalView.feed(byteArray: Array(data)[...])
                    }
                },
                onClose: { [weak self] in
                    Task { @MainActor in
                        self?.status = .disconnected
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
        let text = String(decoding: bytes, as: UTF8.self)
        Task { try? await send(text) }
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
        let hostID = host.id
        Task { await SSHSessionManager.shared.disconnect(hostID: hostID) }
        status = .disconnected
    }
}

extension TerminalViewModel: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = applyPendingModifier(to: Array(data))
        let text = String(decoding: bytes, as: UTF8.self)
        Task { try? await send(text) }
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
