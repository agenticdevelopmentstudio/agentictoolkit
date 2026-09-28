import Darwin
import Foundation
import Synchronization

/// How busy all the cores are together, since the previous sample.
public final class CPUMonitor: SystemMonitor {

    /// Cumulative CPU ticks since boot, summed over every core.
    public struct Ticks: Sendable, Equatable {
        public let busy: UInt64
        public let total: UInt64

        public init(busy: UInt64, total: UInt64) {
            self.busy = busy
            self.total = total
        }
    }

    public typealias Probe = @Sendable () -> Ticks?

    public static let defaultThresholds = MonitorThresholds(warning: 0.80, critical: 0.95)

    public let id: String
    public let title: String
    public let thresholds: MonitorThresholds
    private let probe: Probe
    private let coreCount: Int
    private let previous = Mutex<Ticks?>(nil)

    public init(
        id: String = "cpu",
        title: String = "CPU",
        thresholds: MonitorThresholds = CPUMonitor.defaultThresholds,
        coreCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        probe: @escaping Probe = CPUMonitor.systemTicks
    ) {
        self.id = id
        self.title = title
        self.thresholds = thresholds
        self.coreCount = coreCount
        self.probe = probe
    }

    /// The first sample measures since boot; each later one since the last.
    public func sample() -> MonitorReading {
        guard let now = probe() else { return .unavailable(id: id, title: title) }
        let before = previous.withLock { previous in
            defer { previous = now }
            return previous
        }
        let busy = now.busy &- (before?.busy ?? 0)
        let total = now.total &- (before?.total ?? 0)
        guard total > 0, now.total >= (before?.total ?? 0) else {
            return MonitorReading(
                id: id, title: title, level: .normal, value: "0% busy", detail: coreDetail, fraction: 0
            )
        }
        let fraction = Double(busy) / Double(total)
        return MonitorReading(
            id: id,
            title: title,
            level: thresholds.level(for: fraction),
            value: "\(MonitorFormat.percent(fraction)) busy",
            detail: coreDetail,
            fraction: fraction
        )
    }

    private var coreDetail: String {
        var load = [Double](repeating: 0, count: 1)
        let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        let loadText = getloadavg(&load, 1) == 1 ? "load \(load[0].formatted(oneDecimal)) · " : ""
        return "\(loadText)\(coreCount) cores"
    }

    @Sendable
    public static func systemTicks() -> Ticks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        return Ticks(busy: busy, total: busy + idle)
    }
}
