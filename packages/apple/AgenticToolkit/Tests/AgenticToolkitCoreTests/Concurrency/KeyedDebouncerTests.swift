import Foundation
import Testing
@testable import AgenticToolkitCore

/// The invariant under test is the one the three hand-copies got wrong: an
/// entry leaves the debouncer on success or on an explicit `cancel`, and on
/// nothing else. Every failure test below fails against the old shape, which
/// removed the entry before running the work.
@Suite("KeyedDebouncer")
@MainActor
struct KeyedDebouncerTests {

    private static let debounce: Duration = .milliseconds(30)

    /// Long enough for the debounce and one run to have happened, short
    /// enough to keep the suite quick.
    private static let settle: Duration = .milliseconds(200)

    private enum Failure: Error { case injected }

    /// Counts calls per key and can be told to throw for a key.
    @MainActor
    private final class Recorder {
        private(set) var calls: [String] = []
        var keysThatThrow: Set<String> = []

        func run(_ key: String) throws {
            if keysThatThrow.contains(key) {
                calls.append("!\(key)")
                throw Failure.injected
            }
            calls.append(key)
        }

        func note(_ entry: String) {
            calls.append(entry)
        }

        func successes(for key: String) -> Int {
            calls.filter { $0 == key }.count
        }
    }

    // MARK: - Debouncing

    @Test("ten schedules inside the window run the work once")
    func tenSchedulesRunOnce() async throws {
        let recorder = Recorder()
        let debouncer = KeyedDebouncer<String>(debounce: Self.debounce)

        for index in 0..<10 {
            debouncer.schedule(key: "a") { recorder.note("run-\(index)") }
            try await Task.sleep(for: .milliseconds(3))
        }
        try await Task.sleep(for: Self.settle)

        #expect(recorder.calls == ["run-9"])
        #expect(debouncer.isPending(key: "a") == false)
    }

    @Test("different keys debounce independently")
    func keysAreIndependent() async throws {
        let recorder = Recorder()
        let debouncer = KeyedDebouncer<String>(debounce: Self.debounce)

        debouncer.schedule(key: "a") { try recorder.run("a") }
        debouncer.schedule(key: "b") { try recorder.run("b") }
        try await Task.sleep(for: Self.settle)

        #expect(Set(recorder.calls) == ["a", "b"])
        #expect(debouncer.pendingKeys.isEmpty)
    }

    @Test("cancel before the window elapses runs nothing and drops the entry")
    func cancelDropsTheEntry() async throws {
        let recorder = Recorder()
        let debouncer = KeyedDebouncer<String>(debounce: Self.debounce)

        debouncer.schedule(key: "a") { try recorder.run("a") }
        debouncer.cancel(key: "a")
        try await Task.sleep(for: Self.settle)

        #expect(recorder.calls.isEmpty)
        #expect(debouncer.isPending(key: "a") == false)
    }

    // MARK: - Failure keeps the work
    //
    // This is the whole reason the type exists. Every assertion in this
    // section fails against a debouncer that retires the entry before running
    // the work.

    @Test("work that throws stays pending, and the failure is reported")
    func failureStaysPending() async throws {
        let recorder = Recorder()
        var failures: [String] = []
        let debouncer = KeyedDebouncer<String>(
            debounce: Self.debounce,
            maximumRetryInterval: .seconds(30)
        ) { key, _ in failures.append(key) }

        recorder.keysThatThrow.insert("a")
        debouncer.schedule(key: "a") { try recorder.run("a") }
        try await Task.sleep(for: Self.settle)

        // Retries are on a backoff that starts at the debounce, so more than
        // one attempt may have happened inside the settle window. What is
        // asserted is that every attempt was the failing one and that nothing
        // succeeded — not how many times the backoff got to fire.
        #expect(recorder.calls.isEmpty == false)
        #expect(recorder.calls.allSatisfy { $0 == "!a" })
        #expect(recorder.successes(for: "a") == 0)
        #expect(failures.isEmpty == false)
        #expect(failures.allSatisfy { $0 == "a" })
        #expect(debouncer.isPending(key: "a"), "a failed write must leave something to retry")
        debouncer.cancel(key: "a")
    }

