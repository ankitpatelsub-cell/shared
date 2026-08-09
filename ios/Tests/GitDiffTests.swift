import XCTest
@testable import TermVault

final class GitDiffTests: XCTestCase {
    func testEmptyDiffProducesNoFiles() {
        XCTAssertTrue(GitDiff.parse("").isEmpty)
    }

    func testModifiedFileCountsAdditionsAndDeletions() {
        let raw = """
        diff --git a/foo.txt b/foo.txt
        index e69de29..0cfbf08 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,3 +1,4 @@
         line1
        -line2
        +line2 modified
        +line3 added
         line4
        """
        let files = GitDiff.parse(raw)
        XCTAssertEqual(files.count, 1)
        let file = files[0]
        XCTAssertEqual(file.displayPath, "foo.txt")
        XCTAssertFalse(file.isNew)
        XCTAssertFalse(file.isDeleted)
        XCTAssertFalse(file.isRenamed)
        XCTAssertEqual(file.additions, 2)
        XCTAssertEqual(file.deletions, 1)
        XCTAssertEqual(file.hunks.count, 1)
        XCTAssertEqual(file.hunks[0].lines.filter { $0.kind == .context }.count, 2)
    }

    func testNewFileIsFlagged() {
        let raw = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..e69de29
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +hello
        +world
        """
        let files = GitDiff.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isNew)
        XCTAssertEqual(files[0].displayPath, "new.txt")
        XCTAssertEqual(files[0].additions, 2)
        XCTAssertEqual(files[0].deletions, 0)
    }

    func testDeletedFileIsFlagged() {
        let raw = """
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        index e69de29..0000000
        --- a/old.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -hello
        -world
        """
        let files = GitDiff.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isDeleted)
        XCTAssertEqual(files[0].displayPath, "old.txt")
        XCTAssertEqual(files[0].deletions, 2)
    }

    func testRenamedFileWithNoContentChange() {
        let raw = """
        diff --git a/a.txt b/b.txt
        similarity index 100%
        rename from a.txt
        rename to b.txt
        """
        let files = GitDiff.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isRenamed)
        XCTAssertEqual(files[0].oldPath, "a.txt")
        XCTAssertEqual(files[0].newPath, "b.txt")
        XCTAssertTrue(files[0].hunks.isEmpty)
    }

    func testMultipleFilesInOneDiff() {
        let raw = """
        diff --git a/one.txt b/one.txt
        index e69de29..0cfbf08 100644
        --- a/one.txt
        +++ b/one.txt
        @@ -1 +1 @@
        -old
        +new
        diff --git a/two.txt b/two.txt
        index e69de29..0cfbf08 100644
        --- a/two.txt
        +++ b/two.txt
        @@ -1 +1 @@
        -foo
        +bar
        """
        let files = GitDiff.parse(raw)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].displayPath, "one.txt")
        XCTAssertEqual(files[1].displayPath, "two.txt")
    }

    func testBinaryFileIsFlaggedWithoutHunks() {
        let raw = """
        diff --git a/image.png b/image.png
        index e69de29..0cfbf08 100644
        Binary files a/image.png and b/image.png differ
        """
        let files = GitDiff.parse(raw)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isBinary)
        XCTAssertTrue(files[0].hunks.isEmpty)
    }
}
