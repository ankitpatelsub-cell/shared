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

    func testAttachmentNameRemovesUnsafePathCharacters() {
        XCTAssertEqual(
            TerminalViewModel.safeAttachmentName("../../screen shot?.png"),
            ".._.._screen_shot_.png"
        )
    }

    func testAttachmentNamePreservesSafeCharacters() {
        XCTAssertEqual(
            TerminalViewModel.safeAttachmentName("error-log_2026.txt"),
            "error-log_2026.txt"
        )
    }
}
