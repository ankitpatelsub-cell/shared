import Foundation

/// A minimal unified-diff parser — just enough of `git diff`'s output
/// format to drive a colored, per-file review UI. Not a general-purpose
/// diff/patch library; doesn't handle every edge case `git diff` can emit
/// (e.g. combined diffs from a merge), only the common single-parent case.
struct GitDiffFile: Identifiable {
    let id = UUID()
    let oldPath: String
    let newPath: String
    let isNew: Bool
    let isDeleted: Bool
    let isRenamed: Bool
    let isBinary: Bool
    let hunks: [GitDiffHunk]

    var displayPath: String { newPath == "/dev/null" ? oldPath : newPath }
    var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count } }
    var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count } }
}

struct GitDiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let lines: [GitDiffLine]
}

struct GitDiffLine: Identifiable {
    enum Kind { case context, addition, deletion }
    let id = UUID()
    let kind: Kind
    let text: String
}

enum GitDiff {
    static func parse(_ raw: String) -> [GitDiffFile] {
        guard !raw.isEmpty else { return [] }
        var files: [GitDiffFile] = []

        var oldPath = ""
        var newPath = ""
        var isNew = false
        var isDeleted = false
        var isRenamed = false
        var isBinary = false
        var hunks: [GitDiffHunk] = []
        var currentHunkHeader: String?
        var currentHunkLines: [GitDiffLine] = []
        var hasFile = false

        func flushHunk() {
            if let header = currentHunkHeader {
                hunks.append(GitDiffHunk(header: header, lines: currentHunkLines))
            }
            currentHunkHeader = nil
            currentHunkLines = []
        }

        func flushFile() {
            flushHunk()
            if hasFile {
                files.append(GitDiffFile(
                    oldPath: oldPath, newPath: newPath,
                    isNew: isNew, isDeleted: isDeleted, isRenamed: isRenamed, isBinary: isBinary,
                    hunks: hunks
                ))
            }
            oldPath = ""; newPath = ""
            isNew = false; isDeleted = false; isRenamed = false; isBinary = false
            hunks = []
            hasFile = false
        }

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("diff --git ") {
                flushFile()
                hasFile = true
                // "diff --git a/old b/new" — paths themselves can contain
                // spaces, so this split is best-effort; --- / +++ below
                // give the authoritative paths for the common case.
                let parts = text.dropFirst("diff --git ".count).split(separator: " ")
                if parts.count >= 2 {
                    oldPath = String(parts[0].dropFirst(2))
                    newPath = String(parts[1].dropFirst(2))
                }
            } else if text.hasPrefix("new file mode") {
                isNew = true
            } else if text.hasPrefix("deleted file mode") {
                isDeleted = true
            } else if text.hasPrefix("rename from ") {
                isRenamed = true
                oldPath = String(text.dropFirst("rename from ".count))
            } else if text.hasPrefix("rename to ") {
                isRenamed = true
                newPath = String(text.dropFirst("rename to ".count))
            } else if text.hasPrefix("Binary files ") || text.contains("GIT binary patch") {
                isBinary = true
            } else if text.hasPrefix("--- ") {
                let path = String(text.dropFirst(4))
                if path != "/dev/null" { oldPath = path.hasPrefix("a/") ? String(path.dropFirst(2)) : path }
            } else if text.hasPrefix("+++ ") {
                let path = String(text.dropFirst(4))
                if path != "/dev/null" { newPath = path.hasPrefix("b/") ? String(path.dropFirst(2)) : path }
            } else if text.hasPrefix("@@ ") {
                flushHunk()
                currentHunkHeader = text
            } else if currentHunkHeader != nil {
                if text.hasPrefix("+") {
                    currentHunkLines.append(GitDiffLine(kind: .addition, text: String(text.dropFirst())))
                } else if text.hasPrefix("-") {
                    currentHunkLines.append(GitDiffLine(kind: .deletion, text: String(text.dropFirst())))
                } else if text.hasPrefix("\\ ") {
                    // "\ No newline at end of file" — not a real line, skip.
                } else {
                    currentHunkLines.append(GitDiffLine(kind: .context, text: String(text.dropFirst(min(1, text.count)))))
                }
            }
        }
        flushFile()
        return files
    }
}
