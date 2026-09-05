import Foundation
import Logging
import MCP

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

    private var isConnected = false

    /// Republishes the channel's frames onto `messageStream`. Held so the
    /// actor keeps a reference to it while connected; it ends on its own when
    /// the channel's frame stream finishes, which `terminate()` guarantees.
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

    /// Spawns the child and starts republishing its frames. Calling this twice
    /// is a no-op, matching `StdioTransport`'s `guard !isConnected`.
    public func connect() async throws {
        guard !isConnected else { return }
        try await channel.launch()
        // Recorded the moment the child exists rather than once the pump is
        // running: anything that fails below this line has already spawned a
        // process, and `disconnect()` is the only thing that will reap it.
        isConnected = true
        let frames = try await channel.messages()
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
    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        await channel.terminate()
        forwardingTask = nil
        messageContinuation.finish()
        logger.debug("Transport disconnected")
    }

    /// Frames `data` and writes it to the child's stdin. The MCP stdio wire
    /// format is newline-delimited JSON, so the delimiter `.newlineDelimited`
    /// appends here is exactly the one the spec requires.
    public func send(_ data: Data) async throws {
        try await channel.send(data)
    }

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        messageStream
    }
}
