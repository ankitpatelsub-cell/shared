import Foundation
import os.log

/// Centralized error logging with file persistence and categorization
final class ErrorLogger {
    static let shared = ErrorLogger()

    enum ErrorCategory: String, Codable {
        case network = "Network"
        case authentication = "Authentication"
        case hostKey = "Host Key"
        case fileOperation = "File Operation"
        case general = "General"
    }

    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let category: ErrorCategory
        let message: String
        let technicalDetails: String?
        let suggestion: String?

        init(id: UUID = UUID(), timestamp: Date, category: ErrorCategory, message: String, technicalDetails: String? = nil, suggestion: String? = nil) {
            self.id = id
            self.timestamp = timestamp
            self.category = category
            self.message = message
            self.technicalDetails = technicalDetails
            self.suggestion = suggestion
        }
    }

    private let logger = OSLog(subsystem: "dev.termvault", category: "errors")
    private let fileManager = FileManager.default
    private var logs: [LogEntry] = []
    private let logsDirectoryKey = "dev.termvault.logsDirectory"

    init() {
        loadLogsFromDisk()
    }

    func log(
        category: ErrorCategory,
        message: String,
        technicalDetails: String? = nil,
        suggestion: String? = nil
    ) {
        let entry = LogEntry(
            timestamp: Date(),
            category: category,
            message: message,
            technicalDetails: technicalDetails,
            suggestion: suggestion
        )

        logs.append(entry)
        os_log("[%{public}@] %{public}@", log: logger, type: .error, category.rawValue, message)

        if let details = technicalDetails {
            os_log("Details: %{public}@", log: logger, type: .debug, details)
        }

        saveToDisk()
    }

    func getRecentLogs(limit: Int = 50) -> [LogEntry] {
        Array(logs.suffix(limit))
    }

    func clearLogs() {
        logs.removeAll()
        saveToDisk()
    }

    func exportLogsAsText() -> String {
        logs.map { entry in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestamp = dateFormatter.string(from: entry.timestamp)

            var text = "[\(timestamp)] \(entry.category.rawValue): \(entry.message)"
            if let details = entry.technicalDetails {
                text += "\n  Technical: \(details)"
            }
            if let suggestion = entry.suggestion {
                text += "\n  Suggestion: \(suggestion)"
            }
            return text
        }.joined(separator: "\n\n")
    }

    private func saveToDisk() {
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(self.logs)
                let logsDir = self.getLogsDirectory()
                try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
                let filePath = logsDir.appendingPathComponent("errors.json")
                try data.write(to: filePath)
            } catch {
                os_log("Failed to save logs: %{public}@", log: self.logger, type: .error, error.localizedDescription)
            }
        }
    }

    private func loadLogsFromDisk() {
        DispatchQueue.global(qos: .background).async {
            do {
                let filePath = self.getLogsDirectory().appendingPathComponent("errors.json")
                if FileManager.default.fileExists(atPath: filePath.path) {
                    let data = try Data(contentsOf: filePath)
                    self.logs = try JSONDecoder().decode([LogEntry].self, from: data)
                }
            } catch {
                os_log("Failed to load logs: %{public}@", log: self.logger, type: .error, error.localizedDescription)
            }
        }
    }

    private func getLogsDirectory() -> URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return documentsDir.appendingPathComponent("TermVaultLogs")
    }
}

// MARK: - Error Suggestions
extension ErrorLogger {
    static func suggestedAction(for error: Error) -> String? {
        let errorString = error.localizedDescription.lowercased()

        if errorString.contains("connection timed out") || errorString.contains("unable to connect") {
            return "Check your internet connection and verify the host address is correct."
        } else if errorString.contains("connection refused") {
            return "SSH service may not be running on the host. Verify SSH is enabled and listening on the specified port."
        } else if errorString.contains("permission denied") || errorString.contains("authentication failed") {
            return "Check your username and password/key. Verify SSH key permissions (should be 600)."
        } else if errorString.contains("host key verification failed") {
            return "The host key changed. This could indicate a security issue. Verify the host hasn't been compromised."
        } else if errorString.contains("no such file") {
            return "The file or directory doesn't exist. Check the path is correct."
        }

        return nil
    }
}

