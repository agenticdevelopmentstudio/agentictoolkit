import Foundation
import Testing
@testable import AgenticToolkitCore

/// Running a helper tool to completion, with neither of the two ways that
/// blocks forever.
///
/// Both failure modes are real and neither is hypothetical: an undrained pipe
/// stops the child dead once the kernel's buffer fills, and a child that never
/// exits stops the caller. The tests below reproduce each with a shell one
/// liner rather than asserting on the implementation, so a rewrite that keeps
/// the guarantees keeps them passing.
@Suite(.serialized)
struct CommandRunnerTests {

    private func shell(_ script: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        return process
    }

    // MARK: - Draining

    /// 200 KB is comfortably past the 64 KB a pipe holds, so a run that only
    /// reads after waiting never gets to read at all: the child blocks writing
    /// and the parent blocks waiting. This is the test that fails by hanging,
    /// which the timeout turns back into an ordinary failure.
    @Test("a command that writes more output than a pipe holds still finishes")
    func aFloodOfStandardOutputDoesNotDeadlock() throws {
        let outcome = try CommandRunner.runToCompletion(
            shell("head -c 200000 /dev/zero | tr '\\0' 'x'"), timeout: 30)

        #expect(!outcome.timedOut)
        #expect(outcome.status == 0)
        #expect(outcome.standardOutput.count == 200_000)
    }

    @Test("a command that floods standard error finishes too")
    func aFloodOfStandardErrorDoesNotDeadlock() throws {
        let outcome = try CommandRunner.runToCompletion(
            shell("head -c 200000 /dev/zero | tr '\\0' 'x' >&2"), timeout: 30)

        #expect(!outcome.timedOut)
        #expect(outcome.standardError.count == 200_000)
    }

    // MARK: - What comes back

    @Test("the exit status and the diagnostics both come back")
    func theStatusAndTheDiagnosticsComeBack() throws {
        let outcome = try CommandRunner.runToCompletion(
            shell("printf 'no such file\\n' >&2; exit 3"), timeout: 30)

        #expect(outcome.status == 3)
        #expect(outcome.diagnostics == "no such file")
        #expect(!outcome.timedOut)
        #expect(outcome.standardOutput.isEmpty)
    }

    @Test("an executable that is not there throws rather than reporting a status")
    func aMissingExecutableThrows() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/definitely-not-a-tool")

