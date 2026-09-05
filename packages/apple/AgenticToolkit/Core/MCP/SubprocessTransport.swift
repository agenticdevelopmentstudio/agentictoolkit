import Foundation
import Logging
import MCP
// `Errno`, for the `ENOTCONN` that `send()` throws when there is no child.
// `StdioTransport` reaches for the same type from the same module.
import System

/// An `MCP.Transport` over `SubprocessChannel`. This is the MCP stdio
/// transport — newline-delimited JSON over a child process's stdin and
/// stdout — expressed in terms of this codebase's one shared subprocess
/// implementation instead of a second `Process` plus three `Pipe`s.
///
/// It lives in `Core/MCP/` rather than beside `SubprocessChannel` in
/// `Core/RPC/` deliberately: the channel must stay free of the `MCP` import,
/// and knowing what an MCP transport is, is MCP's business.
///
/// Compared with the SDK's `StdioTransport`, which this replaces at the one
/// call site that used it: that type is handed two already-open file
/// descriptors and never owns the child, which is why `MCPClient` had to keep
/// a `Process` of its own beside it and terminate that separately. Here the
/// transport owns the child outright, so `disconnect()` is the single thing
/// that stops it and there is no second owner to fall out of step with.
///
/// Frames reach `receive()` byte-exact, trailing `0x0A` included — see
/// `MessageFraming.newlineDelimited`. `JSONDecoder` tolerates trailing
/// whitespace, so a real message decodes unchanged and stripping the delimiter
/// would buy a copy per frame and nothing observable.
///
/// A **blank** line is the one case where that byte matters, and this
/// transport filters those out (see `connect()`). `StdioTransport` stripped the
/// delimiter and then dropped any frame that was left empty, so blank stdout
/// lines never reached the SDK. Forwarding them as `"\n"` would not: `"\n"` is
/// not valid JSON, so every one would surface as a "Unexpected message received
/// by client" warning. That filtering belongs here rather than in
/// `MessageFraming`, because a blank line is meaningful in a newline-delimited
/// stream generally — it is MCP specifically that has no use for one.
public actor SubprocessTransport: Transport {

    /// Defaults to a no-op handler, matching `StdioTransport`'s own default.
    /// A transport that logged by default would be a regression in a menu-bar
    /// app: every JSON-RPC frame of every MCP server would reach the log.
    public nonisolated let logger: Logger

    private let channel: SubprocessChannel
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    /// Three states rather than a `Bool`, because there is a window in which
    /// neither answer is true: `connect()` releases this actor at
    /// `await channel.launch()`, and from the moment that call returns there
    /// is a live child that only `terminate()` will ever reap — but
    /// `connect()` has not resumed to record it. A `Bool` set after the
    /// suspension makes a `disconnect()` landing in that window a no-op, and
    /// the child outlives the app.
    private enum State {
        /// No child, or the last one has been terminated.
        case idle
        /// `connect()` is in flight and has not yet claimed the connection.
        /// A child may or may not exist yet; `terminate()` is safe either way
        /// (it guards on the channel's own `hasLaunched`).
        case connecting
        /// `connect()` completed: the child is running and the pump is up.
        case connected
    }

    private var state: State = .idle

    /// Republishes the channel's frames onto `messageStream`. Held so
    /// `disconnect()` can wait for it to drain: the frames a graceful child
    /// writes between SIGTERM and its own `exit` arrive through this task, and
    /// finishing `messageStream` without waiting would throw them away.
    private var forwardingTask: Task<Void, Never>?

    public init(configuration: SubprocessChannel.Configuration, logger: Logger? = nil) {
        self.channel = SubprocessChannel(configuration: configuration)
        self.logger = logger ?? Logger(
            label: "mcp.transport.subprocess",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )
        var producedContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { producedContinuation = $0 }
        self.messageContinuation = producedContinuation
    }

    /// Spawns the child and starts republishing its frames.
    ///
    /// Calling this twice is a no-op, matching `StdioTransport`'s
    /// `guard !isConnected` — and a *concurrent* second call, made while the
    /// first is still in `.connecting`, is the same no-op: it returns
    /// immediately rather than waiting for the first to finish. That is the
    /// same contract the sequential case has always had, where the second
    /// caller likewise learns nothing about the first, and it keeps the guard
    /// from becoming a place a caller can be parked for the length of a
    /// process spawn. What it does *not* do any more is spawn a second child.
    public func connect() async throws {
        guard case .idle = state else { return }
        // Claimed before the suspension, not after: from here until this
        // method returns, `disconnect()` must behave as though a child
        // exists, because for most of that span one does.
        state = .connecting
        do {
            try await channel.launch()
        } catch {
            // Nothing was spawned — `launch()` throws only before `run()`
            // succeeds — so there is nothing to reap, and the transport must
            // not be left claiming a connection it does not have.
            state = .idle
            throw error
        }
        // A `disconnect()` that landed while the line above was suspended has
        // already terminated the channel and finished the message stream.
        // Starting a pump over a dead child would republish nothing and
        // reopen a stream the caller was told had closed.
        guard case .connecting = state else { return }
        let frames = try await channel.messages()
        // Re-checked for the same reason: `messages()` is a second hop onto
        // the channel actor, so it is a second window. (A throw from it leaves
        // the state at `.connecting`, which is correct — the child is alive
        // and `disconnect()` must still reap it.)
        guard case .connecting = state else { return }
        state = .connected
        let continuation = messageContinuation
        forwardingTask = Task.detached {
            do {
                for try await frame in frames {
                    // A frame that is empty once its delimiter is disregarded
                    // is a blank stdout line. `StdioTransport` dropped those;
                    // yielding one as `"\n"` would make the SDK log an
                    // "Unexpected message" warning for every blank line a
                    // server prints. The delimiter is *not* stripped from real
                    // frames — only used to recognise this case.
                    guard frame.contains(where: { $0 != 0x0A }) else { continue }
                    continuation.yield(frame)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        logger.debug("Transport connected successfully")
    }

    /// Stops the child and finishes the message stream.
    ///
    /// `terminate()` is what makes this the *only* owner of the child: it
    /// closes stdin, escalates SIGTERM to SIGKILL, and only then releases the
    /// descriptors — so it costs up to 2.5 s and is not cancellable. Callers
    /// tearing down several servers must do so concurrently rather than in a
    /// loop; `MCPServerRegistry` already gives each `disconnect()` its own
    /// `Task`.
    ///
    /// `.connecting` is treated exactly as `.connected` and the channel is
    /// terminated unconditionally: `terminate()` guards on the channel's own
    /// `hasLaunched`, so it is a no-op if the spawn has not happened yet and a
    /// real kill if it has — which is the only way to cover a window this
    /// actor cannot see the far side of.
    public func disconnect() async {
        if case .idle = state { return }
        state = .idle
        await channel.terminate()

        // `terminate()` finishes the channel's frame stream itself — after
        // waiting out its own pump-drain grace — so this task is already
        // finishing or done. Waiting for it is what delivers the frames a
        // graceful child wrote between SIGTERM and `exit`, which is the
        // entire reason `terminate()` has a grace period at all; finishing
        // `messageStream` first would discard them.
        //
        // This cannot deadlock. The task's only suspension points are reading
        // the channel's stream — which `terminate()` has already finished —
        // and `continuation.yield`, and `messageStream` is built with
        // `AsyncThrowingStream`'s default `.unbounded` buffering policy, where
        // `yield` returns immediately and never waits for a consumer. Nothing
        // in the task touches this actor, so it does not queue behind the call
        // in progress either.
        if let forwardingTask {
            await forwardingTask.value
            // Belt and braces. A finished task ignores this; it costs nothing
            // and stops a future change that lets the pump outlive the
            // channel's stream from turning into a hang here.
            forwardingTask.cancel()
        }
        forwardingTask = nil

        // Also belt and braces: the loop above ended by calling
        // `continuation.finish()` itself, which is what actually closed the
        // stream. This covers the path where `connect()` never got as far as
        // installing a pump — the race this method exists to handle — and a
        // second `finish()` is defined to be a no-op.
        messageContinuation.finish()
        logger.debug("Transport disconnected")
    }

    /// Frames `data` and writes it to the child's stdin. The MCP stdio wire
    /// format is newline-delimited JSON, so the delimiter `.newlineDelimited`
    /// appends here is exactly the one the spec requires.
    ///
    /// Sending before `connect()` or after `disconnect()` throws `ENOTCONN`,
    /// which is `StdioTransport`'s answer byte for byte. Without the guard the
    /// caller would get whatever the channel happened to raise —
    /// `.notLaunched` before the spawn, `EPIPE` after the teardown — and the
    /// SDK's error handling is written against the errno.
    public func send(_ data: Data) async throws {
        guard case .connected = state else {
            throw MCPError.transportError(Errno(rawValue: ENOTCONN))
        }
        try await channel.send(data)
    }

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        messageStream
    }
}
