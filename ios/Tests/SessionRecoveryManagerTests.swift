import XCTest
@testable import TermVault

@MainActor
final class SessionRecoveryManagerTests: XCTestCase {
    var sut: SessionRecoveryManager!

    override func setUp() {
        super.setUp()
        sut = SessionRecoveryManager()
    }

    override func tearDown() {
        sut.cancelRecovery()
        sut = nil
        super.tearDown()
    }

    func testInitialStateIsIdle() {
        if case .idle = sut.recoveryState {
            XCTAssert(true)
        } else {
            XCTFail("Initial state should be idle")
        }
    }

    func testIsRecoveringReturnsFalseWhenIdle() {
        XCTAssertFalse(sut.isRecovering())
    }

    func testIsRecoveringReturnsTrueWhenReconnecting() async {
        let expectation = XCTestExpectation(description: "Reconnecting state reached")

        sut.startRecovery {
            try await Task.sleep(for: .seconds(10))
            throw NSError(domain: "Test", code: -1)
        }

        try? await Task.sleep(for: .milliseconds(100))
        if case .reconnecting = sut.recoveryState {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testRecoveryCanBeCancelled() async {
        sut.startRecovery {
            try await Task.sleep(for: .seconds(10))
            throw NSError(domain: "Test", code: -1)
        }

        try? await Task.sleep(for: .milliseconds(100))
        sut.cancelRecovery()

        if case .idle = sut.recoveryState {
            XCTAssert(true)
        } else {
            XCTFail("State should return to idle after cancellation")
        }
    }

    func testSuccessfulReconnection() async {
        let expectation = XCTestExpectation(description: "Recovery succeeded")

        sut.startRecovery {
            // Simulate successful reconnection
        }

        try? await Task.sleep(for: .milliseconds(100))
        if case .recovered = sut.recoveryState {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testFailureAfterMaxAttempts() async {
        let expectation = XCTestExpectation(description: "Recovery failed")

        sut.startRecovery {
            throw NSError(domain: "Test", code: -1)
        }

        try? await Task.sleep(for: .milliseconds(500))

        if case .failed = sut.recoveryState {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }
}
