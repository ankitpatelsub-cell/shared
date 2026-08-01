import SwiftUI

struct RemoteFileOperationsView: View {
    private enum PendingOperation { case copy, move, chmod }
    @ObservedObject var browser: SFTPBrowserViewModel
    let entry: SFTPEntry
    @Environment(\.dismiss) private var dismiss
    @State private var destination: String
    @State private var mode = "644"
    @State private var pendingOperation: PendingOperation?

    init(browser: SFTPBrowserViewModel, entry: SFTPEntry) {
        self.browser = browser
        self.entry = entry
        _destination = State(initialValue: entry.path)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Copy or Move") {
                    TextField("Destination path", text: $destination)
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Copy") { pendingOperation = .copy }
                    Button("Move") { pendingOperation = .move }
                }
                Section("Permissions") {
                    TextField("Octal mode", text: $mode)
                        .keyboardType(.numberPad)
                    Button("Apply chmod") { pendingOperation = .chmod }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Confirm Remote Change", isPresented: Binding(
                get: { pendingOperation != nil },
                set: { if !$0 { pendingOperation = nil } }
            ), titleVisibility: .visible) {
                Button(operationLabel, role: operationRole) {
                    let operation = pendingOperation
                    pendingOperation = nil
                    Task {
                        switch operation {
                        case .copy: await browser.copy(entry, to: destination)
                        case .move: await browser.move(entry, to: destination)
                        case .chmod: await browser.changePermissions(entry, mode: mode)
                        case nil: return
                        }
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { pendingOperation = nil }
            } message: {
                Text(operationDescription)
            }
        }
    }

    private var operationLabel: String {
        switch pendingOperation {
        case .copy: return "Copy"
        case .move: return "Move"
        case .chmod: return "Change Permissions"
        case nil: return "Continue"
        }
    }

    private var operationRole: ButtonRole? {
        if case .copy = pendingOperation { return nil }
        return .destructive
    }

    private var operationDescription: String {
        switch pendingOperation {
        case .copy, .move: return "Destination: \(destination)"
        case .chmod: return "Apply mode \(mode) to \(entry.name)?"
        case nil: return ""
        }
    }
}
