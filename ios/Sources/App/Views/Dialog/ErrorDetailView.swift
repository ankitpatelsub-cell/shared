import SwiftUI

struct ErrorDetailView: View {
    let entry: ErrorLogger.LogEntry
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Error Message
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            Text(entry.category.rawValue)
                                .font(.headline)
                                .foregroundStyle(.red)
                        }
                        Text(entry.message)
                            .font(.body)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)

                    // Timestamp
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timestamp")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDate(entry.timestamp))
                            .font(.caption)
                            .monospaced()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    // Technical Details
                    if let technicalDetails = entry.technicalDetails {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Technical Details")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(technicalDetails)
                                .font(.caption)
                                .monospaced()
                                .textSelection(.enabled)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }

                    // Suggestion
                    if let suggestion = entry.suggestion {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.orange)
                                Text("Suggestion")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            Text(suggestion)
                                .font(.caption)
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Error Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    ErrorDetailView(
        entry: ErrorLogger.LogEntry(
            timestamp: Date(),
            category: .network,
            message: "Connection timeout",
            technicalDetails: "Failed to connect to example.com:22 after 30 seconds",
            suggestion: "Check your internet connection and verify the host address is correct."
        )
    )
}
