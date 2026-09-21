import Foundation
import XCTest
@testable import HeadroomCore

final class StorageTests: XCTestCase {
    func testCoherentDecimalCapacity() {
        let snapshot = StorageSnapshot(totalBytes: 250_000_000_000, freeBytes: 20_000_000_000,
                                       volumeName: "Test", fetchedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.freeGB, 20)
        XCTAssertEqual(snapshot.usedPercent, 92, accuracy: 0.000001)
    }

    func testNoAvailableSpaceIsCriticalRatherThanInvalid() {
        let snapshot = StorageSnapshot(totalBytes: 250, freeBytes: 0,
                                       volumeName: "Test", fetchedAt: Date())
        XCTAssertTrue(snapshot.isValidCapacity)
        XCTAssertEqual(snapshot.usedPercent, 100)
    }

    func testInvalidCapacityDoesNotProduceHealthyPercentage() {
        for values: (Int64, Int64) in [(0, 0), (100, -1), (100, 101)] {
            let snapshot = StorageSnapshot(totalBytes: values.0, freeBytes: values.1,
                                           volumeName: "Test", fetchedAt: Date())
            XCTAssertFalse(snapshot.isValidCapacity)
            XCTAssertTrue(snapshot.usedPercent.isNaN)
        }
    }

    func testNotificationOccursOnFirstCriticalSampleOnly() {
        var policy = StorageAlertPolicy()
        XCTAssertFalse(policy.observe(usedPercent: 94.999))
        XCTAssertTrue(policy.observe(usedPercent: 95))
        policy.completeDelivery(attemptID: policy.pendingAttemptID!, succeeded: true)
        XCTAssertFalse(policy.observe(usedPercent: 99))
        XCTAssertFalse(policy.observe(usedPercent: 94.5))
        XCTAssertFalse(policy.observe(usedPercent: 95))
    }

    func testRecoveryRequiresTwoConsecutiveSamplesStrictlyBelow94() {
        var policy = StorageAlertPolicy(isLatched: true)
        XCTAssertFalse(policy.observe(usedPercent: 93.9))
        XCTAssertTrue(policy.isLatched)
        XCTAssertFalse(policy.observe(usedPercent: 94))
        XCTAssertEqual(policy.recoveryReadCount, 0)
        XCTAssertFalse(policy.observe(usedPercent: 93.9))
        XCTAssertFalse(policy.observe(usedPercent: 93.9))
        XCTAssertFalse(policy.isLatched)
        XCTAssertTrue(policy.observe(usedPercent: 95))
    }

    func testReadFailureBreaksRecoverySequenceWithoutRearming() {
        var policy = StorageAlertPolicy(isLatched: true)
        policy.observe(usedPercent: 93)
        policy.recordFailure()
        policy.observe(usedPercent: 93)
        XCTAssertTrue(policy.isLatched)
        XCTAssertEqual(policy.recoveryReadCount, 1)
        XCTAssertFalse(policy.observe(usedPercent: 95))
    }

    func testInvalidSamplesCannotAlertOrRecover() {
        for sample in [Double.nan, Double.infinity, -1, 101] {
            var policy = StorageAlertPolicy(isLatched: true, recoveryReadCount: 1)
            XCTAssertFalse(policy.observe(usedPercent: sample))
            XCTAssertTrue(policy.isLatched)
            XCTAssertEqual(policy.recoveryReadCount, 0)
            var fresh = StorageAlertPolicy()
            XCTAssertFalse(fresh.observe(usedPercent: sample))
            XCTAssertFalse(fresh.isLatched)
        }
    }

    func testPersistedCriticalEpisodeDoesNotRenotifyOnRestart() throws {
        var policy = StorageAlertPolicy()
        XCTAssertTrue(policy.observe(usedPercent: 96))
        policy.completeDelivery(attemptID: policy.pendingAttemptID!, succeeded: true)
        let saved = try JSONEncoder().encode(policy)
        var restored = try JSONDecoder().decode(StorageAlertPolicy.self, from: saved)
        XCTAssertEqual(restored, policy)
        XCTAssertFalse(restored.observe(usedPercent: 96))
        restored.observe(usedPercent: 93)
        restored.observe(usedPercent: 93)
        XCTAssertTrue(restored.observe(usedPercent: 96))
    }

    func testRecoveryContinuesWhileNotificationsDisabled() {
        var policy = StorageAlertPolicy()
        XCTAssertTrue(policy.observe(usedPercent: 96))
        policy.completeDelivery(attemptID: policy.pendingAttemptID!, succeeded: true)
        XCTAssertFalse(policy.observe(usedPercent: 93, notificationsEnabled: false))
        XCTAssertFalse(policy.observe(usedPercent: 93, notificationsEnabled: false))
        XCTAssertFalse(policy.isLatched)
        XCTAssertFalse(policy.observe(usedPercent: 96, notificationsEnabled: false))
        XCTAssertTrue(policy.observe(usedPercent: 96, notificationsEnabled: true))
    }

    func testDisabledCriticalDoesNotConsumeFirstAlertOrRepeatExistingEpisode() {
        var fresh = StorageAlertPolicy()
        XCTAssertFalse(fresh.observe(usedPercent: 96, notificationsEnabled: false))
        XCTAssertFalse(fresh.isLatched)
        XCTAssertTrue(fresh.observe(usedPercent: 96, notificationsEnabled: true))
        fresh.completeDelivery(attemptID: fresh.pendingAttemptID!, succeeded: true)
        XCTAssertFalse(fresh.observe(usedPercent: 96, notificationsEnabled: false))
        XCTAssertFalse(fresh.observe(usedPercent: 96, notificationsEnabled: true))
        fresh.observe(usedPercent: 93, notificationsEnabled: false)
        fresh.observe(usedPercent: 96, notificationsEnabled: false)
        fresh.observe(usedPercent: 93, notificationsEnabled: false)
        XCTAssertTrue(fresh.isLatched)
    }

    func testReaderRejectsMissingPathInsteadOfUsingParentVolume() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try StorageReader.read(url: missing))
    }
}
