import XCTest
@testable import Headroom

final class SetupRecoveryTests: XCTestCase {
    @MainActor func testMissingExecutableOffersSetupInsteadOfAnotherRetry() {
        let model = AppModel()
        model.cliPath = "/nonexistent-headroom-test/codex"
        model.refreshCodex()
        XCTAssertTrue(model.codexNeedsSetup)
        XCTAssertNil(model.codex)
        XCTAssertFalse(model.codexRefreshing)
        XCTAssertFalse(model.codexError?.contains("below") ?? true)
    }
    @MainActor func testValidExecutableClearsSetupStateBeforeRead() {
        let model = AppModel()
        model.cliPath = "/nonexistent-headroom-test/codex"
        model.refreshCodex()
        XCTAssertTrue(model.codexNeedsSetup)
        model.cliPath = "/usr/bin/true"
        model.refreshCodex()
        XCTAssertFalse(model.codexNeedsSetup)
        model.stop()
    }
}
