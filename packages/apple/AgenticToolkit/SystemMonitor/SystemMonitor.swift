import Foundation

/// Something about the machine worth watching — free disk, memory pressure, a
/// process group eating the CPU.
///
/// `sample()` is synchronous and cheap (a few syscalls), and is called off the
/// main actor, one call at a time per monitor. A monitor that needs the
/// previous sample to compute a rate keeps it itself, behind a lock.
public protocol SystemMonitor: Sendable {
    /// Stable across launches; a settings key or a trigger can name it.
    var id: String { get }
    var title: String { get }
    func sample() -> MonitorReading
}

/// When a value that grows worse as it grows becomes a warning, then critical.
public struct MonitorThresholds: Sendable, Equatable {
    public let warning: Double
    public let critical: Double

    public init(warning: Double, critical: Double) {
        precondition(warning <= critical, "warning threshold must not exceed critical")
        self.warning = warning
        self.critical = critical
    }

    public func level(for value: Double) -> MonitorLevel {
        if value >= critical { return .critical }
        if value >= warning { return .warning }
        return .normal
    }
}

/// The formatting every monitor shares, so "GB" and "%" read the same in each row.
enum MonitorFormat {
    static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .memory)
    }

    static func diskBytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .file)
    }

    static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        fraction.formatted(.percent.precision(.fractionLength(decimals)))
    }
}
