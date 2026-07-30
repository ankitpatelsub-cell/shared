import SwiftUI
import Citadel

struct SFTPBrowserView: View {
    @StateObject private var viewModel: SFTPBrowserViewModel
    @State private var showingImporter = false
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""

    init(host: Host, sshClient: SSHClient) {
        _viewModel = StateObject(wrappedValue: SFTPBrowserViewModel(host: host, sshClient: sshClient))
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            List {
                ForEach(viewModel.entries) { entry in
                    SFTPEntryRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await viewModel.open(entry) }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(entry) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading { ProgressView() }
            }
        }
        .navigationTitle(viewModel.currentPath)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showingImporter = true } label: { Image(systemName: "square.and.arrow.up") }
                Button { showingNewFolderAlert = true } label: { Image(systemName: "folder.badge.plus") }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await viewModel.upload(localURL: url) }
            }
        }
        .alert("New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task {
                    await viewModel.createFolder(named: newFolderName)
                    newFolderName = ""
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let text = viewModel.transferProgressText {
                ProgressBanner(text: text)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
    }

    private var breadcrumbBar: some View {
        HStack {
            Button { Task { await viewModel.goUp() } } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(viewModel.currentPath == "/")
            Text(viewModel.currentPath)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct SFTPEntryRow: View {
    let entry: SFTPEntry

    var body: some View {
        HStack {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
            VStack(alignment: .leading) {
                Text(entry.name)
                Text("\(entry.permissions) · \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct ProgressBanner: View {
    let text: String

    var body: some View {
        HStack {
            ProgressView()
            Text(text)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}
