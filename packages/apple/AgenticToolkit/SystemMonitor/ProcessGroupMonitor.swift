import Foundation
import Synchronization

/// The memory and CPU of a group of processes together — all of Docker, all
/// of Ollama — measured against the whole machine.
///
/// CPU is a rate, so it needs two samples: the first reports memory only, and
/// a process that appeared since the last sample counts from its next one.
public final class ProcessGroupMonitor: SystemMonitor {

    public static let defaultCPUThresholds = MonitorThresholds(warning: 0.50, critical: 0.80)
    public static let defaultMemoryThresholds = MonitorThresholds(warning: 0.25, critical: 0.50)

    public let id: String
    public let title: String
    public let matcher: ProcessMatcher
    /// Applied to the share of every core the group is using.
    public let cpuThresholds: MonitorThresholds
    /// Applied to the share of physical memory the group holds.
    public let memoryThresholds: MonitorThresholds

    private let physicalMemory: UInt64
    private let coreCount: Int
    private let processes: @Sendable () -> [ProcessSample]
    private let openFiles: @Sendable (Int32) -> [String]
    private let clock: @Sendable () -> UInt64

    private struct Previous {
        let cpuByPID: [Int32: UInt64]
        let sampledAt: UInt64
    }
    private let previous = Mutex<Previous?>(nil)

    public init(
        id: String,
        title: String,
        matcher: ProcessMatcher,
        cpuThresholds: MonitorThresholds = ProcessGroupMonitor.defaultCPUThresholds,
        memoryThresholds: MonitorThresholds = ProcessGroupMonitor.defaultMemoryThresholds,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        coreCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        processes: @escaping @Sendable () -> [ProcessSample] = ProcessTable.snapshot,
        openFiles: @escaping @Sendable (Int32) -> [String] = ProcessTable.openFilePaths,
        clock: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.id = id
        self.title = title
        self.matcher = matcher
        self.cpuThresholds = cpuThresholds
        self.memoryThresholds = memoryThresholds
        self.physicalMemory = physicalMemory
        self.coreCount = max(coreCount, 1)
        self.processes = processes
        self.openFiles = openFiles
        self.clock = clock
    }

    public static func docker() -> ProcessGroupMonitor {
        ProcessGroupMonitor(id: "docker", title: "Docker", matcher: .docker)
    }

    public static func ollama() -> ProcessGroupMonitor {
        ProcessGroupMonitor(id: "ollama", title: "Ollama", matcher: .ollama)
    }

    public func sample() -> MonitorReading {
        let members = processes().filter { matcher.matches($0, openFiles: openFiles) }
        let now = clock()
        let cpuByPID = Dictionary(members.map { ($0.pid, $0.cpuTimeNanoseconds) }, uniquingKeysWith: max)
        let before = previous.withLock { previous in
            defer { previous = Previous(cpuByPID: cpuByPID, sampledAt: now) }
            return previous
        }

        guard !members.isEmpty else {
            return MonitorReading(id: id, title: title, level: .normal, value: "Not running")
        }

        let resident = members.reduce(UInt64(0)) { $0 + $1.residentBytes }
        let memoryFraction = physicalMemory > 0 ? Double(resident) / Double(physicalMemory) : 0
        let cpuFraction = before.flatMap { cpuShare(since: $0, now: now, cpuByPID: cpuByPID) }

        var level = memoryThresholds.level(for: memoryFraction)
        if let cpuFraction { level = max(level, cpuThresholds.level(for: cpuFraction)) }

        var value = MonitorFormat.bytes(resident)
        if let cpuFraction { value += " · \(MonitorFormat.percent(cpuFraction)) CPU" }
        let noun = members.count == 1 ? "process" : "processes"
        return MonitorReading(
            id: id,
            title: title,
            level: level,
            value: value,
            detail: "\(members.count) \(noun) · \(MonitorFormat.percent(memoryFraction)) of memory",
            // The gauge shows whichever of the two is pressing harder.
            fraction: max(memoryFraction, cpuFraction ?? 0)
        )
    }

    /// The share of every core the group used since `before`. Processes new
    /// since then, and ones whose CPU time went backwards (a reused pid), add
    /// nothing this time.
    private func cpuShare(since before: Previous, now: UInt64, cpuByPID: [Int32: UInt64]) -> Double? {
        guard now > before.sampledAt else { return nil }
        let used = cpuByPID.reduce(UInt64(0)) { total, entry in
            guard let earlier = before.cpuByPID[entry.key], entry.value >= earlier else { return total }
            return total + (entry.value - earlier)
        }
        let available = Double(now - before.sampledAt) * Double(coreCount)
        return min(Double(used) / available, 1)
    }
}
