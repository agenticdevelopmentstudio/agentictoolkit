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
}
