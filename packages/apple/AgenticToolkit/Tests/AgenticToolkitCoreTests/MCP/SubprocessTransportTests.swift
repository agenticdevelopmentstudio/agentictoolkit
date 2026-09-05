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

    /// Collects everything left in `stream` until it finishes. Used after
    /// `disconnect()`, where the stream is already closed and the question is
    /// what was in it.
    private func drainToEOF(
        _ stream: AsyncThrowingStream<Data, Error>
    ) async throws -> [Data] {
        try await withWallClockBudget(Self.boundedWaitSeconds) {
            var frames: [Data] = []
            for try await frame in stream { frames.append(frame) }
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

    /// A blank stdout line must never reach the SDK. `StdioTransport` stripped
    /// the delimiter and then dropped whatever was left empty; `.newlineDelimited`
    /// keeps the delimiter, so without the filter in `connect()` a blank line
    /// arrives as a `"\n"` frame — not valid JSON, and one "Unexpected message
    /// received by client" warning per blank line. Servers that print one are
    /// not hypothetical, and this is the subsystem the on-screen acceptance
    /// check covers.
    @Test("a blank stdout line is dropped rather than yielded as a bare newline")
    func blankLinesAreNotForwarded() async throws {
        let transport = makeTransport(
            executable: "/bin/sh",
            arguments: ["-c", #"printf '{"id":1}\n\n{"id":2}\n'"#]
        )
        try await transport.connect()
        let stream = await transport.receive()

        let frames = try await collectFrames(from: stream, count: 2)
        #expect(frames == [newlineTerminated(#"{"id":1}"#), newlineTerminated(#"{"id":2}"#)])

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

    /// The transport half of `SubprocessChannel`'s graceful-shutdown
    /// guarantee. The channel deliberately keeps its pump running through the
    /// SIGTERM grace period so a server's last protocol message — a shutdown
    /// notification, on a real MCP session — still reaches the consumer, and
    /// this asserts that the guarantee survives being republished through
    /// `receive()`.
    ///
    /// What it pins, precisely: that `disconnect()` does not close
    /// `messageStream` before, or instead of, letting the frame through.
    /// Finishing the continuation ahead of `await channel.terminate()` fails
    /// this test outright. What it does **not** pin is the finer ordering
    /// question — whether `disconnect()` *awaits* the forwarding task before
    /// its own `finish()`. It cannot: `terminate()` spends up to half a second
    /// waiting out the channel's pump, and the detached forwarding task is
    /// scheduled throughout that wait, so by the time `disconnect()` resumes
    /// the frame is already buffered in `messageStream` and a later `finish()`
    /// still delivers it. The await is there for the residual case the channel
    /// cannot rule out — a frame the pump yields in the same instant
    /// `terminate()` returns — and that case is argued in `disconnect()`, not
    /// tested here.
    @Test("disconnect delivers the frame a graceful child writes on its way out")
    func disconnectDeliversTheChildsFinalFrame() async throws {
        let transport = makeTransport(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "trap 'sleep 0.05; echo BYE; exit 0' TERM; "
                    + "echo UP; while :; do sleep 0.05; done"
            ]
        )
        try await transport.connect()
        let stream = await transport.receive()
        // Let the trap be installed and `UP` be written before signalling.
        try await Task.sleep(for: .milliseconds(500))

        await transport.disconnect()

        let frames = try await drainToEOF(stream)
        let text = frames.compactMap { String(bytes: $0, encoding: .utf8) }.joined()
        #expect(text.contains("UP"))
        #expect(
            text.contains("BYE"),
            "the shutdown frame written during the grace period never reached receive()"
        )
    }

    /// The connect/disconnect race. `connect()` suspends at
    /// `await channel.launch()`, which releases this actor: the child is
    /// spawned during that suspension, but nothing yet records that the
    /// transport owns one. A `disconnect()` that lands in the window must
    /// still stop the child.
    ///
    /// The probe is **probabilistic by construction**, and the shape of the
    /// margin is what makes it trustworthy rather than the absence of one.
    /// `launch()` is synchronous once it reaches the channel actor, so the
    /// suspension lasts a `posix_spawn` — on the order of a millisecond. The
    /// steps below that have to fall inside it are actor hops, on the order of
    /// microseconds. Three orders of magnitude is the whole margin; there is
    /// no lock that can be taken from outside the actor to make it exact
    /// without adding a test-only hook to production code.
    ///
    /// The child is found with `pgrep -f` on a marker in its `argv` rather
    /// than by a pid it prints, because with the fix in place it is killed
    /// before it can print anything. Reaching the assertion at all requires
    /// `connect()` to have returned without throwing, which is what proves
    /// there was a real child to leak.
    @Test("a disconnect during a still-suspended connect stops the child")
    func disconnectDuringConnectStopsTheChild() async throws {
        let marker = "SubprocessTransportRaceProbe-\(UUID().uuidString)"
        let transport = makeTransport(
            executable: "/bin/sh",
            arguments: ["-c", "while :; do sleep 0.05; done", marker]
        )

        let started = StartFlag()
        let connecting = Task {
            started.set()
            try await transport.connect()
        }
        // The task body has been entered, so `connect()` is at most a few
        // instructions from the actor. Yielding rather than sleeping keeps
        // this from eating the window it is waiting for.
        while !started.isSet { await Task.yield() }

        // Each hop enters this actor, so each can only run while `connect()`
        // is suspended — and its only suspension before it claims the
        // connection is `await channel.launch()`. Several rather than one so a
        // single scheduling quirk cannot land outside the window unnoticed.
        for _ in 0..<16 { _ = await transport.receive() }

        await transport.disconnect()
        try await connecting.value

        var survivors = try Self.processesMatching(marker)
        for _ in 0..<50 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            survivors = try Self.processesMatching(marker)
        }
        // Kill before asserting: a failure here means a real orphan, and
        // leaving it running would outlive the whole test run.
        for pid in survivors { kill(pid, SIGKILL) }
        #expect(
            survivors.isEmpty,
            "disconnect() during a suspended connect() left the child running (pids \(survivors))"
        )
    }

    /// The pids whose full command line contains `marker`. `pgrep` never
    /// matches itself, so the marker in its own `argv` is not a false hit.
    private static func processesMatching(_ marker: String) throws -> [pid_t] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", marker]
        let output = Pipe()
        pgrep.standardOutput = output
        pgrep.standardError = Pipe()
        try pgrep.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        return (String(bytes: data, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// A one-way flag shared with a detached task. `NSLock` rather than
    /// `Mutex` because this package still deploys below macOS 15.
    private final class StartFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }
        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
