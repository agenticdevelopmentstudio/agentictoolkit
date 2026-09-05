import Foundation
import Testing
@testable import AgenticToolkitCore

/// Drives real processes (`/bin/cat`, `/bin/echo`, `/bin/sh -c ...`) rather
/// than a fixture binary, since those exist on every macOS machine. Every
/// test bounds its wait with `withWallClockBudget` (or a short fixed sleep
/// before cancelling) so a regression that hangs the channel fails the test
/// instead of hanging the suite.
@Suite("SubprocessChannel")
struct SubprocessChannelTests {

    private static let boundedWaitSeconds: TimeInterval = 5

    /// Collects frames from `stream` until `count` have arrived, bounded by
    /// `boundedWaitSeconds` so a channel that stops producing fails fast.
    private func collectFrames(
        from stream: AsyncThrowingStream<Data, Error>,
        count: Int
    ) async throws -> [Data] {
        try await withWallClockBudget(Self.boundedWaitSeconds) {
            var frames: [Data] = []
            for try await frame in stream {
                frames.append(frame)
                if frames.count == count { break }
            }
            return frames
        }
    }

    /// Drains `stream` to EOF (no more frames expected), bounded so a child
    /// that unexpectedly keeps the stream open fails fast rather than hangs.
    private func drainToEOF(_ stream: AsyncThrowingStream<Data, Error>) async throws -> [Data] {
        try await withWallClockBudget(Self.boundedWaitSeconds) {
            var frames: [Data] = []
            for try await frame in stream { frames.append(frame) }
            return frames
        }
    }

    /// `standardErrorText()` awaits the drain task's own completion before
    /// reading the buffer (see R4), so it is deterministic once the child
    /// has exited — no polling is needed here any more. Bounded anyway, so a
    /// regression that makes it hang again fails the test instead of the
    /// suite.
    private func waitForStandardError(
        containing substring: String,
        on channel: SubprocessChannel
    ) async throws -> String {
        try await withWallClockBudget(Self.boundedWaitSeconds) {
            await channel.standardErrorText()
        }
    }

    // MARK: - Basic I/O

