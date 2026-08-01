import SwiftUI

struct RemoteFileEditorView: View {
    @ObservedObject var browser: SFTPBrowserViewModel
    let entry: SFTPEntry
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var localURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Downloading…")
                } else {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(4)
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isLoading || localURL == nil)
                }
            }
            .task { await load() }
            .alert("File Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func load() async {
        defer { isLoading = false }
        guard entry.size <= 2_000_000 else {
            errorMessage = "Files larger than 2 MB are download-only."
            return
        }
        guard let url = await browser.download(entry) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let value = String(data: data, encoding: .utf8) else {
                errorMessage = "This file is not UTF-8 text."
                return
            }
            localURL = url
            text = value
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() async {
        guard let localURL else { return }
        do {
            try Data(text.utf8).write(to: localURL, options: .atomic)
            await browser.upload(localURL: localURL)
            if browser.errorMessage == nil { dismiss() }
        } catch { errorMessage = error.localizedDescription }
    }
}
