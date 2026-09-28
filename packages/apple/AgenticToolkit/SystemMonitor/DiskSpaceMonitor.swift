import Foundation

/// Free space on one volume.
///
/// Defaults to `/System/Volumes/Data`, not `/`: on APFS `/` is the sealed,
/// read-only system volume, and the space that runs out is the data volume's.
public struct DiskSpaceMonitor: SystemMonitor {

    public struct Capacity: Sendable, Equatable {
        public let total: UInt64
        public let available: UInt64

        public init(total: UInt64, available: UInt64) {
            self.total = total
            self.available = available
        }
    }

    public typealias Probe = @Sendable (URL) -> Capacity?

    public static let dataVolume = URL(fileURLWithPath: "/System/Volumes/Data")

    /// Warn under 10% free, critical under 5% — thresholds on how *full* it is.
    public static let defaultThresholds = MonitorThresholds(warning: 0.90, critical: 0.95)

    public let id: String
    public let title: String
    public let volume: URL
    /// Applied to the fraction used, so a fuller disk is a worse one.
    public let thresholds: MonitorThresholds
    private let probe: Probe

    public init(
        id: String = "disk",
        title: String = "Disk Space",
        volume: URL = DiskSpaceMonitor.dataVolume,
        thresholds: MonitorThresholds = DiskSpaceMonitor.defaultThresholds,
        probe: @escaping Probe = DiskSpaceMonitor.volumeCapacity
    ) {
        self.id = id
        self.title = title
        self.volume = volume
        self.thresholds = thresholds
        self.probe = probe
    }

    public func sample() -> MonitorReading {
        guard let capacity = probe(volume), capacity.total > 0 else {
            return .unavailable(id: id, title: title, detail: volume.path)
        }
        let available = min(capacity.available, capacity.total)
        let usedFraction = 1 - Double(available) / Double(capacity.total)
        return MonitorReading(
            id: id,
            title: title,
            level: thresholds.level(for: usedFraction),
            value: "\(MonitorFormat.diskBytes(available)) free",
            detail: "\(MonitorFormat.percent(1 - usedFraction, decimals: 1)) of "
                + MonitorFormat.diskBytes(capacity.total),
            fraction: usedFraction
        )
    }

    /// The volume's size and the space free on it right now (what `df` shows,
    /// not counting purgeable space the system might give back).
    @Sendable
    public static func volumeCapacity(_ url: URL) -> Capacity? {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values?.volumeTotalCapacity, let available = values?.volumeAvailableCapacity else {
            return nil
        }
        return Capacity(total: UInt64(max(total, 0)), available: UInt64(max(available, 0)))
    }
}
