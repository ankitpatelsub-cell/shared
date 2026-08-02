import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SSHConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [Host]
    @State private var showingImport = false
    @State private var exporting = false
    @State private var document = SSHConfigDocument(text: "")
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    SSHConfigImportView()
                } label: {
                    Label("Import SSH Config", systemImage: "square.and.arrow.down")
                }
                
                Button {
                    document = SSHConfigDocument(text: SSHConfigService.export(hosts))
                    exporting = true
                } label: {
                    Label("Export SSH Config", systemImage: "square.and.arrow.up")
                }
            }
            Section {
                Text("Imports Host, HostName, User, Port, IdentityFile, ProxyJump, and more. Credentials remain in the Keychain and are never written to exported config files.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SSH Config")
        .fileExporter(isPresented: $exporting, document: document, contentType: .plainText, defaultFilename: "ssh_config") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .alert("SSH Config", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }
}

private struct SSHConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
