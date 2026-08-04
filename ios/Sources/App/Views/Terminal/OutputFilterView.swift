import SwiftUI

struct OutputFilterView: View {
    let transcript: String
    @Binding var isPresented: Bool
    @State private var filterText = ""
    @State private var filterMode: FilterMode = .contains
    @State private var invertFilter = false

    enum FilterMode {
        case contains
        case startsWith
        case regex
    }

    private var filteredLines: [String] {
        let lines = transcript.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard !filterText.isEmpty else { return lines }

        let filtered: [String]
        switch filterMode {
        case .contains:
            filtered = lines.filter { $0.localizedCaseInsensitiveContains(filterText) }
        case .startsWith:
            filtered = lines.filter { $0.lowercased().starts(with: filterText.lowercased()) }
        case .regex:
            if let regex = try? NSRegularExpression(pattern: filterText) {
                let nsString = lines.joined(separator: "\n") as NSString
                let matches = regex.matches(in: nsString as String, range: NSRange(location: 0, length: nsString.length))
                filtered = matches.flatMap { match in
                    let range = match.range
                    let matchedString = nsString.substring(with: range)
                    return matchedString.split(separator: "\n").map(String.init)
                }
            } else {
                filtered = lines
            }
        }

        return invertFilter ? lines.filter { !filtered.contains($0) } : filtered
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.blue)

                        TextField("Filter pattern", text: $filterText)
                            .textFieldStyle(.roundedBorder)

                        if !filterText.isEmpty {
                            Button {
                                filterText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        Picker("Mode", selection: $filterMode) {
                            Text("Contains").tag(FilterMode.contains)
                            Text("Starts With").tag(FilterMode.startsWith)
                            Text("Regex").tag(FilterMode.regex)
                        }
                        .pickerStyle(.segmented)
                        .font(.caption)

                        Toggle("Invert", isOn: $invertFilter)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding()

                if filterText.isEmpty {
                    ContentUnavailableView(
                        "Filter Output",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Enter a pattern to filter terminal output")
                    )
                } else if filteredLines.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No lines match the filter pattern")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(filteredLines.count) matching line\(filteredLines.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(nil)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .textSelection(.enabled)

                                    if index < filteredLines.count - 1 {
                                        Divider()
                                    }
                                }
                                .background(Color(.systemGray6))
                            }
                        }
                        .padding()
                    }
                }

                Spacer()
            }
            .navigationTitle("Filter Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