    @Test("a failed entry is still there for a later flush, and that flush writes it")
    func failedEntrySurvivesToALaterFlush() async throws {
        let recorder = Recorder()
        let debouncer = KeyedDebouncer<String>(debounce: Self.debounce)

        recorder.keysThatThrow.insert("a")
        debouncer.schedule(key: "a") { try recorder.run("a") }
        try await Task.sleep(for: Self.settle)
        #expect(debouncer.isPending(key: "a"))

        // The disk comes back.
        recorder.keysThatThrow.remove("a")
        await debouncer.flush(key: "a")

        #expect(recorder.successes(for: "a") == 1)
        #expect(debouncer.isPending(key: "a") == false)
    }

    @Test("flushAll answers with the keys that still failed")
    func flushAllReportsSurvivingFailures() async throws {
        let recorder = Recorder()
        let debouncer = KeyedDebouncer<String>(debounce: .seconds(60))

        recorder.keysThatThrow.insert("bad")
        debouncer.schedule(key: "good") { try recorder.run("good") }
        debouncer.schedule(key: "bad") { try recorder.run("bad") }

        let stillFailing = await debouncer.flushAll()

        #expect(stillFailing == ["bad"])
        #expect(recorder.successes(for: "good") == 1)
    }

    @Test("retry backoff is capped, so a permanently failing entry keeps retrying")
    func retryBackoffIsCapped() async throws {
        let recorder = Recorder()
        let debouncer = KeyedDebouncer<String>(
            debounce: .milliseconds(10),
            maximumRetryInterval: .milliseconds(20)
        )

        recorder.keysThatThrow.insert("a")
        debouncer.schedule(key: "a") { try recorder.run("a") }
        try await Task.sleep(for: .milliseconds(300))

        #expect(recorder.calls.count >= 3, "capped backoff should have retried several times")
        #expect(debouncer.isPending(key: "a"))
        debouncer.cancel(key: "a")
    }

    // MARK: - One run per key

    @Test("flush during a run in flight awaits it rather than starting a second")
    func flushAwaitsTheRunInFlight() async throws {
        let debouncer = KeyedDebouncer<String>(debounce: .milliseconds(10))
        let gate = Gate()

        debouncer.schedule(key: "a") { await gate.enterAndWait() }
        try await Task.sleep(for: .milliseconds(60))
        #expect(gate.entries == 1)

        let flush = Task { await debouncer.flush(key: "a") }
        try await Task.sleep(for: .milliseconds(60))
        #expect(gate.entries == 1, "flush must not start a second run beside one in flight")

        gate.open()
        await flush.value
        #expect(gate.entries == 1)
        #expect(debouncer.isPending(key: "a") == false)
    }

    @Test("scheduling newer work during a run re-arms instead of retiring the entry")
    func newerWorkDuringARunIsNotLost() async throws {
        let debouncer = KeyedDebouncer<String>(debounce: .milliseconds(10))
        let gate = Gate()
        var ran: [String] = []

        debouncer.schedule(key: "a") {
            ran.append("first")
            await gate.enterAndWait()
        }
        try await Task.sleep(for: .milliseconds(60))
        #expect(ran == ["first"])

        // The user types again while the first write is still suspended.
        debouncer.schedule(key: "a") { ran.append("second") }
        gate.open()
        try await Task.sleep(for: Self.settle)

        #expect(ran == ["first", "second"], "work scheduled during a run must still run")
        #expect(debouncer.isPending(key: "a") == false)
    }

    @Test("cancel during a run in flight does not resurrect the entry")
    func cancelDuringARunWins() async throws {
        let debouncer = KeyedDebouncer<String>(debounce: .milliseconds(10))
        let gate = Gate()

        debouncer.schedule(key: "a") { await gate.enterAndWait() }
        try await Task.sleep(for: .milliseconds(60))
        #expect(gate.entries == 1)

        debouncer.cancel(key: "a")
        gate.open()
        try await Task.sleep(for: Self.settle)

        #expect(debouncer.isPending(key: "a") == false)
    }

    /// A main-actor latch: work parks on `enterAndWait()` until `open()`.
    @MainActor
    private final class Gate {
        private(set) var entries = 0
        private var isOpen = false

        func enterAndWait() async {
            entries += 1
            while !isOpen {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        func open() {
            isOpen = true
        }
    }
}