        #expect(throws: (any Error).self) {
            try CommandRunner.runToCompletion(process, timeout: 30)
        }
    }

    // MARK: - Giving up

    /// The point is that this returns at all. `sleep 30` outlives any patience
    /// a user has, and a caller that waits for it has handed its thread to a
    /// third party's archive.
    @Test("a command that will not finish is given up on, and says so")
    func aCommandThatWillNotFinishIsGivenUpOn() throws {
        let started = Date()

        let outcome = try CommandRunner.runToCompletion(shell("sleep 30"), timeout: 0.5)

        #expect(outcome.timedOut)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    /// Given up on, and *gone* — not left running with nobody waiting for it.
    @Test("a command given up on is no longer running")
    func aCommandGivenUpOnIsNoLongerRunning() throws {
        let process = shell("sleep 30")

        let outcome = try CommandRunner.runToCompletion(process, timeout: 0.5)

        #expect(outcome.timedOut)
        #expect(!process.isRunning)
    }

    /// The escalation the timeout exists for. A tool that ignores `SIGTERM` is
    /// exactly the tool the two-step teardown was written for, and nothing
    /// exercised the second step — so the `SIGKILL` path, and the status read
    /// that follows it, ran for the first time in front of a user.
    ///
    /// The status is not asserted on beyond "it came back": the process was
    /// signalled, so whatever it says describes this code's impatience. What
    /// is asserted is that a run against an unkillable-by-TERM tool *returns*,
    /// inside its budget, with `timedOut` set.
    @Test("a tool that ignores SIGTERM is killed, and the run still returns")
    func aToolThatIgnoresTerminationIsKilled() throws {
        // **`/bin/sh`, and not an interpreter, because the arming has to beat
        // the timeout.** The tool must have ignored `SIGTERM` and written its
        // line within the one second below, or the run under test is not the
        // escalation at all — it is a cold process killed on the first
        // signal, and the output assertion fails for a reason that has
        // nothing to do with this code. A `python3` here did exactly that
        // inside a full 1206-test run: interpreter start-up plus two imports
        // lost the race on a loaded machine, and the suite was green alone
        // and red in company. `sh` arms in a few milliseconds, with `trap`
        // and `echo` both builtins, so nothing is forked before the line is
        // out. The `sleep`s that keep it alive send their own output to
        // `/dev/null`, so no child holds the pipe's write end open after the
        // shell is killed and EOF arrives at once.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "trap '' TERM; echo armed; while :; do sleep 1 >/dev/null 2>&1; done"
        ]

        let started = Date()
        let outcome = try CommandRunner.runToCompletion(process, timeout: 1)
        let elapsed = Date().timeIntervalSince(started)

        #expect(outcome.timedOut)
        // 1s timeout, then SIGTERM is ignored through a 2s grace, then SIGKILL.
        // Comfortably inside the 1 + 2 + 2 budget, and well past it would mean
        // the escalation never happened.
        #expect(elapsed < 8)
        // What it managed to write before being killed is still collected —
        // the drain does not depend on a clean exit.
        #expect(outcome.diagnostics.isEmpty)
        #expect(String(bytes: outcome.standardOutput, encoding: .utf8)?
            .contains("armed") == true)
    }

    // MARK: - Giving up for a reason other than the clock

    /// The clock is the wrong limit for a tool whose damage is measured in
    /// bytes. A watchdog is how a caller enforces its own limit on something
    /// the tool does not report — an archive expanding on disk, for one — and
    /// the run has to end on it, well inside a timeout generous enough for an
    /// honest slow tool.
    @Test("a watchdog that says stop ends the run, inside the timeout")
    func aWatchdogEndsTheRun() throws {
        let started = Date()
        let calls = Counter()

        let outcome = try CommandRunner.runToCompletion(
            shell("sleep 30"),
            timeout: 30,
            watchdog: CommandRunner.Watchdog(interval: 0.1) { calls.bump() > 2 })

        #expect(outcome.aborted)
        #expect(!outcome.timedOut)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    /// Aborted is not timed out, and a caller has to be able to tell them
    /// apart: one says "your limit was reached" and the other says "the tool
    /// is wedged". Collapsing them into one flag makes both messages wrong
    /// half the time.
    @Test("the clock still reports as a timeout even with a watchdog attached")
    func aTimeoutWithAWatchdogIsStillATimeout() throws {
        let outcome = try CommandRunner.runToCompletion(
            shell("sleep 30"),
            timeout: 0.5,
            watchdog: CommandRunner.Watchdog(interval: 0.1) { false })

        #expect(outcome.timedOut)
        #expect(!outcome.aborted)
    }

    /// A watchdog that never fires must not change what an ordinary run does —
    /// including collecting its output, which the polling loop is a second
    /// path to and could easily have dropped.
    @Test("a watchdog that never fires leaves an ordinary run alone")
    func aQuietWatchdogChangesNothing() throws {
        let outcome = try CommandRunner.runToCompletion(
            shell("printf hello; exit 3"),
            timeout: 30,
            watchdog: CommandRunner.Watchdog(interval: 0.05) { false })

        #expect(!outcome.aborted)
        #expect(!outcome.timedOut)
        #expect(outcome.status == 3)
        #expect(String(bytes: outcome.standardOutput, encoding: .utf8) == "hello")
    }

    /// And a run the watchdog outlives is not signalled on the way past: the
    /// poll loop has to notice the exit rather than waiting out its interval.
    @Test("a process that exits during a poll interval is not aborted")
    func anExitDuringAPollIsNotAnAbort() throws {
        let outcome = try CommandRunner.runToCompletion(
            shell("exit 0"),
            timeout: 30,
            watchdog: CommandRunner.Watchdog(interval: 5) { true })

        #expect(!outcome.aborted)
        #expect(outcome.status == 0)
    }

    /// Counts `shouldAbort` calls across the waiting thread and this one.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() -> Int { lock.withLock { value += 1; return value } }
    }

    /// The ordinary case still reports the tool's own status, not the sentinel.
    /// A guard that read `neverExited` whenever it was unsure would turn every
    /// successful run into an unreadable one.
    @Test("a tool that exits normally reports its own status")
    func anExitingToolReportsItsOwnStatus() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 3"]

        let outcome = try CommandRunner.runToCompletion(process, timeout: 10)

        #expect(!outcome.timedOut)
        #expect(outcome.status == 3)
        #expect(outcome.status != CommandRunner.neverExited)
    }
}
