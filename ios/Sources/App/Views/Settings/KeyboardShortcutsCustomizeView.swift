import SwiftUI

/// Lets the user pick exactly which keys show in the extra-keys row above
/// the keyboard, and in what order — see `ExtraKey` for the full catalog
/// and `ExtraKeysAccessoryView` for where the selection actually renders.
struct KeyboardShortcutsCustomizeView: View {
    @AppStorage("dev.termvault.settings.extraKeysOrder") private var order = ExtraKeysOrder(keys: ExtraKey.defaultOrder)

    private var availableKeys: [ExtraKey] {
        ExtraKey.allCases.filter { !order.keys.contains($0) }
    }

    var body: some View {
        List {
            Section {
                if order.keys.isEmpty {
                    Text("No keys shown — add some from the list below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(order.keys) { key in
                        row(for: key)
                    }
                    .onDelete { order.keys.remove(atOffsets: $0) }
                    .onMove { order.keys.move(fromOffsets: $0, toOffset: $1) }
                }
            } header: {
                Text("Shown in Keyboard Row")
            } footer: {
                Text("Tap Edit to drag and reorder, or swipe left to remove.")
            }

            if !availableKeys.isEmpty {
                Section("Available") {
                    ForEach(availableKeys) { key in
                        Button {
                            order.keys.append(key)
                        } label: {
                            HStack {
                                row(for: key)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button("Reset to Default", role: .destructive) {
                    order = ExtraKeysOrder(keys: ExtraKey.defaultOrder)
                }
            }
        }
        .navigationTitle("Keyboard Row")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func row(for key: ExtraKey) -> some View {
        HStack {
            Text(key.fullName)
            Spacer()
            Text(key.label)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        KeyboardShortcutsCustomizeView()
    }
}
