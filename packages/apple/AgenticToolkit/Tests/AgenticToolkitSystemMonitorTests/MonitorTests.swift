import Foundation
import Synchronization
import Testing
@testable import AgenticToolkitSystemMonitor

@Suite("MonitorThresholds")
struct MonitorThresholdsTests {

    @Test func levelsClimbAtEachThreshold() {
        let thresholds = MonitorThresholds(warning: 0.5, critical: 0.8)
        #expect(thresholds.level(for: 0.49) == .normal)
        #expect(thresholds.level(for: 0.5) == .warning)
        #expect(thresholds.level(for: 0.79) == .warning)
        #expect(thresholds.level(for: 0.8) == .critical)
        #expect(thresholds.level(for: 1.2) == .critical)
    }

    @Test func levelsOrderWorstLast() {
        #expect([MonitorLevel.critical, .unknown, .warning, .normal].max() == .critical)
        #expect(MonitorLevel.unknown < .normal)
    }
}

@Suite("MonitorReading")
struct MonitorReadingTests {

    @Test func fractionIsClampedIntoTheGauge() {
        #expect(MonitorReading(id: "a", title: "A", level: .normal, value: "", fraction: 1.7).fraction == 1)
        #expect(MonitorReading(id: "a", title: "A", level: .normal, value: "", fraction: -0.2).fraction == 0)
        #expect(MonitorReading(id: "a", title: "A", level: .normal, value: "").fraction == nil)
    }

    @Test func placeholdersAreUnknown() {
        #expect(MonitorReading.pending(id: "a", title: "A").level == .unknown)
        #expect(MonitorReading.unavailable(id: "a", title: "A").value == "Unavailable")
    }
}

@Suite("DiskSpaceMonitor")
struct DiskSpaceMonitorTests {

    private func monitor(total: UInt64, available: UInt64) -> DiskSpaceMonitor {
        DiskSpaceMonitor(probe: { _ in .init(total: total, available: available) })
    }

    @Test func aRoomyDiskIsNormal() {
        let reading = monitor(total: 1_000_000_000_000, available: 500_000_000_000).sample()
        #expect(reading.id == "disk")
        #expect(reading.level == .normal)
        #expect(reading.fraction == 0.5)
        #expect(reading.value.hasSuffix(" free"))
    }

    @Test func aFullerDiskIsWorse() {
        #expect(monitor(total: 100, available: 8).sample().level == .warning)
        #expect(monitor(total: 100, available: 4).sample().level == .critical)
    }

    @Test func moreFreeThanTotalReadsAsEmpty() {
        #expect(monitor(total: 100, available: 150).sample().fraction == 0)
    }

    @Test func aFailedProbeIsUnavailable() {
        let reading = DiskSpaceMonitor(probe: { _ in nil }).sample()
        #expect(reading.level == .unknown)
        #expect(reading.detail == DiskSpaceMonitor.dataVolume.path)
    }

    @Test func theRealDataVolumeReads() {
        #expect(DiskSpaceMonitor.volumeCapacity(DiskSpaceMonitor.dataVolume) != nil)
    }
}

@Suite("MemoryMonitor")
struct MemoryMonitorTests {

    @Test func levelFollowsTheKernelsPressureNotHowFullRAMIs() {
        let full = MemoryMonitor(probe: { .init(physical: 100, used: 99, pressure: .normal) }).sample()
        #expect(full.level == .normal)
        #expect(full.fraction == 0.99)

        let pressed = MemoryMonitor(probe: { .init(physical: 100, used: 40, pressure: .critical) }).sample()
        #expect(pressed.level == .critical)
        #expect(pressed.detail.hasSuffix("pressure critical"))
    }

    @Test func aFailedProbeIsUnavailable() {
        #expect(MemoryMonitor(probe: { nil }).sample().level == .unknown)
    }

    @Test func theRealSystemReads() throws {
        let snapshot = try #require(MemoryMonitor.systemSnapshot())
        #expect(snapshot.physical == ProcessInfo.processInfo.physicalMemory)
        #expect(snapshot.used > 0)
    }
}

@Suite("CPUMonitor")
struct CPUMonitorTests {

    @Test func eachSampleMeasuresSinceTheLast() {
        let ticks = Mutex([CPUMonitor.Ticks(busy: 10, total: 100), .init(busy: 100, total: 200)])
        let monitor = CPUMonitor(coreCount: 8, probe: { ticks.withLock { $0.removeFirst() } })

        let first = monitor.sample()
        #expect(first.fraction == 0.1)
        #expect(first.level == .normal)

        let second = monitor.sample()
        #expect(second.fraction == 0.9)
        #expect(second.level == .warning)
        #expect(second.detail.hasSuffix("8 cores"))
    }

