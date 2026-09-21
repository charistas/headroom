import Foundation

/// An even-use budget for the explicitly returned seven-day quota window.
/// This is a comparison, not a prediction of future work or model availability.
public struct WeeklyPace: Equatable, Sendable {
    public enum Status: String, Sendable {
        case onPace = "On pace"
        case nearPace = "Near pace"
        case faster = "Using faster than pace"
        case exhausted = "Weekly allowance exhausted"
    }
    /// A small planning tolerance, in percentage points of the full weekly allowance.
    public static let tolerance = 2.0
    public let remainingPercent: Double
    public let timeRemainingPercent: Double
    public let daysRemaining: Double
    public let status: Status
    public var percentagePointsFromPace: Double { remainingPercent - timeRemainingPercent }
    public var dailyBudgetPercent: Double? { daysRemaining >= 1 ? remainingPercent / daysRemaining : nil }

    public static func evaluate(snapshot: CodexSnapshot, now: Date = Date()) -> WeeklyPace? {
        guard let weekly = snapshot.weekly,
              weekly.remainingPercent.isFinite, (0...100).contains(weekly.remainingPercent) else { return nil }
        let duration: TimeInterval = 7 * 24 * 60 * 60
        let secondsLeft = weekly.resetsAt.timeIntervalSince(now)
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard secondsLeft.isFinite, secondsLeft > 0, secondsLeft <= duration,
              age.isFinite, age >= 0, age <= 300 else { return nil }
        let timePercent = secondsLeft / duration * 100
        let status: Status = weekly.remainingPercent == 0 ? .exhausted :
            (weekly.remainingPercent + 0.000001 >= timePercent ? .onPace :
                (weekly.remainingPercent + tolerance + 0.000001 >= timePercent ? .nearPace : .faster))
        return WeeklyPace(remainingPercent: weekly.remainingPercent, timeRemainingPercent: timePercent,
                          daysRemaining: secondsLeft / 86400, status: status)
    }
}
