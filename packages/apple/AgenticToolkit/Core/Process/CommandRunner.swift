//
//  CommandRunner.swift
//  AgenticToolkit
//

import Foundation

/// Runs a helper tool to completion and comes back — draining what it writes,
/// and giving up on it if it will not finish.
///
/// **Both of those are the difference between a failure and a hang.** A
/// `Process` whose output goes to a `Pipe` nothing reads stops the moment the
/// kernel's buffer fills, which is 64 KB in, and the caller waiting for it
/// stops with it: two processes, each waiting for the other, forever. And a
/// tool that simply never exits holds the calling thread for as long as it
/// feels like — which for anything handed an archive off the internet is a
/// decision made by whoever wrote the archive.
///
/// So this drains both streams as they are written and waits against a
/// deadline, and a run that reaches the deadline is terminated and reported as
/// timed out rather than thrown away *(fail-fast)*. It is the whole-output,
/// one-shot shape; a tool to hold a conversation with is `SubprocessChannel`.
///
/// `standardOutput` and `standardError` are installed here, so anything a
/// caller set on them is replaced.
public enum CommandRunner {

    /// What one run amounted to.
    public struct Outcome: Sendable, Equatable {

        /// The process's exit status. Meaningless when `timedOut` — the
        /// process was signalled, so the status describes this code's
        /// impatience rather than the tool's opinion.
        ///
        /// `neverExited` when the process outlived even `SIGKILL`, which is
        /// not hypothetical: a process blocked in an uninterruptible kernel
        /// wait — the classic one being a read against a hung network mount —
        /// cannot be killed and does not reap.
        public let status: Int32

        public let standardOutput: Data
        public let standardError: Data

        /// The run did not finish inside its timeout and was terminated.
        public let timedOut: Bool

        /// `standardError` as trimmed text — what a tool's complaint reads
        /// like when it is put in front of a person.
        public var diagnostics: String {
            (String(bytes: standardError, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public init(status: Int32, standardOutput: Data, standardError: Data, timedOut: Bool) {
            self.status = status
            self.standardOutput = standardOutput
            self.standardError = standardError
            self.timedOut = timedOut
        }
    }

    /// How long a terminated process is given to die before it is killed.
    ///
    /// A tool that ignores `SIGTERM` is exactly the tool this timeout exists
    /// for, so there has to be a second step; two seconds is long enough for
    /// an honest cleanup handler and short enough that nobody notices.
    private static let terminationGrace: TimeInterval = 2

    /// `Outcome.status` for a process that never exited at all.
    ///
    /// Distinct from any real exit status, which is 0...255 for an ordinary
    /// exit, and from a signalled one. It is only ever seen alongside
    /// `timedOut`, where the status already means nothing.
    public static let neverExited: Int32 = -1

    /// Runs `process`, returning once it has exited or `timeout` has passed.
    ///
    /// Throws only what `Process.run()` throws — a tool that is not there, or
    /// one this process is not allowed to execute. A tool that ran and failed
    /// is not an error here; it is an `Outcome` with a non-zero `status`,
    /// because what a failing helper wrote is usually the whole answer.
    public static func runToCompletion(
        _ process: Process,
        timeout: TimeInterval
    ) throws -> Outcome {
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let collected = Collector()
        let outputDrained = drain(output, into: collected, as: .standardOutput)
        let errorsDrained = drain(errors, into: collected, as: .standardError)

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            throw error
        }

        var timedOut = false
        var didExit = true
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + terminationGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                didExit = exited.wait(timeout: .now() + terminationGrace) == .success
            }
        }
        // Both write ends are closed once the process is gone, so these are
        // waits on an EOF that has already been posted — bounded anyway, in
        // case a grandchild inherited one of them.
        _ = outputDrained.wait(timeout: .now() + terminationGrace)
        _ = errorsDrained.wait(timeout: .now() + terminationGrace)
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil

        // **Only when it actually exited.** `Process.terminationStatus` is
        // documented to raise `NSInvalidArgumentException` on a process that
        // is still running, and an Objective-C exception is not catchable from
        // Swift — it is a crash, in the one path that exists to handle a tool
        // behaving badly. Surviving `SIGKILL` sounds impossible and is not:
        // a process stuck in an uninterruptible kernel wait, which is what a
        // read against a wedged network mount produces, neither dies nor
        // reaps. The timeout path is exactly where that shows up, so the
        // guard belongs exactly here *(fail-fast, not fail-crash)*.
        return Outcome(
            status: didExit ? process.terminationStatus : Self.neverExited,
            standardOutput: collected.data(for: .standardOutput),
            standardError: collected.data(for: .standardError),
            timedOut: timedOut)
    }

    // MARK: - Private

    private enum Stream {
        case standardOutput
        case standardError
    }

    /// Reads `pipe` on Foundation's reader queue until EOF, appending into
    /// `collected`, and signals the returned semaphore when EOF arrives.
    ///
    /// Draining *while* the tool writes is the point: a read that waits for
    /// the process to exit first is the deadlock this type exists to avoid.
    private static func drain(
        _ pipe: Pipe,
        into collected: Collector,
        as stream: Stream
    ) -> DispatchSemaphore {
        let finished = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                finished.signal()
                return
            }
            collected.append(chunk, to: stream)
        }
        return finished
    }

    /// The two buffers, behind one lock.
    ///
    /// Foundation delivers both streams on its own queue, so every append here
    /// is off the calling thread and the two can arrive at once.
    private final class Collector: @unchecked Sendable {

        private let lock = NSLock()
        private var buffers: [Stream: Data] = [:]

        func append(_ chunk: Data, to stream: Stream) {
            lock.withLock { buffers[stream, default: Data()].append(chunk) }
        }

        func data(for stream: Stream) -> Data {
            lock.withLock { buffers[stream] ?? Data() }
        }
    }
}
