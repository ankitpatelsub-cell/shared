import XCTest
@testable import TermVault

final class ErrorLoggerTests: XCTestCase {
    var sut: ErrorLogger!

    override func setUp() {
        super.setUp()
        sut = ErrorLogger()
        sut.clearLogs()
    }

    override func tearDown() {
        sut.clearLogs()
        sut = nil
        super.tearDown()
    }

    func testLogCanBeAdded() {
        sut.log(category: .network, message: "Test error")
        let logs = sut.getRecentLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, "Test error")
        XCTAssertEqual(logs.first?.category, .network)
    }

    func testMultipleLogsCanBeAdded() {
        sut.log(category: .network, message: "Error 1")
        sut.log(category: .authentication, message: "Error 2")
        sut.log(category: .hostKey, message: "Error 3")

        let logs = sut.getRecentLogs()
        XCTAssertEqual(logs.count, 3)
    }

    func testLogsCanBeCleared() {
        sut.log(category: .network, message: "Test error")
        sut.clearLogs()
        let logs = sut.getRecentLogs()
        XCTAssertEqual(logs.count, 0)
    }

    func testLogExportToText() {
        sut.log(
            category: .network,
            message: "Connection failed",
            technicalDetails: "Timeout after 30 seconds",
            suggestion: "Check internet connection"
        )

        let exportedText = sut.exportLogsAsText()
        XCTAssertTrue(exportedText.contains("Network"))
        XCTAssertTrue(exportedText.contains("Connection failed"))
        XCTAssertTrue(exportedText.contains("Timeout after 30 seconds"))
        XCTAssertTrue(exportedText.contains("Check internet connection"))
    }

    func testSuggestedActionForTimeout() {
        let error = NSError(domain: "Test", code: 0, userInfo: [NSLocalizedDescriptionKey: "connection timed out"])
        let suggestion = ErrorLogger.suggestedAction(for: error)
        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion!.contains("internet connection"))
    }

    func testSuggestedActionForAuthFailure() {
        let error = NSError(domain: "Test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        let suggestion = ErrorLogger.suggestedAction(for: error)
        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion!.contains("username") || suggestion!.contains("password"))
    }
}
