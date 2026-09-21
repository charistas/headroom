import Foundation

public enum NotificationPermission: Sendable { case unknown, notRequested, allowed, blocked }
public enum NotificationReadiness: String, Sendable {
    case off = "Off", checking = "Checking…", enabled = "Enabled", blocked = "Blocked"
    public static func evaluate(requested: Bool, permission: NotificationPermission) -> Self {
        guard requested else { return .off }
        switch permission {
        case .unknown: return .checking
        case .allowed: return .enabled
        case .notRequested, .blocked: return .blocked
        }
    }
}
