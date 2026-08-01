import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SSHConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [Host]
    @State private var importing = false
    @State private var exporting = false
    @State private var document = SSHConfigDocument(text: "")
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Button { importing = true } label: { Label("Import SSH Config", systemImage: "square.and.arrow.down") }
                Button {
                    document = SSHConfigDocument(text: SSHConfigService.export(hosts))
                    exporting = true
                } label: { Label("Export SSH Config", systemImage: "square.and.arrow.up") }
            }
            Section {
                Text("Imports Host, HostName, User, and Port. Credentials remain in the Keychain and are never written to exported config files.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SSH Config")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let entries = SSHConfigService.parse(try String(contentsOf: url, encoding: .utf8))
                var count = 0
                for entry in entries where !hosts.contains(where: { $0.address == entry.hostname && $0.username == entry.user && $0.port == entry.port }) {
                    modelContext.insert(Host(label: entry.alias, address: entry.hostname, port: entry.port, username: entry.user, authMethod: .none))
                    count += 1
                }
                try modelContext.save(); message = "Imported \(count) host(s)."
            } catch { message = error.localizedDescription }
        }
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
