import XCTest
@testable import TermVault

final class TermVaultTests: XCTestCase {
    @MainActor
    func testNavigationBackReturnsToPreviousTab() {
        let navigation = AppNavigationStore()
        navigation.navigate(to: .browser)
        navigation.navigate(to: .sessions)
        navigation.goBack()
        XCTAssertEqual(navigation.selectedTab, .browser)
    }

    // These two were never actually compiled before (CI never ran the test
    // target), so this @MainActor requirement — needed because
    // TerminalViewModel itself is @MainActor-isolated — went unnoticed
    // until the "Run unit tests" step landed.
    @MainActor
    func testAttachmentNameRemovesUnsafePathCharacters() {
        XCTAssertEqual(
            TerminalViewModel.safeAttachmentName("../../screen shot?.png"),
            ".._.._screen_shot_.png"
        )
    }

    @MainActor
    func testAttachmentNamePreservesSafeCharacters() {
        XCTAssertEqual(
            TerminalViewModel.safeAttachmentName("error-log_2026.txt"),
            "error-log_2026.txt"
        )
    }
}
