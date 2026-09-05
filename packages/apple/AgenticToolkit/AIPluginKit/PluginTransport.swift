import AgenticToolkitCore
import Foundation

/// Drives one `AIRequestSpec` to completion and streams the decoded
/// `AIStreamEvent`s, regardless of whether the plugin chose HTTP or a local
/// subprocess. The plugin *describes* the request and *decodes* the bytes; this
/// type owns the actual I/O — it is the one place in the system that performs
/// networking or spawns a process.
///
/// The decoder (`AIPlugin.makeDecoder`) is created *inside* the streaming task:
/// it is not `Sendable` and holds per-response parsing state, so it must never
/// be shared. The plugin itself is `Sendable`, so capturing it is safe.
public enum PluginTransport {

    /// A provider-level failure raised after the plugin described the request:
    /// a non-2xx HTTP response, a non-zero subprocess exit, or the request
    /// exceeding its wall-clock budget. The message is the plugin's own
    /// `describeError` text when it offers one, else a generic fallback.
    public enum TransportError: Error, LocalizedError {
        case http(status: Int, message: String)
        case commandFailed(status: Int32, message: String)
        case invalidResponse
        case timedOut(after: TimeInterval)

        public var errorDescription: String? {
            switch self {
            case .http(_, let message): return message
            case .commandFailed(_, let message): return message
            case .invalidResponse: return "The server returned an invalid response."
            case .timedOut(let seconds):
                return "The request exceeded its \(String(format: "%g", seconds))s budget."
            }
        }
    }

