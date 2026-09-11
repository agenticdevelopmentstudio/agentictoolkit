import AgenticToolkitCore
import Foundation
import Testing
@testable import AgenticToolkitLanguage

/// Pins the two orderings in which a `stop()` racing an in-flight `start()`
/// used to kill the host process or lose the child.
///
/// These live in their own suite type — not in `LanguageServerSessionTests` —
/// for two reasons. They sweep an offset over many iterations rather than
/// asserting a single outcome, so they are slower than everything else; and the
/// defect one of them pins is **process-fatal**, so a regression takes the
/// whole test bundle down with it rather than reporting a failure. Being able
/// to name this type alone to `-only-testing:` is what makes that readable.
/// (Name the *type*, never the `@Suite` display name: a display name matches
/// zero tests and still reports success.)
///
/// `.serialized` because both spawn real children and both depend on wall-clock
/// orderings; run in parallel they would compete for what they measure.
@Suite("LanguageServerSession stop/start race", .serialized)
struct LanguageServerSessionRaceTests {

    /// Short so a swept iteration is cheap: the child below never answers, so
    /// this is what bounds each `start()`. The production default is 30 s,
    /// sized for a cold `sourcekit-lsp` indexing a large package.
    private static let initializeBudget: TimeInterval = 0.1
    private static let shutdownBudget: TimeInterval = 0.1

    /// The offset between `Task { start() }` and `await stop()`, cycled per
    /// iteration.
    ///
    /// Tens of microseconds, not milliseconds: the offset only has to put
    /// `stop()` inside `start()`'s first suspension. Everything the race then
    /// turns on — when `Process.run()` returns, when `initialize` reaches the
    /// write path, when the child's stdout stream finishes unwinding — happens
    /// milliseconds later and is what actually varies from iteration to
    /// iteration.
    private static let offsetsMicroseconds = 40

    /// Never reads stdin, never writes stdout, and outlives the whole suite.
    ///
    /// `exec` matters twice. It makes the recorded `$$` the pid of the process
    /// that actually receives the signal, rather than a shell whose `sleep`
    /// would be a grandchild — and `SubprocessChannel.terminate()` documents
    /// that it signals the direct child only, so without `exec` a survivor
    /// would prove nothing about this session. And a child that neither reads
    /// nor writes is what keeps `initialize` outstanding, which is the state
    /// `stop()` has to be safe against.
    private static func sleepingScript(markerPath: String?) -> String {
        guard let markerPath else { return "exec sleep 60" }
        return """
        printf '%s' $$ > '\(markerPath)'
        exec sleep 60
        """
    }

