import XCTest
@testable import HeadroomCore

final class AlertDeliveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFailedSubmissionRetriesAtMostThreeTimesWithoutLatching() throws {
        var policy = StorageAlertPolicy()
        for attempt in 0..<3 {
            let time = now.addingTimeInterval(Double(attempt * 60))
            XCTAssertTrue(policy.observe(usedPercent: 96, now: time))
            XCTAssertFalse(policy.observe(usedPercent: 96, now: time.addingTimeInterval(60))) // still pending
            policy.completeDelivery(attemptID: try XCTUnwrap(policy.pendingAttemptID), succeeded: false)
            XCTAssertFalse(policy.isLatched)
            XCTAssertFalse(policy.observe(usedPercent: 96, now: time.addingTimeInterval(59)))
        }
        XCTAssertTrue(policy.retriesExhausted)
        XCTAssertFalse(policy.observe(usedPercent: 96, now: now.addingTimeInterval(3600)))
        policy.observe(usedPercent: 93, notificationsEnabled: false)
        policy.observe(usedPercent: 93, notificationsEnabled: false)
        XCTAssertTrue(policy.observe(usedPercent: 96, now: now.addingTimeInterval(3600)))
    }

    func testAcceptedRetryLatchesAndPreventsFurtherAttempts() throws {
        var policy = StorageAlertPolicy()
        XCTAssertTrue(policy.observe(usedPercent: 96, now: now))
        policy.completeDelivery(attemptID: try XCTUnwrap(policy.pendingAttemptID), succeeded: false)
        XCTAssertTrue(policy.observe(usedPercent: 96, now: now.addingTimeInterval(60)))
        policy.completeDelivery(attemptID: try XCTUnwrap(policy.pendingAttemptID), succeeded: true)
        XCTAssertTrue(policy.isLatched)
        XCTAssertFalse(policy.observe(usedPercent: 96, now: now.addingTimeInterval(3600)))
    }

    func testRestartPreservesRetryBudgetAndDelayButNotInFlightWork() throws {
        var policy = StorageAlertPolicy()
        policy.observe(usedPercent: 96, now: now)
        var restored = try JSONDecoder().decode(StorageAlertPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertNil(restored.pendingAttemptID)
        XCTAssertEqual(restored.deliveryAttempts, 1)
        XCTAssertFalse(restored.observe(usedPercent: 96, now: now.addingTimeInterval(59)))
        XCTAssertTrue(restored.observe(usedPercent: 96, now: now.addingTimeInterval(60)))
    }

    func testLateResultCannotLatchNewEpisode() throws {
        var policy = StorageAlertPolicy()
        policy.observe(usedPercent: 96, now: now)
        let old = try XCTUnwrap(policy.pendingAttemptID)
        policy.observe(usedPercent: 93, notificationsEnabled: false)
        policy.observe(usedPercent: 93, notificationsEnabled: false)
        policy.observe(usedPercent: 96, now: now.addingTimeInterval(60))
        let current = policy.pendingAttemptID
        policy.completeDelivery(attemptID: old, succeeded: true)
        XCTAssertFalse(policy.isLatched)
        XCTAssertEqual(policy.pendingAttemptID, current)
    }

    func testOldPersistedEpisodeMigratesWithoutDuplicateAlert() throws {
        let data = Data(#"{"isLatched":true,"recoveryReadCount":0}"#.utf8)
        var policy = try JSONDecoder().decode(StorageAlertPolicy.self, from: data)
        XCTAssertTrue(policy.isLatched)
        XCTAssertFalse(policy.observe(usedPercent: 96, now: now))
    }

    func testPermissionRevocationBlocksWithoutConsumingAttempt() {
        XCTAssertEqual(NotificationReadiness.evaluate(requested: false, permission: .allowed), .off)
        XCTAssertEqual(NotificationReadiness.evaluate(requested: true, permission: .unknown), .checking)
        XCTAssertEqual(NotificationReadiness.evaluate(requested: true, permission: .allowed), .enabled)
        XCTAssertEqual(NotificationReadiness.evaluate(requested: true, permission: .notRequested), .blocked)
        let revoked = NotificationReadiness.evaluate(requested: true, permission: .blocked)
        XCTAssertEqual(revoked, .blocked)
        var policy = StorageAlertPolicy()
        XCTAssertFalse(policy.observe(usedPercent: 96, notificationsEnabled: revoked == .enabled, now: now))
        XCTAssertEqual(policy.deliveryAttempts, 0)
        XCTAssertTrue(policy.observe(usedPercent: 96, notificationsEnabled: true, now: now))
    }
}
