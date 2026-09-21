import XCTest
import ServiceManagement
@testable import Headroom

final class LaunchAtLoginTests: XCTestCase {
    @MainActor func testRegistrationAndRemovalReflectSystemState() {
        var state: SMAppService.Status = .notRegistered
        var registrations = 0
        var removals = 0
        let login = LaunchAtLogin(readStatus: { state }, register: { registrations += 1; state = .enabled },
                                  unregister: { removals += 1; state = .notRegistered })
        XCTAssertFalse(login.isEnabled)
        XCTAssertEqual(registrations, 0)
        login.setEnabled(true)
        login.setEnabled(true)
        XCTAssertTrue(login.isEnabled)
        XCTAssertEqual(registrations, 1)
        login.setEnabled(false)
        XCTAssertFalse(login.isEnabled)
        XCTAssertEqual(removals, 1)
    }

    @MainActor func testExternalRevocationRequiresApprovalWithoutReregistering() {
        var state: SMAppService.Status = .enabled
        var openedSettings = false
        let login = LaunchAtLogin(readStatus: { state }, register: { XCTFail("Must not reregister revoked item") },
                                  openSettings: { openedSettings = true })
        state = .requiresApproval
        login.refresh()
        XCTAssertFalse(login.isEnabled)
        login.setEnabled(true)
        XCTAssertTrue(openedSettings)
        state = .enabled
        login.refresh()
        XCTAssertTrue(login.isEnabled)
    }

    @MainActor func testFailureDoesNotClaimEnabled() {
        struct Failed: Error {}
        let login = LaunchAtLogin(readStatus: { .notRegistered }, register: { throw Failed() })
        login.setEnabled(true)
        XCTAssertFalse(login.isEnabled)
        XCTAssertNotNil(login.message)
    }

    @MainActor func testFailedRemovalKeepsActualEnabledState() {
        struct Failed: Error {}
        let login = LaunchAtLogin(readStatus: { .enabled }, unregister: { throw Failed() })
        login.setEnabled(false)
        XCTAssertTrue(login.isEnabled)
        XCTAssertNotNil(login.message)
    }

    @MainActor func testDemoNeverReadsOrMutatesRegistration() {
        let login = LaunchAtLogin(demo: true, readStatus: { XCTFail("Demo read system state"); return .enabled },
                                  register: { XCTFail("Demo registered") }, unregister: { XCTFail("Demo unregistered") },
                                  openSettings: { XCTFail("Demo opened settings") })
        login.refresh()
        login.setEnabled(true)
        login.setEnabled(false)
        login.showSettings()
        XCTAssertFalse(login.isEnabled)
    }
}