    @Test func noTicksSinceTheLastSampleReadsIdle() {
        let monitor = CPUMonitor(probe: { .init(busy: 5, total: 50) })
        _ = monitor.sample()
        let idle = monitor.sample()
        #expect(idle.fraction == 0)
        #expect(idle.level == .normal)
    }

    @Test func aFailedProbeIsUnavailable() {
        #expect(CPUMonitor(probe: { nil }).sample().level == .unknown)
    }

    @Test func theRealSystemReads() {
        #expect(CPUMonitor.systemTicks() != nil)
    }
}

@Suite("ProcessMatcher")
struct ProcessMatcherTests {

    private func process(_ name: String, path: String = "", pid: Int32 = 1) -> ProcessSample {
        ProcessSample(pid: pid, name: name, path: path, residentBytes: 0, cpuTimeNanoseconds: 0)
    }

    @Test func dockerMatchesItsAppHelpersAndCLI() {
        let noFiles: (Int32) -> [String] = { _ in [] }
        #expect(ProcessMatcher.docker.matches(process("com.docker.backend"), openFiles: noFiles))
        let app = process("Docker Desktop", path: "/Applications/Docker.app/Contents/MacOS/Docker Desktop")
        #expect(ProcessMatcher.docker.matches(app, openFiles: noFiles))
        #expect(ProcessMatcher.docker.matches(process("docker"), openFiles: noFiles))
        #expect(!ProcessMatcher.docker.matches(process("dockerd-rootless"), openFiles: noFiles))
    }

    @Test func aVirtualMachineCountsOnlyWhenItHoldsDockersDisk() {
        let machine = process(ProcessMatcher.virtualMachineProcessName, pid: 42)
        let dockerDisk: (Int32) -> [String] = { pid in
            pid == 42 ? ["/Users/me/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"] : []
        }
        let otherDisk: (Int32) -> [String] = { _ in ["/Users/me/VMs/linux.img"] }
        #expect(ProcessMatcher.docker.matches(machine, openFiles: dockerDisk))
        #expect(!ProcessMatcher.docker.matches(machine, openFiles: otherDisk))
    }

    @Test func openFilesAreReadOnlyForVirtualMachines() {
        let asked = Mutex(false)
        let spy: (Int32) -> [String] = { _ in asked.withLock { $0 = true }; return [] }
        _ = ProcessMatcher.docker.matches(process("Safari"), openFiles: spy)
        #expect(!asked.withLock { $0 })
    }

    @Test func ollamaMatchesTheServerAndRunnersCaseInsensitively() {
        let noFiles: (Int32) -> [String] = { _ in [] }
        #expect(ProcessMatcher.ollama.matches(process("ollama"), openFiles: noFiles))
        #expect(ProcessMatcher.ollama.matches(process("Ollama"), openFiles: noFiles))
        #expect(ProcessMatcher.ollama.matches(process("ollama_llama_server"), openFiles: noFiles))
        #expect(!ProcessMatcher.ollama.matches(process("llama"), openFiles: noFiles))
    }
}

@Suite("ProcessGroupMonitor")
struct ProcessGroupMonitorTests {

    private static let gib: UInt64 = 1 << 30

    /// A process table and clock the test advances by hand.
    private final class World: Sendable {
        let processes = Mutex<[ProcessSample]>([])
        let now = Mutex<UInt64>(1_000_000_000)

        func monitor(physicalMemory: UInt64 = 16 * gib, cores: Int = 4) -> ProcessGroupMonitor {
            ProcessGroupMonitor(
                id: "ollama",
                title: "Ollama",
                matcher: .ollama,
                physicalMemory: physicalMemory,
                coreCount: cores,
                processes: { self.processes.withLock { $0 } },
                openFiles: { _ in [] },
                clock: { self.now.withLock { $0 } }
            )
        }

        func set(_ list: [ProcessSample]) { processes.withLock { $0 = list } }
        func advance(seconds: UInt64) { now.withLock { $0 += seconds * 1_000_000_000 } }
    }

    private func ollama(pid: Int32, memory: UInt64, cpuSeconds: UInt64) -> ProcessSample {
        ProcessSample(
            pid: pid, name: "ollama", path: "/usr/local/bin/ollama",
            residentBytes: memory, cpuTimeNanoseconds: cpuSeconds * 1_000_000_000
        )
    }

    @Test func nothingRunningIsNormal() {
        let world = World()
        world.set([ProcessSample(pid: 9, name: "Safari", path: "", residentBytes: 1 << 40, cpuTimeNanoseconds: 0)])
        let reading = world.monitor().sample()
        #expect(reading.value == "Not running")
        #expect(reading.level == .normal)
        #expect(reading.fraction == nil)
    }

