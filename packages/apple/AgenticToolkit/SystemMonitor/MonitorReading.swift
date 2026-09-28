import Foundation

/// How worried a reading says to be. Ordered, so the worst of several is `max`.
public enum MonitorLevel: Int, Sendable, Comparable, CaseIterable {
    /// Not sampled yet, or the probe could not read the system.
    case unknown
    case normal
    case warning
    case critical

    public static func < (lhs: MonitorLevel, rhs: MonitorLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One monitor's answer at one moment: what it measured, said for a person,
/// and how bad that is.
public struct MonitorReading: Sendable, Equatable, Identifiable {
    /// The monitor's `id`, so a reading can be matched to the row showing it.
    public let id: String
    public let title: String
    public let level: MonitorLevel
    /// The headline — "15.3 GB free", "37% busy".
    public let value: String
    /// The supporting line — "1.7% of 926.4 GB", "7 processes".
    public let detail: String
    /// How full or busy, 0...1, for a gauge. `nil` when there is nothing to fill.
    public let fraction: Double?
    public let sampledAt: Date

    public init(
        id: String,
        title: String,
        level: MonitorLevel,
        value: String,
        detail: String = "",
        fraction: Double? = nil,
        sampledAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.level = level
        self.value = value
        self.detail = detail
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.sampledAt = sampledAt
    }

    /// The reading a monitor shows before its first sample lands.
    public static func pending(id: String, title: String) -> MonitorReading {
        MonitorReading(id: id, title: title, level: .unknown, value: "Waiting…")
    }

    /// The reading a monitor gives when its probe fails.
    public static func unavailable(id: String, title: String, detail: String = "") -> MonitorReading {
        MonitorReading(id: id, title: title, level: .unknown, value: "Unavailable", detail: detail)
    }
}
