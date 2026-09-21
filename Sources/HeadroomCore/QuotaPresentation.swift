import Foundation

/// Menu text and color always describe the same selected constraint.
public struct QuotaPresentation: Equatable, Sendable {
    public enum Tone: Sendable { case neutral, warning, critical }
    public let text: String
    public let accessibilityText: String
    public let tone: Tone

    public static func remainingText(_ value: Double) -> String {
        guard value.isFinite, (0...100).contains(value) else { return "—" }
        return value > 0 && value < 1 ? "<1%" : "\(Int(floor(value)))%"
    }

    public static func evaluate(_ snapshot: CodexSnapshot?, now: Date = Date()) -> Self {
        guard let q = snapshot, q.remainingPercent.isFinite, (0...100).contains(q.remainingPercent),
              (0...300).contains(now.timeIntervalSince(q.fetchedAt)),
              q.resetsAt.map({ $0 > now }) ?? true else {
            return Self(text: "—", accessibilityText: "Codex allowance unavailable", tone: .neutral)
        }
        let scope: String
        if q.windowLabel == "Weekly allowance" { scope = "7d" }
        else if q.windowLabel.hasSuffix("-hour allowance") {
            scope = q.windowLabel.replacingOccurrences(of: "-hour allowance", with: "h")
        } else if q.windowLabel.hasSuffix("-minute allowance") {
            scope = q.windowLabel.replacingOccurrences(of: "-minute allowance", with: "m")
        } else { scope = "Now" }
        let tone: Tone = q.remainingPercent == 0 ? .critical :
            (scope == "7d" && WeeklyPace.evaluate(snapshot: q, now: now)?.status == .faster ? .warning : .neutral)
        return Self(text: "\(scope) \(remainingText(q.remainingPercent))",
                    accessibilityText: "Codex \(q.windowLabel), \(q.remainingPercent > 0 && q.remainingPercent < 1 ? "less than one" : String(Int(floor(q.remainingPercent)))) percent remaining", tone: tone)
    }
}
