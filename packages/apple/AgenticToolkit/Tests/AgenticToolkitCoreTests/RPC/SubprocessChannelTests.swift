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

    /// Polls `channel.standardErrorText()` until it contains `substring`,
    /// bounded by `boundedWaitSeconds` — the stderr drain finishes on its own
    /// task, asynchronously with respect to `waitUntilExit()` returning.
    private func waitForStandardError(
        containing substring: String,
        on channel: SubprocessChannel
    ) async throws -> String {
        try await withWallClockBudget(Self.boundedWaitSeconds) {
            while true {
                let text = await channel.standardErrorText()
                if text.contains(substring) { return text }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
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
