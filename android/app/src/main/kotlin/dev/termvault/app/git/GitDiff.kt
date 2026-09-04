package dev.termvault.app.git

import java.util.UUID

/** Direct Kotlin port of iOS `GitDiff.swift` — a dependency-free unified-diff parser. */

data class GitDiffLine(
    val id: UUID = UUID.randomUUID(),
    val kind: Kind,
    val text: String,
) {
    enum class Kind { CONTEXT, ADDITION, DELETION }
}

data class GitDiffHunk(
    val id: UUID = UUID.randomUUID(),
    val header: String,
    val lines: List<GitDiffLine>,
)

data class GitDiffFile(
    val id: UUID = UUID.randomUUID(),
    val oldPath: String,
    val newPath: String,
    val isNew: Boolean,
    val isDeleted: Boolean,
    val isRenamed: Boolean,
    val isBinary: Boolean,
    val hunks: List<GitDiffHunk>,
) {
    val displayPath: String get() = if (newPath == "/dev/null") oldPath else newPath
    val additions: Int get() = hunks.sumOf { hunk -> hunk.lines.count { it.kind == GitDiffLine.Kind.ADDITION } }
    val deletions: Int get() = hunks.sumOf { hunk -> hunk.lines.count { it.kind == GitDiffLine.Kind.DELETION } }
}

object GitDiff {
    fun parse(raw: String): List<GitDiffFile> {
        val files = mutableListOf<GitDiffFile>()
        val lines = raw.split("\n")

        var oldPath = ""
        var newPath = ""
        var isNew = false
        var isDeleted = false
        var isRenamed = false
        var isBinary = false
        var hasCurrentFile = false

        var hunks = mutableListOf<GitDiffHunk>()
        var hunkHeader: String? = null
        var hunkLines = mutableListOf<GitDiffLine>()

        fun flushHunk() {
            val header = hunkHeader
            if (header != null) {
                hunks.add(GitDiffHunk(header = header, lines = hunkLines.toList()))
            }
            hunkHeader = null
            hunkLines = mutableListOf()
        }

        fun flushFile() {
            flushHunk()
            if (hasCurrentFile) {
                files.add(
                    GitDiffFile(
                        oldPath = oldPath,
                        newPath = newPath,
                        isNew = isNew,
                        isDeleted = isDeleted,
                        isRenamed = isRenamed,
                        isBinary = isBinary,
                        hunks = hunks.toList(),
                    )
                )
            }
            hunks = mutableListOf()
            oldPath = ""
            newPath = ""
            isNew = false
            isDeleted = false
            isRenamed = false
            isBinary = false
            hasCurrentFile = false
        }

        fun stripPrefix(path: String): String =
            if (path == "/dev/null") path else path.removePrefix("a/").removePrefix("b/")

        for (line in lines) {
            when {
                line.startsWith("diff --git ") -> {
                    flushFile()
                    hasCurrentFile = true
                    val rest = line.removePrefix("diff --git ")
                    val parts = rest.split(" b/", limit = 2)
                    if (parts.size == 2) {
                        oldPath = parts[0].removePrefix("a/")
                        newPath = parts[1]
                    }
                }
                line.startsWith("new file mode") -> isNew = true
                line.startsWith("deleted file mode") -> isDeleted = true
                line.startsWith("rename from ") -> {
                    isRenamed = true
                    oldPath = line.removePrefix("rename from ")
                }
                line.startsWith("rename to ") -> {
                    isRenamed = true
                    newPath = line.removePrefix("rename to ")
                }
                line.startsWith("Binary files ") || line.startsWith("GIT binary patch") -> isBinary = true
                line.startsWith("--- ") -> oldPath = stripPrefix(line.removePrefix("--- ").trim())
                line.startsWith("+++ ") -> newPath = stripPrefix(line.removePrefix("+++ ").trim())
                line.startsWith("@@ ") -> {
                    flushHunk()
                    hunkHeader = line
                }
                hunkHeader != null && line.startsWith("+") ->
                    hunkLines.add(GitDiffLine(kind = GitDiffLine.Kind.ADDITION, text = line.removePrefix("+")))
                hunkHeader != null && line.startsWith("-") ->
                    hunkLines.add(GitDiffLine(kind = GitDiffLine.Kind.DELETION, text = line.removePrefix("-")))
                hunkHeader != null && line.startsWith("\\ No newline at end of file") -> Unit
                hunkHeader != null ->
                    hunkLines.add(GitDiffLine(kind = GitDiffLine.Kind.CONTEXT, text = line.removePrefix(" ")))
            }
        }
        flushFile()

        return files
    }
}