    /// Performs `spec` and streams decoded events. Cancelling the consuming task
    /// cancels the underlying transfer or terminates the subprocess.
    /// `spec.timeout` is enforced as a WALL-CLOCK bound on the whole request, per
    /// its contract — `URLRequest.timeoutInterval` alone is an idle timeout that
    /// resets on every byte, so a trickling response would never end.
    public static func run(spec: AIRequestSpec, plugin: any AIPlugin) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withWallClockBudget(spec.timeout) {
                        switch spec.transport {
                        case let .http(method, url, headers, body):
                            try await runHTTP(
                                method: method, url: url, headers: headers, body: body,
                                timeout: spec.timeout, plugin: plugin, into: continuation
                            )
                        case let .command(executableURL, arguments, stdin, environment):
                            try await runCommand(
                                executableURL: executableURL, arguments: arguments,
                                stdin: stdin, environment: environment,
                                plugin: plugin, into: continuation
                            )
                        }
                    }
                    continuation.finish()
                } catch let expired as WallClockBudgetExceeded {
                    // The budget is `AgenticToolkitCore`'s now, but the error
                    // vocabulary of this module is public: mapping here keeps
                    // `TransportError.timedOut` the thing callers and tests
                    // match on, and keeps `WallClockBudgetExceeded` out of
                    // `AIPluginKit`'s API.
                    continuation.finish(throwing: TransportError.timedOut(after: expired.seconds))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - HTTP

    private static func runHTTP(
        method: AIRequestSpec.Method,
        url: URL,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval,
        plugin: any AIPlugin,
        into continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TransportError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            // Drain the body so the plugin can describe the error.
            var errorBody = Data()
            for try await byte in bytes { errorBody.append(byte) }
            let message = plugin.describeError(status: http.statusCode, body: errorBody)
                ?? "HTTP \(http.statusCode)"
            throw TransportError.http(status: http.statusCode, message: message)
        }

        try await pump(bytes: bytes, through: plugin.makeDecoder(), into: continuation)
    }

    // MARK: - Command

    /// Runs the child through `SubprocessChannel` and feeds its
    /// newline-delimited stdout to the plugin's decoder.
    ///
    /// The frame sequence the decoder sees is byte-for-byte what the old
    /// hand-rolled byte pump produced: `.newlineDelimited` frames keep their
    /// trailing `0x0A`, and a child that writes an unterminated last fragment
    /// and exits still delivers that fragment as a final frame, because the
    /// channel flushes its framing decoder at a genuine end of the child's
    /// output. Losing those newlines is not a subtle regression — a plain-text
    /// reply arrives as one run-on paragraph.
    ///
    /// Cancellation — the consumer went away, or the wall-clock budget
    /// lapsed — terminates the child eagerly, and the channel owns that: when
    /// the task iterating the frame stream is cancelled, the stream's
    /// termination cancels the channel's own pump, whose cancellation handler
    /// signals the child. There is deliberately no second cancellation handler
    /// here.
    private static func runCommand(
        executableURL: URL,
        arguments: [String],
        stdin: Data?,
        environment: [String: String],
        plugin: any AIPlugin,
        into continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        let channel = SubprocessChannel(
            configuration: SubprocessChannel.Configuration(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                // `.replace`, not a merge: a non-empty environment becomes the
                // child's whole environment and an empty one inherits the
                // parent's, which is exactly what the `Process` code this
                // replaces did. A plugin handing over a minimal environment is
                // isolating its child on purpose.
                environmentPolicy: .replace,
                framing: .newlineDelimited
            )
        )

        try await channel.launch()
        do {
            // `sendRaw`, not `send`: the prompt is an opaque payload with no
            // message boundary to declare, and framing it would append a
            // newline the child never received before. Closing stdin is what
            // lets the child see EOF and finish.
            if let stdin { try await channel.sendRaw(stdin) }
            await channel.closeInput()

            let frames = try await channel.messages()
            let decoder = plugin.makeDecoder()
            for try await frame in frames {
                for event in decoder.consume(frame) { continuation.yield(event) }
            }
            // Before `finish()`, not after: a cancelled run produced no answer,
            // and the old byte pump likewise never reached its `finish()` once
            // cancellation cut the loop short.
            try Task.checkCancellation()
            for event in decoder.finish() { continuation.yield(event) }

            let status = await channel.waitUntilExit()
            // Releases the descriptors and, for a child whose stderr a
            // backgrounded grandchild still holds open, ends the drain — so
            // the capture below is complete rather than a bounded snapshot.
            await channel.terminate()
            guard status == 0 else {
                let errorBody = Data(await channel.standardErrorText().utf8)
                let message = plugin.describeError(status: Int(status), body: errorBody)
                    ?? "Command exited with status \(status)"
                throw TransportError.commandFailed(status: status, message: message)
            }
        } catch {
            // The `defer { process.terminate() }` this replaces, spelled out:
            // `defer` cannot `await`, and terminating the channel is async.
            //
            // The cost of this line, stated plainly, because it is paid on the
            // two paths a caller notices. `terminate()` is deliberately not
            // cancellable — it runs its SIGTERM grace period, escalates to
            // SIGKILL, and waits out the message pump's drain — so a cancelled
            // or timed-out run does not return the instant it is cancelled: it
            // returns up to `terminationGraceSeconds + messagePumpDrainGrace`
            // (2.5 s today) later, and `run`'s `.timedOut` mapping above
            // surfaces after that delay rather than at the budget boundary.
            //
            // That is the trade, and it is the right way round. The
            // alternative is abandoning a half-killed child: a plugin's
            // subprocess left running with its descriptors held, which for a
            // menu-bar app that stays resident for days accumulates. Paying a
            // bounded wait once, on the way out of a run that already failed,
            // buys the guarantee that no `.command` plugin ever leaks a
            // process.
            //
            // The success path does not pay it. There, `waitUntilExit()` has
            // already returned, so the child is gone before `terminate()` is
            // reached and the grace period is never entered — the call
            // degenerates to closing descriptors.
            await channel.terminate()
            throw error
        }
    }

    // MARK: - Byte pump

    /// Accumulates a byte stream into newline-terminated frames and feeds each to
    /// the decoder, yielding whatever events come back. Line-oriented wire
    /// formats (SSE, JSONL) decode a frame per newline; the decoder buffers any
    /// partial trailing frame itself, so the final remainder plus `finish()` flush
    /// anything left over.
    ///
    /// HTTP only. The command transport frames its child's stdout with
    /// `SubprocessChannel`'s `MessageFramingDecoder` instead — same frame
    /// boundaries, same retained trailing `0x0A`, but chunk-at-a-time rather
    /// than byte-at-a-time.
    private static func pump<Bytes: AsyncSequence>(
        bytes: Bytes,
        through decoder: any AIStreamDecoder,
        into continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws where Bytes.Element == UInt8 {
        var line = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            line.append(byte)
            if byte == 0x0A {
                for event in decoder.consume(line) { continuation.yield(event) }
                line.removeAll(keepingCapacity: true)
            }
        }
        if !line.isEmpty {
            for event in decoder.consume(line) { continuation.yield(event) }
        }
        for event in decoder.finish() { continuation.yield(event) }
    }
}
