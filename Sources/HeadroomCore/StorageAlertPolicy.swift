import Foundation

/// Persist after every observation and delivery result. Only accepted submissions latch.
public struct StorageAlertPolicy: Codable, Equatable, Sendable {
    public private(set) var isLatched: Bool
    public private(set) var recoveryReadCount: Int
    public private(set) var deliveryAttempts = 0
    public private(set) var retryAfter: Date?
    public private(set) var pendingAttemptID: UUID?
    public var retriesExhausted: Bool { !isLatched && deliveryAttempts >= 3 && pendingAttemptID == nil }

    public init(isLatched: Bool = false, recoveryReadCount: Int = 0) {
        self.isLatched = isLatched
        self.recoveryReadCount = isLatched ? min(max(recoveryReadCount, 0), 1) : 0
    }

    // Old saved episodes remain latched. In-flight work is never restored as running.
    private enum CodingKeys: String, CodingKey { case isLatched, recoveryReadCount, deliveryAttempts, retryAfter }
    public init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        isLatched = try saved.decode(Bool.self, forKey: .isLatched)
        deliveryAttempts = min(3, max(0, try saved.decodeIfPresent(Int.self, forKey: .deliveryAttempts) ?? 0))
        recoveryReadCount = min(1, max(0, try saved.decode(Int.self, forKey: .recoveryReadCount)))
        retryAfter = try saved.decodeIfPresent(Date.self, forKey: .retryAfter)
        pendingAttemptID = nil
    }

    /// Reserves at most three attempts per episode, at least 60 seconds apart.
    /// Pass false when recording recovery without requesting a delivery.
    @discardableResult
    public mutating func observe(usedPercent: Double, notificationsEnabled: Bool = true, now: Date = Date()) -> Bool {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else {
            recordFailure(); return false
        }
        if usedPercent >= 95 {
            recoveryReadCount = 0
            guard notificationsEnabled, !isLatched, pendingAttemptID == nil,
                  deliveryAttempts < 3, retryAfter.map({ now >= $0 }) ?? true else { return false }
            deliveryAttempts += 1
            retryAfter = now.addingTimeInterval(60)
            pendingAttemptID = UUID()
            return true
        }
        guard isLatched || deliveryAttempts > 0 else { recoveryReadCount = 0; return false }
        if usedPercent < 94 {
            recoveryReadCount += 1
            if recoveryReadCount >= 2 { self = StorageAlertPolicy() }
        } else { recoveryReadCount = 0 }
        return false
    }

    /// Ignore results from an episode that has already recovered.
    public mutating func completeDelivery(attemptID: UUID, succeeded: Bool) {
        guard pendingAttemptID == attemptID else { return }
        pendingAttemptID = nil
        if succeeded { isLatched = true }
    }

    public mutating func recordFailure() { recoveryReadCount = 0 }
}