    @Test("echo with arguments produces the expected frame on messages()")
    func echoWithArgumentsProducesExpectedFrame() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "world"]
        ))
        try await channel.launch()
        let stream = try await channel.messages()

        let frames = try await collectFrames(from: stream, count: 1)
        #expect(frames == [Data("hello world\n".utf8)])

        _ = await channel.waitUntilExit()
    }

    @Test("cat round-trips three sent messages back in order")
    func catRoundTripsThreeSentMessages() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/cat")
        ))
        try await channel.launch()
        let stream = try await channel.messages()

        try await channel.send(Data("one".utf8))
        try await channel.send(Data("two".utf8))
        try await channel.send(Data("three".utf8))
        await channel.closeInput()

        let frames = try await collectFrames(from: stream, count: 3)
        #expect(frames == [
            Data("one\n".utf8),
            Data("two\n".utf8),
            Data("three\n".utf8)
        ])

        await channel.terminate()
    }

    @Test("sendRaw() writes byte-exactly with no appended newline, unlike send()")
    func sendRawWritesByteExactlyWithNoAppendedNewline() async throws {
        let rawChannel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/cat")
        ))
        try await rawChannel.launch()
        let rawStream = try await rawChannel.messages()
        try await rawChannel.sendRaw(Data("abc".utf8))
        await rawChannel.closeInput()
        let rawFrames = try await collectFrames(from: rawStream, count: 1)
        #expect(rawFrames == [Data("abc".utf8)])
        await rawChannel.terminate()

        let framedChannel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/cat")
        ))
        try await framedChannel.launch()
        let framedStream = try await framedChannel.messages()
        try await framedChannel.send(Data("abc".utf8))
        await framedChannel.closeInput()
        let framedFrames = try await collectFrames(from: framedStream, count: 1)
        #expect(framedFrames == [Data("abc\n".utf8)])
        await framedChannel.terminate()
    }

    // MARK: - Lifecycle misuse

    @Test("messages() before launch() throws notLaunched")
    func messagesBeforeLaunchThrowsNotLaunched() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/cat")
        ))
        do {
            _ = try await channel.messages()
            Issue.record("expected messages() to throw before launch()")
        } catch SubprocessChannel.ChannelError.notLaunched {
            // expected
        }
    }

    @Test("a second launch() throws alreadyLaunched")
    func secondLaunchThrowsAlreadyLaunched() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/cat")
        ))
        try await channel.launch()
        do {
            try await channel.launch()
            Issue.record("expected a second launch() to throw")
        } catch SubprocessChannel.ChannelError.alreadyLaunched {
            // expected
        }
        await channel.terminate()
    }

    @Test("a second call to messages() throws alreadyConsumed — the stream is single-consumer")
    func secondMessagesCallThrowsAlreadyConsumed() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/cat")
        ))
        try await channel.launch()
        _ = try await channel.messages()
        do {
            _ = try await channel.messages()
            Issue.record("expected a second messages() call to throw")
        } catch SubprocessChannel.ChannelError.alreadyConsumed {
            // expected
        }
        await channel.terminate()
    }

    @Test("terminate() before launch() is a harmless no-op and does not disarm a later terminate()")
    func terminateBeforeLaunchDoesNotDisarmLaterTermination() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 30"]
        ))
        // Calling terminate() before launch() must not leave some
        // "already terminated" flag set that silently no-ops the real
        // terminate() below, once the child actually exists.
        await channel.terminate()

        try await channel.launch()
        await channel.terminate()

        let exitStatus = try await withWallClockBudget(3) {
            await channel.waitUntilExit()
        }
        #expect(exitStatus != 0)
    }

    // MARK: - Exit status and stderr

    @Test("a child writing to stderr and exiting non-zero reports both")
    func childWritingStderrAndExitingNonZeroReportsBoth() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo boom >&2; exit 3"]
        ))
        try await channel.launch()
        let stream = try await channel.messages()

        // This script writes nothing to stdout; drain to EOF so the stream
        // finishes before we check the exit status.
        _ = try await drainToEOF(stream)

        let status = await channel.waitUntilExit()
        #expect(status == 3)

        let stderrText = try await waitForStandardError(containing: "boom", on: channel)
        #expect(stderrText.contains("boom"))
    }

    @Test("a child writing more than 64 KB to stderr is fully captured by the continuous drain")
    func childWritingMoreThan64KBToStderrIsFullyCaptured() async throws {
        // 64 KB is the drain's own read-chunk size; a one-shot read (the
        // regression this guards against) would silently truncate anything
        // past the first chunk and this test would go red.
        let lineCount = 6_000
        let script = "for i in $(seq 1 \(lineCount)); do echo \"errline-$i-0123456789\" >&2; done"
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        ))
        try await channel.launch()
        let stream = try await channel.messages()
        _ = try await drainToEOF(stream)
        _ = await channel.waitUntilExit()

        let stderrText = await channel.standardErrorText()
        #expect(stderrText.utf8.count > 64 * 1024)
        #expect(stderrText.contains("errline-1-0123456789"))
        #expect(stderrText.contains("errline-\(lineCount)-0123456789"))
    }

    // MARK: - SIGPIPE

    @Test("writing to a channel whose child has already exited throws rather than killing the test process")
    func sendAfterChildExitThrowsRatherThanKillingProcess() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 0"]
        ))
        try await channel.launch()
        let stream = try await channel.messages()
        _ = try await drainToEOF(stream)
        _ = await channel.waitUntilExit()

        // The child has exited and closed its end of the pipe; a write here
        // must surface EPIPE as a thrown Swift error (R6), not raise SIGPIPE
        // and take the whole test process down with it.
        await #expect(throws: (any Error).self) {
            try await channel.send(Data("too late".utf8))
        }
    }

    // MARK: - Termination

    @Test("terminate() on a long-lived child finishes the message stream and is safe to call twice")
    func terminateOnLongLivedChildFinishesStreamAndIsIdempotent() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/cat")
        ))
        try await channel.launch()
        let stream = try await channel.messages()

        await channel.terminate()
        await channel.terminate() // must not crash or hang

        let remaining = try await drainToEOF(stream)
        #expect(remaining.isEmpty)
    }

    @Test("cancelling the consuming task terminates the child")
    func cancellingConsumingTaskTerminatesChild() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 30"]
        ))
        try await channel.launch()
        let stream = try await channel.messages()

        let consumingTask = Task {
            for try await _ in stream {
                // This child never writes to stdout; the loop just waits.
            }
        }
        // Give the consumer a moment to actually start iterating before
        // cancelling it out from under itself.
        try await Task.sleep(nanoseconds: 200_000_000)
        consumingTask.cancel()

        // If cancellation terminated the child eagerly, this returns almost
        // immediately; the 3-second budget (far shorter than the child's
        // 30-second sleep) is what keeps a regression from hanging the test.
        let exitStatus = try await withWallClockBudget(3) {
            await channel.waitUntilExit()
        }
        #expect(exitStatus != 0)
    }

    // MARK: - Environment policy

    @Test(".mergeOverParent merges the override over the parent's environment")
    func mergeOverParentMergesOverrideOverParentEnvironment() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo \"$WHIPPET_TEST_VAR:$HOME\""],
            environment: ["WHIPPET_TEST_VAR": "hello"],
            environmentPolicy: .mergeOverParent
        ))
        try await channel.launch()
        let stream = try await channel.messages()

        let frames = try await collectFrames(from: stream, count: 1)
        let line = String(data: frames[0], encoding: .utf8) ?? ""
        #expect(line.hasPrefix("hello:"))
        let homeValue = line
            .dropFirst("hello:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!homeValue.isEmpty)

        _ = await channel.waitUntilExit()
    }

    @Test(".replace isolates the child from the parent's environment")
    func replaceIsolatesChildFromParentEnvironment() async throws {
        let channel = SubprocessChannel(configuration: .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo \"$WHIPPET_TEST_VAR:$HOME\""],
            environment: ["WHIPPET_TEST_VAR": "hello"],
            environmentPolicy: .replace
        ))
        try await channel.launch()
        let stream = try await channel.messages()

        let frames = try await collectFrames(from: stream, count: 1)
        let line = String(data: frames[0], encoding: .utf8) ?? ""
        #expect(line == "hello:\n")

        _ = await channel.waitUntilExit()
    }
}