    private func makeSession(script: String) -> LanguageServerSession {
        LanguageServerSession(configuration: .init(
            name: "Race",
            languageIds: ["swift"],
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            initializeBudgetSeconds: Self.initializeBudget,
            shutdownBudgetSeconds: Self.shutdownBudget
        ))
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    // MARK: - HIGH-1

    /// A `stop()` landing while `start()` is still in flight must not kill the
    /// host process.
    ///
    /// The shape is exactly the one `LanguageServerRegistry.reconcile`
    /// produces — an unstructured `Task { try await session.start() }` and a
    /// plain `await session.stop()` arriving from another path a moment later —
    /// and it is deliberately *uninstrumented*: no budget wrapper around
    /// `stop()`, no logging inside the loop. Both add scheduling of their own,
    /// and the window this pins is measured in actor hops.
    ///
    /// What it catches: tearing the transport down beside an in-flight
    /// `initialize`. `JSONRPCSession` registers the request's responder and
    /// then writes from an unstructured task; `encodeAndWrite` checks
    /// `channelClosed`, encodes, and only then hops — through the data
    /// channel's write handler and onto the `SubprocessChannel` actor — to do
    /// the write. If the child's stdout stream finishes during those hops, the
    /// session drains every responder with `dataStreamClosed`; the write then
    /// lands on the stdin `terminate()` has already closed, fails, and calls
    /// the *same* responder a second time. Two resumes of one
    /// `CheckedContinuation` is `SWIFT TASK CONTINUATION MISUSE`, which is a
    /// `fatalError`: it does not fail a test, it destroys the process, and in
    /// the app it destroys the app.
    ///
    /// A regression therefore shows up as a crashed test bundle rather than a
    /// recorded issue. The `#expect`s below are the cheap part; surviving the
    /// loop is the assertion.
    @Test("stop() during an in-flight start does not crash the process")
    func stopDuringStartIsNotFatal() async throws {
        for iteration in 0..<400 {
            let session = makeSession(script: Self.sleepingScript(markerPath: nil))
            let starter = Task { try? await session.start() }

            let offset = iteration % Self.offsetsMicroseconds
            if offset > 0 { try? await Task.sleep(for: .microseconds(offset)) }

            await session.stop()
            _ = await starter.result

            let state = await session.state
            switch state {
            case .stopped, .failed: break
            case .idle, .starting, .running:
                Issue.record("expected a terminal state at iteration \(iteration), got \(state)")
            }
        }
    }

    // MARK: - HIGH-2

    /// A `stop()` landing before `SubprocessChannel.launch()` has spawned must
    /// still leave no child behind, and must return.
    ///
    /// What it catches, first: reading "the channel is published" as "the child
    /// is reapable". `SubprocessChannel.terminate()` guards on the channel's
    /// own `hasLaunched` and does nothing whatsoever before the spawn — it
    /// leaves no barrier — so a `launch()` that completes afterwards still
    /// forks a child, and by then `stop()` has finished and nothing will ever
    /// kill it. The window is real because `LanguageServerChannel.connect` is
    /// nonisolated: calling it releases the session actor *before* `launch()`
    /// is enqueued, so a `stop()` waiting on that actor gets to run its
    /// `terminate()` against a channel that has not spawned yet.
    ///
    /// The child records its own pid and the assertion is made against the
    /// live process, because that is exactly what a leak of this shape leaves
    /// unchanged: session state ends `.stopped` either way.
    ///
    /// What it catches, second: the hang from the same window. If the resumed
    /// `start()` publishes `bridge` while `teardown()` sits between
    /// `terminate()` and `drain()`, `drain()` waits on a forwarding task over a
    /// channel that was never terminated, and `stop()` never returns —
    /// wedging `LanguageServerRegistry.stopAll`'s task group with it. `stop()`
    /// is bounded here so that fails rather than hanging the suite.
    @Test("stop() during launch leaves no orphaned child and still returns")
    func stopDuringLaunchLeavesNoOrphan() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lsp-race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var leaked: [String] = []

        for iteration in 0..<200 {
            let marker = directory.appendingPathComponent("pid-\(iteration)")
            let session = makeSession(script: Self.sleepingScript(markerPath: marker.path))
            let starter = Task { try? await session.start() }

            let offset = iteration % Self.offsetsMicroseconds
            if offset > 0 { try? await Task.sleep(for: .microseconds(offset)) }

            // Generous next to every budget this session uses, and still short
            // enough that a teardown which never returns fails the test. A
            // timeout used to `return` straight out of the function, which
            // skipped the sweep below for this iteration's own child and then
            // ran the top-level `defer` — erasing the marker that records its
            // pid before anything could ever kill it. `stopTimedOut` instead
            // lets this iteration finish its sweep and only then ends the loop.
            var stopTimedOut = false
            do {
                try await withWallClockBudget(15) { await session.stop() }
            } catch {
                Issue.record("stop() did not return within 15s at iteration \(iteration): \(error)")
                stopTimedOut = true
            }

            // The abandoned start is allowed to finish: a leak is a child still
            // alive once every path that could have reaped it has run, not one
            // that is merely mid-spawn.
            _ = await starter.result
            try? await Task.sleep(for: .milliseconds(20))

            if let text = try? String(contentsOf: marker, encoding: .utf8),
               let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
               isAlive(pid) {
                // Recorded as it happens rather than tallied at the end: the other
                // half of this window is process-fatal, so a run that finds an
                // orphan may not survive to a summary.
                leaked.append("iteration \(iteration) = pid \(pid)")
                Issue.record("orphaned child at iteration \(iteration): pid \(pid)")
                // Do not leave the suite's own mess running.
                kill(pid, SIGKILL)
            }

            if stopTimedOut { break }
        }

        #expect(leaked.isEmpty, "orphaned children: \(leaked)")
    }
}
