import Foundation
import Testing
@testable import AgenticToolkitCore

/// `SubprocessTransport` is the MCP `Transport` adaptor over
/// `SubprocessChannel`. These tests drive a real child (`/bin/cat`, `/bin/sh`)
/// rather than a fake channel: the whole point of the adaptor is the wiring
/// between a live process and the SDK's `Data`-in/`Data`-out contract, and a
/// fake would only test the fake.
///
/// Every wait is bounded by `withWallClockBudget` so a regression that stops
/// producing fails the test instead of hanging the suite.
@Suite("SubprocessTransport")
struct SubprocessTransportTests {

    private static let boundedWaitSeconds: TimeInterval = 5

    private func makeTransport(
        executable: String,
        arguments: [String] = []
    ) -> SubprocessTransport {
        SubprocessTransport(
            configuration: SubprocessChannel.Configuration(
                executableURL: URL(fileURLWithPath: executable),
                arguments: arguments,
                environmentPolicy: .mergeOverParent,
                framing: .newlineDelimited
            )
        )
    }

    /// Collects frames from `stream` until `count` have arrived, bounded so a
    /// transport that stops producing fails fast.
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

    private func newlineTerminated(_ text: String) -> Data {
        Data(text.utf8) + Data([0x0A])
    }

    /// The round trip the MCP SDK actually performs: a JSON-RPC message goes
    /// out through `send`, the child echoes it, and it comes back out of
    /// `receive` **with its newline delimiter still attached**. The SDK's JSON
    /// decoder tolerates the trailing whitespace, and keeping the byte is what
    /// makes the frame identical to what the wire carried.
    @Test("a JSON message round-trips through send/receive with its newline delimiter")
    func jsonMessageRoundTrips() async throws {
        let transport = makeTransport(executable: "/bin/cat")
        try await transport.connect()
        let stream = await transport.receive()

        let request = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        try await transport.send(Data(request.utf8))

        let frames = try await collectFrames(from: stream, count: 1)
        #expect(frames == [newlineTerminated(request)])

        await transport.disconnect()
    }

    /// Two messages in a row must arrive as two frames, in order — the framing
    /// decoder is stateful, and a regression that coalesced or reordered would
    /// break every multi-response MCP session.
    @Test("successive messages arrive as separate frames in order")
    func successiveMessagesArriveInOrder() async throws {
        let transport = makeTransport(executable: "/bin/cat")
        try await transport.connect()
        let stream = await transport.receive()

        let first = #"{"id":1}"#
        let second = #"{"id":2}"#
        try await transport.send(Data(first.utf8))
        try await transport.send(Data(second.utf8))

        let frames = try await collectFrames(from: stream, count: 2)
        #expect(frames == [newlineTerminated(first), newlineTerminated(second)])

        await transport.disconnect()
    }

    /// `disconnect()` is the only owner of the child: `MCPClient` no longer
    /// keeps a `Process` of its own beside the transport, so if this leaks the
    /// server survives for the life of the app.
    ///
    /// `exec cat` replaces the shell in place, so the pid the shell printed is
    /// the pid of the process still running when the announcement arrives.
    @Test("disconnect stops the child process")
    func disconnectStopsTheChild() async throws {
        let transport = makeTransport(
            executable: "/bin/sh",
            arguments: ["-c", "echo $$; exec cat"]
        )
        try await transport.connect()
        let stream = await transport.receive()

        let frames = try await collectFrames(from: stream, count: 1)
        let announced = (String(bytes: frames.first ?? Data(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let childPID = try #require(pid_t(announced), "the child announces its own pid")
        #expect(kill(childPID, 0) == 0, "the child is running before disconnect")

        await transport.disconnect()

        // Polled rather than asserted once: the claim is that the child goes
        // away, not that it has gone by any particular instruction.
        var stillAlive = true
        for _ in 0..<50 where stillAlive {
            if kill(childPID, 0) != 0 && errno == ESRCH {
                stillAlive = false
            } else {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        #expect(!stillAlive, "disconnect() left the child running")
    }

    /// The SDK calls `connect()` once, but a reconnect path could call it
    /// twice. A second call must not spawn a second child or wedge the stream.
    @Test("a second connect is a no-op")
    func secondConnectIsANoOp() async throws {
        let transport = makeTransport(executable: "/bin/cat")
        try await transport.connect()
        try await transport.connect()

        let stream = await transport.receive()
        let message = #"{"id":7}"#
        try await transport.send(Data(message.utf8))

        let frames = try await collectFrames(from: stream, count: 1)
        #expect(frames == [newlineTerminated(message)])

        await transport.disconnect()
    }

    /// Mirrors the double call `MCPClient.teardown()` makes: the SDK client
    /// disconnects the transport it holds, and the client then disconnects it
    /// again to cover the window before `connect(transport:)` was reached.
    @Test("a second disconnect is a no-op")
    func secondDisconnectIsANoOp() async throws {
        let transport = makeTransport(executable: "/bin/cat")
        try await transport.connect()
        await transport.disconnect()
        await transport.disconnect()
    }
}
