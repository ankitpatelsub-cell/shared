import XCTest
@testable import TermVault

final class HostKeyApprovalServiceTests: XCTestCase {
    var sut: HostKeyApprovalService!
    var mockDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockDefaults = UserDefaults(suiteName: "TestHostKeyApproval")
        mockDefaults?.removePersistentDomain(forName: "TestHostKeyApproval")
        sut = HostKeyApprovalService(defaults: mockDefaults)
    }

    override func tearDown() {
        mockDefaults?.removePersistentDomain(forName: "TestHostKeyApproval")
        sut = nil
        mockDefaults = nil
        super.tearDown()
    }

    func testSessionTrustNotSetInitially() {
        let isTrusted = sut.isSessionTrusted(host: "example.com", port: 22, fingerprint: "abc123")
        XCTAssertFalse(isTrusted)
    }

    func testSessionTrustCanBeSet() {
        sut.trustSessionOnly(host: "example.com", port: 22, fingerprint: "abc123")
        let isTrusted = sut.isSessionTrusted(host: "example.com", port: 22, fingerprint: "abc123")
        XCTAssertTrue(isTrusted)
    }

    func testDifferentFingerprintNotTrusted() {
        sut.trustSessionOnly(host: "example.com", port: 22, fingerprint: "abc123")
        let isTrusted = sut.isSessionTrusted(host: "example.com", port: 22, fingerprint: "xyz789")
        XCTAssertFalse(isTrusted)
    }

    func testDifferentHostNotTrusted() {
        sut.trustSessionOnly(host: "example.com", port: 22, fingerprint: "abc123")
        let isTrusted = sut.isSessionTrusted(host: "other.com", port: 22, fingerprint: "abc123")
        XCTAssertFalse(isTrusted)
    }

    func testSessionTrustsCanBeCleared() {
        sut.trustSessionOnly(host: "example.com", port: 22, fingerprint: "abc123")
        sut.clearSessionTrusts()
        let isTrusted = sut.isSessionTrusted(host: "example.com", port: 22, fingerprint: "abc123")
        XCTAssertFalse(isTrusted)
    }
}
