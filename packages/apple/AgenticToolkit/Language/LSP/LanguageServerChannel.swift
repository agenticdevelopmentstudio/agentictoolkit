//
//  LanguageServerChannel.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Foundation
import JSONRPC
import OSLog

/// Bridges `AgenticToolkitCore.SubprocessChannel` onto `JSONRPC.DataChannel`,
/// which is what `JSONRPCServerConnection` — and through it
/// `LanguageClient.InitializingServer` — reads and writes.
///
/// It lives in `Language/LSP/` rather than beside `SubprocessChannel` in
/// `Core/RPC/` for the same reason `SubprocessTransport` lives in `Core/MCP/`:
/// the channel must stay free of the `JSONRPC` import, and knowing what a
/// JSON-RPC data channel is, is JSON-RPC's business. This is the LSP twin of
/// that transport — the same shape of problem, one framing mode over.
///
/// **Framing is the subprocess channel's job and is done exactly once.** The
/// `SubprocessChannel` handed in must be configured `framing: .contentLength`;
/// it then prefixes the `Content-Length` header on `send(_:)` and yields whole
/// decoded bodies from `messages()`. So the write handler passes the **bare
/// JSON** to `send(_:)` — never `sendRaw`, never a header of its own — and the
/// connection built on top must be constructed with `addMessageFraming: false`.
/// Framing twice is silent: the server sees
/// `Content-Length: 57\r\n\r\nContent-Length: 41\r\n\r\n{…}` and either hangs
/// or errors in a way that reads as a bad server rather than a bad client.
/// `LanguageServerSessionTests.initializeRequestIsFramedExactlyOnce` counts the
/// headers that actually reach the child, and
/// `framedInitializeResponseRoundTrips` is the end-to-end control that fails
/// the moment either side frames twice.
///
/// No frame is filtered. `SubprocessTransport` drops all-newline frames because
/// `.newlineDelimited` retains its `0x0A` delimiter, so a blank stdout line
/// arrives as a `"\n"` frame that the MCP SDK would warn about. None of that
/// applies here: a `.contentLength` body carries no delimiter, and a body that
/// happens to be all newlines is a legitimate message. Every frame `messages()`
/// yields goes straight through.
public struct LanguageServerChannel: Sendable {

    /// Called exactly once, when the child's output stream ends: with the error
    /// that ended it, or `nil` for a clean end.
    ///
    /// `DataChannel.dataSequence` is a **non-throwing** `AsyncStream<Data>` and
    /// there is nowhere in `DataChannel` to put an error, so an error swallowed
    /// here would be indistinguishable from a clean shutdown —
    /// `InitializingServer` would see only that the sequence finished. A server
    /// that crashes mid-body produces `MessageFramingError.truncatedMessage`,
    /// and a caller must be able to tell that apart from a `shutdown` it asked
    /// for.
    ///
    /// The optional is deliberate, and is the one place this seam departs from
    /// a plain `(any Error) -> Void`: a clean end the caller did **not** ask for
    /// is also a death — a language server that exits at a frame boundary, or
    /// that writes nothing to stdout at all because its executable was missing —
    /// and the session has to hear about that promptly rather than by timing
    /// out. One handler reporting both outcomes is what lets
    /// `LanguageServerSession` tell all three apart: framing error, unasked
    /// exit, requested shutdown.
    public typealias StreamEndHandler = @Sendable ((any Error)?) -> Void

    /// The bridged channel, ready to hand to
    /// `JSONRPCServerConnection(dataChannel:addMessageFraming: false)`.
    public let dataChannel: DataChannel

    /// Republishes the subprocess channel's frames onto `dataChannel`. Held so
    /// `drain()` can wait for it: the frames a graceful child writes between
    /// SIGTERM and its own `exit` arrive through this task, and finishing the
    /// data sequence without waiting would throw them away.
    private let forwardingTask: Task<Void, Never>

    /// Launches `channel` and starts republishing its frames.
    ///
    /// The republishing task is created once, here, after `launch()`, and the
    /// continuation is captured into a local before the task closure so no
    /// actor is captured with it — the `SubprocessTransport` pattern.
    ///
    /// A throw from here means nothing is left running that this type owns:
    /// `SubprocessChannel.launch()` throws only before `Process.run()`
    /// succeeds, and `messages()` throws only `.notLaunched` /
    /// `.alreadyConsumed`. The caller owns the channel either way and is the
    /// one that terminates it.
    public static func connect(
        over channel: SubprocessChannel,
        onStreamEnd: @escaping StreamEndHandler
    ) async throws -> LanguageServerChannel {
        try await channel.launch()
        let frames = try await channel.messages()

        var producedContinuation: DataChannel.DataSequence.Continuation!
        let dataSequence = DataChannel.DataSequence { producedContinuation = $0 }
        let continuation = producedContinuation!

        let forwardingTask = Task.detached {
            do {
                for try await frame in frames {
                    continuation.yield(frame)
                }
                onStreamEnd(nil)
            } catch {
                let message = error.localizedDescription
                logger.error("Language server transport failed: \(message, privacy: .public)")
                onStreamEnd(error)
            }
            // Always after the handler: a caller that reacts to the sequence
            // ending by reading the recorded error must find it already
            // recorded rather than racing the sequence's own consumers for it.
            continuation.finish()
        }

        // The bare JSON. `.contentLength` framing is applied by `send(_:)`.
        let writeHandler: DataChannel.WriteHandler = { data in
            try await channel.send(data)
        }

        return LanguageServerChannel(
            dataChannel: DataChannel(writeHandler: writeHandler, dataSequence: dataSequence),
            forwardingTask: forwardingTask
        )
    }

    /// Waits for the republishing task to finish.
    ///
    /// Call this **after** `SubprocessChannel.terminate()`, which finishes the
    /// frame stream itself once its own pump-drain grace has elapsed — that is
    /// what bounds this wait, and nothing else. Waiting is what delivers the
    /// frames a graceful child wrote between SIGTERM and `exit`.
    public func drain() async {
        await forwardingTask.value
    }
}

extension LanguageServerChannel: Loggable {
    public static nonisolated let logger = makeLogger()
}
