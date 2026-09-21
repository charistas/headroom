import XCTest
@testable import HeadroomCore

final class QuotaPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(left: Double, label: String = "5-hour allowance", weekly: Double = 70) -> CodexSnapshot {
        CodexSnapshot(remainingPercent: left, windowLabel: label, resetsAt: now.addingTimeInterval(3600), fetchedAt: now,
                      weekly: CodexWeeklyWindow(remainingPercent: weekly, resetsAt: now.addingTimeInterval(3.5 * 86400)))
    }
    func testExhaustedShortWindowIsRedEvenWhenWeeklyPaceHealthy() {
        let value = QuotaPresentation.evaluate(snapshot(left: 0), now: now)
        XCTAssertEqual(value.text, "5h 0%")
        XCTAssertEqual(value.tone, .critical)
        XCTAssertTrue(value.accessibilityText.contains("5-hour allowance"))
    }
    func testShortWindowDoesNotBorrowWeeklyPaceColor() {
        let value = QuotaPresentation.evaluate(snapshot(left: 10, weekly: 20), now: now)
        XCTAssertEqual(value.text, "5h 10%")
        XCTAssertEqual(value.tone, .neutral)
    }
    func testWeeklyScopeUsesWeeklyPaceAndNearPaceTolerance() {
        for (left, tone): (Double, QuotaPresentation.Tone) in [(0, .critical), (20, .warning), (47.99, .warning), (48, .neutral), (49.9, .neutral), (70, .neutral)] {
            let q = snapshot(left: left, label: "Weekly allowance", weekly: left)
            XCTAssertEqual(QuotaPresentation.evaluate(q, now: now).tone, tone)
            XCTAssertTrue(QuotaPresentation.evaluate(q, now: now).text.hasPrefix("7d "))
        }
    }
    func testFractionalAllowanceDoesNotLookExhausted() {
        let value = QuotaPresentation.evaluate(snapshot(left: 0.5), now: now)
        XCTAssertEqual(value.text, "5h <1%")
        XCTAssertEqual(value.tone, .neutral)
        XCTAssertTrue(value.accessibilityText.contains("less than one"))
    }
    func testMissingExpiredAndStaleDataAreUnavailable() {
        XCTAssertEqual(QuotaPresentation.evaluate(nil, now: now).text, "—")
        let q = snapshot(left: 70)
        XCTAssertEqual(QuotaPresentation.evaluate(q, now: now.addingTimeInterval(301)).text, "—")
        XCTAssertEqual(QuotaPresentation.evaluate(q, now: now.addingTimeInterval(-1)).text, "—")
        let expired = CodexSnapshot(remainingPercent: 70, windowLabel: "5-hour allowance", resetsAt: now, fetchedAt: now)
        XCTAssertEqual(QuotaPresentation.evaluate(expired, now: now).text, "—")
    }
}
