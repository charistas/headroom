import XCTest
@testable import HeadroomCore

final class WeeklyPaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(left: Double, days: Double, age: Double = 0) -> CodexSnapshot {
        CodexSnapshot(remainingPercent: 1, windowLabel: "5-hour allowance", resetsAt: now.addingTimeInterval(3600),
                      fetchedAt: now.addingTimeInterval(-age),
                      weekly: CodexWeeklyWindow(remainingPercent: left, resetsAt: now.addingTimeInterval(days * 86400)))
    }
    func testWeeklyBudgetIsIndependentOfMoreConstrainedShortWindow() throws {
        let pace = try XCTUnwrap(WeeklyPace.evaluate(snapshot: snapshot(left: 70, days: 3.5), now: now))
        XCTAssertEqual(pace.remainingPercent, 70)
        XCTAssertEqual(pace.timeRemainingPercent, 50, accuracy: 0.0001)
        XCTAssertEqual(pace.status, .onPace)
        XCTAssertEqual(try XCTUnwrap(pace.dailyBudgetPercent), 20, accuracy: 0.0001)
    }
    func testOverBudgetAndExactEvenPace() throws {
        XCTAssertEqual(WeeklyPace.evaluate(snapshot: snapshot(left: 30, days: 3.5), now: now)?.status, .faster)
        XCTAssertEqual(WeeklyPace.evaluate(snapshot: snapshot(left: 50, days: 3.5), now: now)?.status, .onPace)
        XCTAssertEqual(WeeklyPace.evaluate(snapshot: snapshot(left: 49.9, days: 3.5), now: now)?.status, .nearPace)
    }
    func testNoUsageAndExhaustion() {
        XCTAssertEqual(WeeklyPace.evaluate(snapshot: snapshot(left: 100, days: 7), now: now)?.status, .onPace)
        XCTAssertEqual(WeeklyPace.evaluate(snapshot: snapshot(left: 0, days: 1), now: now)?.status, .exhausted)
    }
    func testExpiredFutureAndStaleWindowsDoNotShowPace() {
        for value in [snapshot(left: 70, days: 0), snapshot(left: 70, days: -1),
                      snapshot(left: 70, days: 7.1), snapshot(left: 70, days: 3, age: 301),
                      snapshot(left: 70, days: 3, age: -1)] {
            XCTAssertNil(WeeklyPace.evaluate(snapshot: value, now: now))
        }
    }
    func testMissingAndMalformedWeeklyDataDoNotInventPace() {
        let missing = CodexSnapshot(remainingPercent: 70, windowLabel: "Weekly allowance", resetsAt: now.addingTimeInterval(86400), fetchedAt: now)
        XCTAssertNil(WeeklyPace.evaluate(snapshot: missing, now: now))
        for value in [Double.nan, Double.infinity, -1, 101] {
            XCTAssertNil(WeeklyPace.evaluate(snapshot: snapshot(left: value, days: 3), now: now))
        }
    }
    func testFinalDayDoesNotSuggestAnInflatedDailyBudget() throws {
        let pace = try XCTUnwrap(WeeklyPace.evaluate(snapshot: snapshot(left: 10, days: 0.5), now: now))
        XCTAssertNil(pace.dailyBudgetPercent)
        XCTAssertEqual(pace.daysRemaining, 0.5)
    }
    func testElapsedTimeUpdatesComparisonWithoutInventingUsage() throws {
        let value = snapshot(left: 47.99, days: 3.5)
        XCTAssertEqual(WeeklyPace.evaluate(snapshot: value, now: now)?.status, .faster)
        let later = try XCTUnwrap(WeeklyPace.evaluate(snapshot: value, now: now.addingTimeInterval(120)))
        XCTAssertEqual(later.remainingPercent, 47.99)
        XCTAssertEqual(later.status, .nearPace)
    }
}
