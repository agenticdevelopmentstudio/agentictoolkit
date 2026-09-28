import Darwin
import Foundation

/// Memory in use and the kernel's memory-pressure verdict.
///
/// The level comes from the pressure the kernel reports, not from how full
/// RAM is: macOS keeps RAM full on purpose, so "95% used" is normal, while
/// pressure is what says the machine has started to struggle.
public struct MemoryMonitor: SystemMonitor {

    public enum Pressure: Sendable, Equatable {
        case normal, warning, critical

        var level: MonitorLevel {
            switch self {
            case .normal: .normal
            case .warning: .warning
            case .critical: .critical
            }
        }

        var label: String {
            switch self {
            case .normal: "normal"
            case .warning: "elevated"
            case .critical: "critical"
            }
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public let physical: UInt64
        /// What Activity Monitor calls "Memory Used": app memory + wired + compressed.
        public let used: UInt64
        public let pressure: Pressure

        public init(physical: UInt64, used: UInt64, pressure: Pressure) {
            self.physical = physical
            self.used = used
            self.pressure = pressure
        }
    }

    public typealias Probe = @Sendable () -> Snapshot?

    public let id: String
    public let title: String
    private let probe: Probe

    public init(
        id: String = "memory",
        title: String = "Memory",
        probe: @escaping Probe = MemoryMonitor.systemSnapshot
    ) {
        self.id = id
        self.title = title
        self.probe = probe
    }

    public func sample() -> MonitorReading {
        guard let snapshot = probe(), snapshot.physical > 0 else {
            return .unavailable(id: id, title: title)
        }
        return MonitorReading(
            id: id,
            title: title,
            level: snapshot.pressure.level,
            value: "\(MonitorFormat.bytes(snapshot.used)) used",
            detail: "of \(MonitorFormat.bytes(snapshot.physical)) · pressure \(snapshot.pressure.label)",
            fraction: Double(snapshot.used) / Double(snapshot.physical)
        )
    }

    @Sendable
    public static func systemSnapshot() -> Snapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        // The counts are in the host's pages (16 KB on Apple silicon), which
        // `host_page_size` reports without touching the `vm_kernel_page_size` global.
        var hostPageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS else {
            return nil
        }

        let pageSize = UInt64(hostPageSize)
        let internalPages = UInt64(stats.internal_page_count)
        let appPages = internalPages - min(UInt64(stats.purgeable_count), internalPages)
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return Snapshot(
            physical: ProcessInfo.processInfo.physicalMemory,
            used: usedPages * pageSize,
            pressure: pressureLevel()
        )
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    private static func pressureLevel() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