    @Test func memoryIsSummedAcrossTheGroupAndJudgedAgainstRAM() {
        let world = World()
        world.set([
            ollama(pid: 1, memory: 3 * Self.gib, cpuSeconds: 0),
            ollama(pid: 2, memory: 2 * Self.gib, cpuSeconds: 0)
        ])
        let reading = world.monitor().sample()
        #expect(reading.level == .warning)
        #expect(reading.fraction == 5.0 / 16.0)
        #expect(reading.detail.hasPrefix("2 processes"))
        #expect(!reading.value.contains("CPU"))
    }

    @Test func cpuIsTheShareOfEveryCoreSinceTheLastSample() {
        let world = World()
        let monitor = world.monitor(cores: 4)
        world.set([ollama(pid: 1, memory: Self.gib, cpuSeconds: 10)])
        _ = monitor.sample()

        world.advance(seconds: 1)
        world.set([ollama(pid: 1, memory: Self.gib, cpuSeconds: 13)])
        let reading = monitor.sample()
        // Three core-seconds in one second on four cores.
        #expect(reading.fraction == 0.75)
        #expect(reading.level == .warning)
        #expect(reading.value.hasSuffix("75% CPU"))
    }

    @Test func aNewOrReusedPIDAddsNothingUntilItsNextSample() {
        let world = World()
        let monitor = world.monitor(cores: 1)
        world.set([ollama(pid: 1, memory: Self.gib, cpuSeconds: 50)])
        _ = monitor.sample()

        world.advance(seconds: 1)
        world.set([ollama(pid: 1, memory: Self.gib, cpuSeconds: 2), ollama(pid: 2, memory: Self.gib, cpuSeconds: 30)])
        let reading = monitor.sample()
        #expect(reading.value.hasSuffix(" 0% CPU"))
    }

    @Test func theRealProcessTableReads() {
        let table = ProcessTable.snapshot()
        #expect(table.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
    }
}

@Suite("SystemMonitorEngine")
@MainActor
struct SystemMonitorEngineTests {

    private struct Fixed: SystemMonitor {
        let id: String
        let title: String
        let level: MonitorLevel
        func sample() -> MonitorReading {
            MonitorReading(id: id, title: title, level: level, value: "\(level)")
        }
    }

    @Test func readingsStartPendingInMonitorOrder() {
        let engine = SystemMonitorEngine(monitors: [
            Fixed(id: "a", title: "A", level: .normal),
            Fixed(id: "b", title: "B", level: .critical)
        ])
        #expect(engine.readings.map(\.id) == ["a", "b"])
        #expect(engine.readings.allSatisfy { $0.level == .unknown })
        #expect(engine.lastRefreshed == nil)
        #expect(engine.overallLevel == .unknown)
    }

    @Test func refreshSamplesEveryMonitorAndTellsObservers() async {
        let engine = SystemMonitorEngine(monitors: [
            Fixed(id: "a", title: "A", level: .normal),
            Fixed(id: "b", title: "B", level: .warning)
        ])
        var seen: [[MonitorLevel]] = []
        let observation = engine.observe { seen.append($0.map(\.level)) }

        await engine.refresh()

        #expect(seen == [[.unknown, .unknown], [.normal, .warning]])
        #expect(engine.overallLevel == .warning)
        #expect(engine.lastRefreshed != nil)
        observation.cancel()
    }

    @Test func aCancelledObservationHearsNothingMore() async {
        let engine = SystemMonitorEngine(monitors: [Fixed(id: "a", title: "A", level: .normal)])
        var calls = 0
        let observation = engine.observe { _ in calls += 1 }
        observation.cancel()
        await engine.refresh()
        #expect(calls == 1)
    }

    @Test func aFreedObservationHearsNothingMore() async {
        let engine = SystemMonitorEngine(monitors: [Fixed(id: "a", title: "A", level: .normal)])
        var calls = 0
        var observation: SystemMonitorEngine.Observation? = engine.observe { _ in calls += 1 }
        #expect(observation != nil)
        observation = nil
        await engine.refresh()
        #expect(calls == 1)
    }

    @Test func startAndStopDriveTheTimer() {
        let engine = SystemMonitorEngine(monitors: [Fixed(id: "a", title: "A", level: .normal)], interval: 60)
        engine.start()
        #expect(engine.isRunning)
        engine.stop()
        #expect(!engine.isRunning)
    }

    @Test func theStandardSetIsDiskMemoryCPUDockerOllama() {
        #expect(SystemMonitorEngine.standardMonitors().map(\.id) == ["disk", "memory", "cpu", "docker", "ollama"])
    }
}
