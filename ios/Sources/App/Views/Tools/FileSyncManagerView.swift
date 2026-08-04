import SwiftUI

struct FileSyncManagerView: View {
    @ObservedObject private var syncService = FileSyncService.shared
    @State private var showingNewSync = false
    @State private var selectedRecord: FileSyncRecord?

    var body: some View {
        NavigationStack {
            if syncService.syncRecords.isEmpty {
                ContentUnavailableView(
                    "No Sync Configurations",
                    systemImage: "arrow.left.arrow.right.circle",
                    description: Text("Add a file sync configuration to sync files between your machine and hosts")
                )
                .navigationTitle("File Sync")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingNewSync = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            } else {
                List(syncService.syncRecords) { record in
                    NavigationLink(destination: FileSyncDetailView(record: record)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .center, spacing: 4) {
                                Image(systemName: record.direction == .bidirectional ? "arrow.left.arrow.right" : "arrow.right")
                                    .foregroundStyle(.blue)
                                    .font(.headline)

                                if let lastSynced = record.lastSyncedAt {
                                    Text(lastSynced, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Never")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.localPath.components(separatedBy: "/").last ?? record.localPath)
                                    .fontWeight(.semibold)

                                HStack(spacing: 8) {
                                    Text(record.displayDirection)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if record.autoSync {
                                        Label("Auto", systemImage: "arrow.clockwise.circle")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }

                                Text(record.remotePath)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task {
                                await syncService.syncNow(record)
                            }
                        } label: {
                            Label("Sync", systemImage: "arrow.clockwise")
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            syncService.removeSyncRecord(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle("File Sync")
                .overlay(alignment: .top) {
                    if let status = syncService.syncStatus {
                        HStack(spacing: 8) {
                            if syncService.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8, anchor: .center)
                            }

                            Text(status)
                                .font(.caption.weight(.semibold))

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(8)
                        .padding(12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task {
                                await syncService.syncAll()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingNewSync = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewSync) {
            NewFileSyncView(isPresented: $showingNewSync)
        }
    }
}

struct FileSyncDetailView: View {
    @ObservedObject private var syncService = FileSyncService.shared
    @State var record: FileSyncRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Paths") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "macbook")
                            .foregroundStyle(.blue)
                        Text("Local")
                            .fontWeight(.semibold)
                    }
                    Text(record.localPath)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.blue)
                        Text("Remote")
                            .fontWeight(.semibold)
                    }
                    Text(record.remotePath)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }
            }

            Section("Configuration") {
                HStack {
                    Text("Direction")
                    Spacer()
                    Text(record.displayDirection)
                        .foregroundStyle(.secondary)
                }

                Toggle("Auto Sync", isOn: .constant(record.autoSync))
                    .disabled(true)

                if !record.ignorePatterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ignore Patterns")
                        ForEach(record.ignorePatterns, id: \.self) { pattern in
                            Text(pattern)
                                .font(.caption)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            Section("Last Sync") {
                if let lastSynced = record.lastSyncedAt {
                    HStack {
                        Text("Synced")
                        Spacer()
                        Text(lastSynced, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Never synced")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    syncService.removeSyncRecord(record)
                    dismiss()
                } label: {
                    Label("Remove Sync Configuration", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Sync Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewFileSyncView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var syncService = FileSyncService.shared
    @State private var localPath = ""
    @State private var remotePath = ""
    @State private var direction: FileSyncRecord.SyncDirection = .bidirectional
    @State private var autoSync = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Paths") {
                    HStack {
                        Image(systemName: "macbook")
                            .foregroundStyle(.blue)
                        TextField("Local Path", text: $localPath)
                    }

                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.blue)
                        TextField("Remote Path", text: $remotePath)
                    }
                }

                Section("Configuration") {
                    Picker("Sync Direction", selection: $direction) {
                        Text("Local → Remote").tag(FileSyncRecord.SyncDirection.localToRemote)
                        Text("Remote → Local").tag(FileSyncRecord.SyncDirection.remoteToLocal)
                        Text("Bidirectional").tag(FileSyncRecord.SyncDirection.bidirectional)
                    }

                    Toggle("Auto Sync", isOn: $autoSync)
                        .help("Automatically sync when files change")
                }
            }
            .navigationTitle("New File Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        syncService.addSyncRecord(
                            hostID: UUID(), // This would be passed as parameter
                            localPath: localPath,
                            remotePath: remotePath,
                            direction: direction,
                            autoSync: autoSync
                        )
                        isPresented = false
                    }
                    .disabled(localPath.isEmpty || remotePath.isEmpty)
                }
            }
        }
    }
}

#Preview {
    FileSyncManagerView()
}
