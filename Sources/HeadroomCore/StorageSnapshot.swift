import Foundation

/// Capacity for the volume containing the requested path; no directory scan occurs.
public struct StorageSnapshot: Equatable, Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let volumeName: String
    public let fetchedAt: Date

    public init(totalBytes: Int64, freeBytes: Int64, volumeName: String, fetchedAt: Date) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.volumeName = volumeName
        self.fetchedAt = fetchedAt
    }

    public var isValidCapacity: Bool {
        totalBytes > 0 && freeBytes >= 0 && freeBytes <= totalBytes
    }

    /// Ordinary available space, not the reclaimable-space estimate for important usage.
    public var freeGB: Double { Double(freeBytes) / 1_000_000_000 }

    /// Shared capacity pressure: sibling APFS volumes also consume this headroom.
    public var usedPercent: Double {
        guard isValidCapacity else { return .nan }
        return Double(totalBytes - freeBytes) / Double(totalBytes) * 100
    }
}

public enum StorageReaderError: LocalizedError {
    case unavailableCapacity
    case invalidCapacity

    public var errorDescription: String? {
        switch self {
        case .unavailableCapacity: return "The volume did not provide capacity information."
        case .invalidCapacity: return "The volume returned inconsistent capacity information."
        }
    }
}

public enum StorageReader {
    public static func read(url: URL) throws -> StorageSnapshot {
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey
        ])
        guard let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacity else {
            throw StorageReaderError.unavailableCapacity
        }
        let snapshot = StorageSnapshot(
            totalBytes: Int64(total), freeBytes: Int64(free),
            volumeName: values.volumeName ?? "Storage", fetchedAt: Date()
        )
        guard snapshot.isValidCapacity else { throw StorageReaderError.invalidCapacity }
        return snapshot
    }
}
