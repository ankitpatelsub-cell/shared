import Foundation
import SwiftTerm
import UIKit

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// Bridges one SwiftTerm `TerminalView` to one `SSHSessionManager` session.
/// Keystrokes flow out via `TerminalViewDelegate.send`, remote output flows
/// in via the `onOutput` callback registered at connect time.
@MainActor
final class TerminalViewModel: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let host: Host
    let identity: Identity?
    let terminalView = TerminalView()

    @Published private(set) var status: ConnectionStatus = .disconnected

    init(host: Host, identity: Identity?) {
        self.host = host
        self.identity = identity
        super.init()
        terminalView.terminalDelegate = self
    }

    func connect() async {
        status = .connecting
        do {
            _ = try await SSHSessionManager.shared.connect(
                host: host,
                identity: identity,
                onOutput: { [weak self] data in
                    Task { @MainActor in
                        self?.terminalView.feed(byteArray: Array(data))
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

    func disconnect() {
        let hostID = host.id
        Task { await SSHSessionManager.shared.disconnect(hostID: hostID) }
        status = .disconnected
    }
}

extension TerminalViewModel: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let text = String(decoding: data, as: UTF8.self)
        Task { try? await send(text) }
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func setTerminalIconTitle(source: TerminalView, title: String) {}
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
