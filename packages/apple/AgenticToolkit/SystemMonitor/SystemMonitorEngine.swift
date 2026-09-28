import AgenticToolkitCore
import Foundation

/// Samples a set of monitors on a timer and holds their latest readings.
///
/// Sampling runs off the main actor; the readings, and every observer call,
/// are on it. `readings` is always one per monitor, in the monitors' order —
/// a monitor not sampled yet reads as `.pending`.
@MainActor
public final class SystemMonitorEngine {

    public typealias Observer = @MainActor ([MonitorReading]) -> Void

    /// Cancels an `observe` registration when cancelled or freed.
    @MainActor
    public final class Observation {
        private var onCancel: (@MainActor () -> Void)?

        init(onCancel: @escaping @MainActor () -> Void) {
            self.onCancel = onCancel
        }

        public func cancel() {
            onCancel?()
            onCancel = nil
        }

        isolated deinit {
            cancel()
        }
    }

    public static let defaultInterval: TimeInterval = 5

    public let monitors: [any SystemMonitor]
    public private(set) var readings: [MonitorReading]
    /// When the last refresh finished; `nil` until the first one has.
    public private(set) var lastRefreshed: Date?

    private let refresher: PeriodicRefresher
    private var observers: [UUID: Observer] = [:]

    public init(monitors: [any SystemMonitor], interval: TimeInterval = SystemMonitorEngine.defaultInterval) {
        precondition(Set(monitors.map(\.id)).count == monitors.count, "monitor ids must be unique")
        self.monitors = monitors
        self.readings = monitors.map { MonitorReading.pending(id: $0.id, title: $0.title) }
        self.refresher = PeriodicRefresher(interval: interval)
    }

    /// Disk space, memory, CPU, Docker and Ollama.
    public static func standardMonitors() -> [any SystemMonitor] {
        [
            DiskSpaceMonitor(),
            MemoryMonitor(),
            CPUMonitor(),
            ProcessGroupMonitor.docker(),
            ProcessGroupMonitor.ollama()
        ]
    }

    public var interval: TimeInterval { refresher.interval }
    public var isRunning: Bool { refresher.isRunning }

    /// Samples now, then every `interval`, until `stop()`.
    public func start() {
        refresher.start(for: self) { engine in await engine.refresh() }
    }

    public func stop() {
        refresher.stop()
    }

    /// Samples every monitor once and tells the observers.
    public func refresh() async {
        let monitors = monitors
        readings = await Task.detached(priority: .utility) {
            monitors.map { $0.sample() }
        }.value
        lastRefreshed = Date()
        for observer in observers.values { observer(readings) }
    }

    /// The worst level among the current readings.
    public var overallLevel: MonitorLevel {
        readings.map(\.level).max() ?? .unknown
    }

    /// Calls `observer` with the current readings now, and again after every
    /// refresh, until the returned observation is cancelled or freed.
    public func observe(_ observer: @escaping Observer) -> Observation {
        let key = UUID()
        observers[key] = observer
        observer(readings)
        return Observation { [weak self] in self?.observers[key] = nil }
    }
}
