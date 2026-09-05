import Darwin
import Dispatch
import Foundation

/// Spawns a child process and exposes its stdout as a stream of framed
/// messages, per `configuration.framing`. This is the one shared replacement
/// for the several independent `Process` + three-`Pipe` implementations in
/// this codebase; it owns exactly one output path — a stream of decoded
/// frames — and does not additionally hand out a raw file descriptor, so
/// there is never more than one reader over the child's stdout.
public actor SubprocessChannel {

    public struct Configuration: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        public var environmentPolicy: EnvironmentPolicy
        public var framing: MessageFraming

        public init(
            executableURL: URL,
            arguments: [String] = [],
            environment: [String: String] = [:],
            environmentPolicy: EnvironmentPolicy = .replace,
            framing: MessageFraming = .newlineDelimited
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.environmentPolicy = environmentPolicy
            self.framing = framing
        }
    }

    /// How `environment` combines with the parent process's environment.
    /// The two callers this type replaces disagree, and the disagreement is
    /// meaningful, so it is a parameter rather than a house style.
    public enum EnvironmentPolicy: Sendable {
        /// `environment` becomes the child's entire environment when non-empty;
        /// an empty dictionary inherits the parent's untouched. This is
        /// `PluginTransport`'s behaviour: a plugin that hands over a minimal
        /// environment is deliberately isolating its child, and silently
        /// merging the parent's back in would defeat that.
        case replace
        /// `environment` is merged over the parent's, new values winning. This
        /// is `MCPClient.makeStdioTransport`'s behaviour: an MCP server needs
        /// `PATH` and `HOME` to run at all, and its configuration only ever
        /// carries overrides.
        case mergeOverParent
    }

    public enum ChannelError: Error, LocalizedError {
        case notLaunched
        case alreadyLaunched
        /// `messages()` was already called once. The channel owns exactly
        /// one reader over the child's stdout; a second caller would
        /// silently split frames between the two, and there is no
        /// well-defined way to hand out the same `AsyncThrowingStream`
        /// twice and have both sides see every frame.
        case alreadyConsumed
        case launchFailed(String)
        /// Not thrown by `SubprocessChannel` itself — `waitUntilExit()`
        /// returns the raw status and `standardErrorText()` the raw text, and
        /// it is the caller's call whether a non-zero exit is an error at
        /// all. (`PluginTransport` treats it as one; a long-lived MCP server
        /// may not.) This case exists so a caller can escalate a non-zero
        /// exit into an error of this same family without inventing its own.
        case exited(status: Int32, standardError: String)

        public var errorDescription: String? {
            switch self {
            case .notLaunched:
                return "The subprocess channel has not been launched yet."
            case .alreadyLaunched:
                return "The subprocess channel has already been launched."
            case .alreadyConsumed:
                return "messages() has already been called; only one reader is supported."
            case .launchFailed(let reason):
                return "Failed to launch the subprocess: \(reason)"
            case .exited(let status, let standardError):
                return "The subprocess exited with status \(status): \(standardError)"
            }
        }
    }

    /// The largest chunk either reader hands over at once — the `DispatchIO`
    /// high-water mark for both the stdout pump and the stderr drain. Feeding
    /// `MessageFramingDecoder` chunks this size, rather than one byte at a
    /// time via `FileHandle.bytes`, is half of what makes decoding linear
    /// instead of quadratic — the other half is the decoder's own scan cursor.
    private static let readChunkSize = 64 * 1024

    /// SIGTERM grace period before `terminate()` escalates to SIGKILL. A
    /// child that traps or ignores SIGTERM must not be able to hang
    /// `terminate()`, or leak the process and its descriptors, forever.
    private static let terminationGraceSeconds: TimeInterval = 2.0

    /// How long `standardErrorText()` will wait for the stderr drain to reach
    /// EOF before answering with whatever it has buffered so far. EOF on
    /// stderr needs *every* holder of the write end to close it, and a child
    /// that backgrounds a helper (`npx`, any `sh -c "… &"` wrapper) can leave
    /// that end open long after it has exited itself — an unbounded wait there
    /// is a permanent hang. Half a second is generous for the ordinary case,
    /// where the drain has already finished before this is ever called.
    private static let standardErrorDrainGraceSeconds: TimeInterval = 0.5

    /// How long `terminate()` waits — after the child is dead and the chunk
    /// streams have been stopped — for the message pump to flush what it has
    /// already read and finish the message stream itself. That wait is what
    /// delivers a shutdown *frame* the child wrote between SIGTERM and its own
    /// `exit`; cancelling the pump in its place would trip the pump's
    /// `Task.checkCancellation()` and hand the consumer a `CancellationError`
    /// where its last protocol message should be. Bounded for the same reason
    /// as the stderr grace above: a pump that has not finished once its
    /// descriptor is closed is not going to, and an unbounded wait inside
    /// `terminate()` is a hang.
    private static let messagePumpDrainGraceSeconds: TimeInterval = 0.5

    /// How much of the child's stderr this actor retains. Frames already
    /// have a 16 MB cap (`MessageFramingDecoder.maximumFrameBytes`); stderr
    /// had no equivalent, and a verbose long-lived child would otherwise
    /// grow this without bound for the life of the process.
    private static let maximumStandardErrorBytes = 1 * 1024 * 1024

    private let configuration: Configuration

    /// Bridges `Process.terminationHandler` to any number of independent
    /// `waitUntilExit()` callers. `nonisolated` and lock-protected internally
    /// (see `ExitWaiterBox`/`ExitWaiter` below) rather than actor-isolated,
    /// because the whole point of `waitUntilExit()` is that awaiting it must
    /// never hold this actor.
    private nonisolated let exitWaiterBox = ExitWaiterBox()

    /// The two `DispatchIO` readers, held where `deinit` can reach them.
    /// A channel dropped without `terminate()` — its child still alive and
    /// silent — must still give its descriptors and its dispatch queues back;
    /// `deinit` is nonisolated, so the readers cannot live in actor-isolated
    /// storage if it is to stop them.
    private nonisolated let readerBox = DescriptorReaderBox()

    private var process: Process?
    private var standardInputPipe: Pipe?

    private var hasLaunched = false
    private var isTerminated = false
    private var hasVendedMessageStream = false

    private var messageStream: AsyncThrowingStream<Data, Error>?
    private var messageContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var pumpTask: Task<Void, Never>?
    private var standardErrorTask: Task<Void, Never>?
    private var standardErrorBuffer = Data()
    private var isStandardErrorTruncated = false
    /// Set when `standardErrorText()`'s drain budget lapsed, i.e. the capture
    /// is a snapshot of a stream still being written rather than everything
    /// the child had to say. Distinct from `isStandardErrorTruncated`, which
    /// means the *front* was trimmed at the cap.
    private var isStandardErrorIncomplete = false

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    deinit {
        // Stops the `DispatchIO` channels and closes the read descriptors
        // they own. Safe from `deinit` because `readerBox` is a `nonisolated
        // let` guarded by its own lock, not actor-isolated state.
        readerBox.stopAll()
    }

    /// Spawns the process and starts the read pump. Throws `.alreadyLaunched`
    /// if called twice.
    public func launch() throws {
        guard !hasLaunched else { throw ChannelError.alreadyLaunched }

        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        applyEnvironment(to: process)

        let standardInputPipe = Pipe()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()

        // Suppress SIGPIPE for exactly this descriptor rather than
        // process-wide: `AgenticToolkitCore` is a shared framework, and
        // `signal(SIGPIPE, SIG_IGN)` here would reach into every host app
        // and plugin bundle that links it. `F_SETNOSIGPIPE` scopes the
        // change to the one descriptor this actor ever writes to, so a
        // write after the child has exited becomes a thrown `EPIPE` Swift
        // error (from `FileHandle`'s throwing `write(contentsOf:)`) instead
        // of a fatal signal.
        //
        // The return value is checked rather than discarded: a silently
        // un-armed guard is precisely the failure this exists to remove, and
        // its consequence — the *host* process dying on signal 13 on some
        // later `send()` — is unbounded. Nothing has launched yet at this
        // point, so failing here leaves no child behind.
        guard fcntl(standardInputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ChannelError.launchFailed(
                "could not disable SIGPIPE on the child's stdin (errno \(errno))"
            )
        }

        process.standardInput = standardInputPipe
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        // Installed *before* `run()`, so there is no window in which the
        // child can exit before anything is listening. The `isRunning`
        // fallback below still covers the case where Foundation has already
        // reaped an immediately-exiting child by the time `run()` returns.
        let exitWaiter = ExitWaiter(process: process)

        do {
            try process.run()
        } catch {
            // Nothing launched, so there is no running child to leave behind.
            throw ChannelError.launchFailed("\(error)")
        }

        exitWaiter.resolveIfAlreadyExited(process)
        exitWaiterBox.set(exitWaiter)

        let standardOutputReader = DescriptorReader(
            handle: standardOutputPipe.fileHandleForReading,
            label: "com.agentictoolkit.subprocess-channel.stdout"
        )
        let standardErrorReader = DescriptorReader(
            handle: standardErrorPipe.fileHandleForReading,
            label: "com.agentictoolkit.subprocess-channel.stderr"
        )
        readerBox.set(standardOutput: standardOutputReader, standardError: standardErrorReader)

        self.process = process
        self.standardInputPipe = standardInputPipe
        hasLaunched = true

        startMessagePump(process: process, reader: standardOutputReader)
        startStandardErrorDrain(reader: standardErrorReader)
    }

    /// Framed messages from the child's stdout. Finishes on EOF; throws on a
    /// framing error. Calling this before `launch()` throws `.notLaunched`;
    /// calling it a second time throws `.alreadyConsumed` — the child's
    /// stdout has exactly one reader.
    public func messages() throws -> AsyncThrowingStream<Data, Error> {
        guard let messageStream else { throw ChannelError.notLaunched }
        guard !hasVendedMessageStream else { throw ChannelError.alreadyConsumed }
        hasVendedMessageStream = true
        return messageStream
    }

    /// Frames `message` and writes it to the child's stdin. Equivalent to
    /// `sendRaw(configuration.framing.frame(message))`.
    public func send(_ message: Data) throws {
        try sendRaw(configuration.framing.frame(message))
    }

    /// Writes `bytes` to the child's stdin **unframed**, byte for byte.
    /// A one-shot caller that pipes an opaque payload in (a prompt, a file)
    /// and closes stdin has no message boundaries to declare, and appending a
    /// delimiter it never asked for would change what the child reads.
    ///
    /// A write after the child has exited throws rather than raising
    /// SIGPIPE — `launch()` disables the signal for this descriptor
    /// specifically (see `F_SETNOSIGPIPE` there).
    public func sendRaw(_ bytes: Data) throws {
        guard let standardInputPipe else { throw ChannelError.notLaunched }
        try standardInputPipe.fileHandleForWriting.write(contentsOf: bytes)
    }

    /// Closes stdin so the child sees EOF and can finish.
    public func closeInput() {
        try? standardInputPipe?.fileHandleForWriting.close()
    }

    /// Everything the child wrote to stderr, decoded as UTF-8 where possible.
    /// A truncation cut, or a child that simply doesn't write UTF-8, can
    /// leave bytes that don't decode as UTF-8; those fall back to Latin-1
    /// (which accepts every byte) rather than losing the whole capture to an
    /// empty string.
    ///
    /// Waits up to `standardErrorDrainGraceSeconds` for the drain task to
    /// finish, so the ordinary case is deterministic rather than racing the
    /// child's last write — but the wait is **bounded**, and expiry is not an
    /// error: whatever is buffered at that point is returned. The case that
    /// makes the bound necessary is not a child still running, it is a child
    /// that has *already exited* while a grandchild it backgrounded still
    /// holds the stderr write end open (`npx` wrappers, `sh -c "… &"`). EOF
    /// needs every holder to close, so an unbounded wait there never returns
    /// at all. A diagnostic string is a best-effort artefact; failing to
    /// produce one must never fail the operation that was trying to explain
    /// itself. Calling `terminate()` first forces the descriptors closed and
    /// makes the answer complete.
    ///
    /// Capped at the last `maximumStandardErrorBytes`; a truncated capture is
    /// prefixed with a marker rather than silently missing its start. A
    /// capture cut short by the drain budget instead gets its own, different
    /// marker: a partial answer must never present itself as a complete one,
    /// and "the front was trimmed" and "the end hasn't arrived yet" are
    /// different facts for a caller trying to explain a failure.
    public func standardErrorText() async -> String {
        if let standardErrorTask {
            let drained: Bool? = try? await withWallClockBudget(
                Self.standardErrorDrainGraceSeconds
            ) {
                await standardErrorTask.value
                return true
            }
            if drained == nil { isStandardErrorIncomplete = true }
        }
        let text = String(bytes: standardErrorBuffer, encoding: .utf8)
            ?? String(bytes: standardErrorBuffer, encoding: .isoLatin1)
            ?? ""
        var prefix = ""
        if isStandardErrorTruncated {
            prefix += "[stderr truncated to the last \(Self.maximumStandardErrorBytes) bytes]\n"
        }
        if isStandardErrorIncomplete {
            let grace = Self.standardErrorDrainGraceSeconds
            prefix += "[stderr capture incomplete: the drain did not finish within \(grace)s]\n"
        }
        return prefix + text
    }

    /// Terminates the child if still running and finishes the message
    /// stream. Idempotent. A no-op if `launch()` was never called, and that
    /// case does not disarm a later `launch()` + `terminate()` on the same
    /// channel.
    ///
    /// Order matters, and is: close the child's stdin → SIGTERM → wait up to
    /// `terminationGraceSeconds` → SIGKILL → stop the two `DispatchIO`
    /// readers, which is the only place descriptors are closed → wait up to
    /// `messagePumpDrainGraceSeconds` for the pump to flush and finish the
    /// message stream itself. Neither output stream is touched before the
    /// child is dead: the pump and the stderr drain both run for the whole
    /// grace period, so a shutdown *frame* on stdout and a shutdown log line
    /// on stderr — the same event on two descriptors, and on a JSON-RPC
    /// channel the stdout one is a protocol message rather than a log —
    /// both reach their consumer. Closing the
    /// child's stdout/stderr read ends any earlier makes its next write raise
    /// SIGPIPE, so a child that flushes a shutdown log from its own SIGTERM
    /// handler dies of a signal with that log unwritten and the grace period
    /// buys nothing at all. The readers are stopped unconditionally —
    /// not after waiting for the pump/drain tasks to observe EOF on their
    /// own, which a child launched through a shell wrapper (`sh -c …`,
    /// `npx …`) can withhold forever if a grandchild still holds the write
    /// end. Stopping a `DispatchIO` channel has a defined interaction with a
    /// read in flight (the outstanding handler is called with `ECANCELED`,
    /// then the cleanup handler closes the descriptor), so forcing it here is
    /// safe rather than a crash risk.
    ///
    /// **Termination reaches the direct child only.** Both the SIGTERM and
    /// the SIGKILL escalation signal a single pid, never a process group, so
    /// a child that backgrounds helpers of its own (again: `npx`, `sh -c "… &"`)
    /// leaves those helpers orphaned and running. Killing the group instead
    /// would require spawning with `POSIX_SPAWN_SETPGROUP`, which `Process`
    /// does not expose — and signalling the *inherited* group would signal
    /// this host process too. That is a change to how this channel spawns,
    /// not something `terminate()` can do; until then, callers that need
    /// grandchildren reaped must arrange it in the command they launch.
    public func terminate() async {
        guard hasLaunched else { return }
        guard !isTerminated else { return }
        isTerminated = true

        // Neither output stream is touched here — not the pump, not the
        // drain. A graceful child writes its last words between SIGTERM and
        // its own `exit`: a shutdown frame on stdout and a shutdown log line
        // on stderr are the same event on two descriptors, and both are the
        // whole reason the grace period below exists. Finishing either stream
        // now would drop those bytes even though the descriptor stays open,
        // and closing either read end now would SIGPIPE the child before it
        // could write them at all. Both are wound down after the escalation,
        // next to `readerBox.stopAll()`.
        //
        // Stdin is only ever written from this actor, so closing it here is
        // safe, and a child blocked reading it needs the EOF to notice it has
        // been asked to leave. The stdout/stderr read ends are handled below,
        // once the child is confirmed dead or forcibly killed.
        try? standardInputPipe?.fileHandleForWriting.close()

        if let process, process.isRunning {
            process.terminate() // SIGTERM

            let exitWaiterBox = exitWaiterBox
            _ = try? await withWallClockBudget(Self.terminationGraceSeconds) {
                await exitWaiterBox.get()?.wait()
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        // The child is dead by here, so closing the read ends can no longer
        // SIGPIPE anything, and both readers have had the whole grace period
        // to carry whatever the child said on its way out.
        readerBox.stopAll()

        // `stopAll()` finished both chunk streams, so the pump now runs to its
        // own end: it drains what it has already read, flushes the decoder and
        // finishes the message stream itself. Waiting for that is what
        // delivers the child's final frame — cancelling the pump in its place
        // would trip its `Task.checkCancellation()` and replace that frame
        // with a `CancellationError`, which is the stdout shape of the bug
        // this ordering exists to remove.
        let pumpTask = pumpTask
        _ = try? await withWallClockBudget(Self.messagePumpDrainGraceSeconds) {
            await pumpTask?.value
        }

        // Fallbacks for a pump that did not finish inside that budget. Both
        // are idempotent, and both are no-ops on the ordinary path where the
        // pump has already finished the stream itself.
        pumpTask?.cancel()
        messageContinuation?.finish()

        // The drain needs no wait of its own here: it appends to this actor's
        // buffer as the bytes arrive, and `standardErrorText()` does its own
        // bounded wait for whatever is still in flight.
        standardErrorTask?.cancel()
    }

    /// Waits for exit and returns the status. Returns immediately if already
    /// exited. `nonisolated` and implemented over `Process.terminationHandler`
    /// rather than the blocking `Process.waitUntilExit()`: that call, made
    /// from inside the actor, would park both the calling thread and the
    /// actor itself for as long as the child runs — permanent, for a
    /// long-lived MCP server, and it would make `terminate()` on that same
    /// channel unreachable (every other actor call, `terminate()` included,
    /// queues behind the blocked one).
    public nonisolated func waitUntilExit() async -> Int32 {
        await exitWaiterBox.get()?.wait() ?? 0
    }

    // MARK: - Environment

    private func applyEnvironment(to process: Process) {
        switch configuration.environmentPolicy {
        case .replace:
            if !configuration.environment.isEmpty {
                process.environment = configuration.environment
            }
        case .mergeOverParent:
            if !configuration.environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment
                    .merging(configuration.environment) { _, overridden in overridden }
            }
        }
    }

    // MARK: - Pumping

    /// Decodes the chunks `reader` produces into frames and drives
    /// `messageStream`. The task only ever *awaits* chunks — the descriptor
    /// itself is read by `DispatchIO` on its own queue — so this parks no
    /// thread of Swift's fixed-width cooperative pool while the child is
    /// silent. That distinction is the whole point: a blocking `read(2)` on a
    /// pool thread, two per live channel, starves every other async task in
    /// the host process once roughly `activeProcessorCount / 2` channels are
    /// open.
    private func startMessagePump(process: Process, reader: DescriptorReader) {
        let processBox = ProcessBox(process)
        let framing = configuration.framing

        var producedContinuation: AsyncThrowingStream<Data, Error>.Continuation!
        // `.unbounded` is deliberate, not an oversight: every bounded
        // `AsyncThrowingStream` buffering policy (`.bufferingNewest`,
        // `.bufferingOldest`) silently drops elements once full, and
        // dropping a frame from a JSON-RPC stream desynchronises the
        // session permanently — the next reply gets read against the wrong
        // request, forever, not merely late. The real bounds on how much
        // this can ever buffer are `MessageFramingDecoder`'s 16 MB per-frame
        // cap and this actor's 1 MB stderr cap; if a consumer falls behind a
        // producer badly enough for that to matter, supplying backpressure
        // is the caller's problem to own (the controller's ruling), not
        // something to paper over here by quietly losing frames. Do not
        // "fix" this into a bounded policy.
        let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .unbounded) {
            producedContinuation = $0
        }
        messageStream = stream
        messageContinuation = producedContinuation
        let continuation = producedContinuation!

        let pumpTask = Task.detached {
            var decoder = MessageFramingDecoder(framing: framing)
            do {
                try await withTaskCancellationHandler {
                    for try await chunk in reader.chunks {
                        try Task.checkCancellation()
                        for frame in try decoder.consume(chunk) {
                            continuation.yield(frame)
                        }
                    }
                    try Task.checkCancellation()
                    for frame in try decoder.finish() {
                        continuation.yield(frame)
                    }
                    continuation.finish()
                } onCancel: {
                    // Consuming task cancellation — the consumer went away —
                    // must tear the child down eagerly, and wake this loop's
                    // `await` so it does not park on a silent child forever.
                    // `terminate()` reaches this only as a fallback, after the
                    // escalation, for a pump that outlived its drain budget.
                    //
                    // `finishStream()`, never `stop()`: `Task.cancel()` runs
                    // this body synchronously on the cancelling thread, so
                    // closing the descriptor here would close the child's
                    // stdout read end *before* `terminate()` sends SIGTERM
                    // and kill a graceful child with SIGPIPE. The descriptor
                    // is released by `terminate()`'s `readerBox.stopAll()`
                    // after the SIGKILL escalation, or by `deinit`.
                    reader.finishStream()
                    processBox.terminateIfRunning()
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
        self.pumpTask = pumpTask

        // The stream's own termination — the consumer cancels the task that
        // is iterating `messages()`, breaks out of its loop, or `terminate()`
        // calls `continuation.finish()` — is Swift's signal that nobody is
        // listening any more. Forward it into the pump task's cancellation so
        // the `onCancel` handler above runs.
        continuation.onTermination = { @Sendable _ in
            pumpTask.cancel()
        }
    }

    /// Drains the child's stderr on its own task, independent of both the
    /// actor and the stdout pump. A child that fills the 64 KB stderr pipe
    /// buffer while nobody drains it deadlocks, and a long-lived server makes
    /// that likely rather than theoretical — the original `runCommand` only
    /// read stderr once, at exit, which is exactly exposed to this. Draining
    /// continuously, on a task that never needs the actor mid-stream, is a
    /// genuine improvement over what this replaces.
    ///
    /// Captures `self` weakly: a drain that never sees EOF (the same
    /// grandchild-holds-the-pipe case `terminate()`'s doc comment describes)
    /// must not keep this actor alive forever just because this task hasn't
    /// noticed yet. If every external reference to the channel is dropped,
    /// this task's `self?.appendStandardError` calls become harmless no-ops
    /// instead of a retain cycle, and the actor's `deinit` stops the reader.
    private func startStandardErrorDrain(reader: DescriptorReader) {
        standardErrorTask = Task.detached { [weak self] in
            do {
                try await withTaskCancellationHandler {
                    for try await chunk in reader.chunks {
                        await self?.appendStandardError(chunk)
                    }
                } onCancel: {
                    // Wake the loop without closing the child's stderr read
                    // end — see `DescriptorReader.finishStream()`. Closing it
                    // here would SIGPIPE the child mid-shutdown, losing
                    // exactly the diagnostic this drain exists to capture.
                    reader.finishStream()
                }
            } catch {
                // Best-effort: whatever arrived before the read failed (e.g.
                // the descriptor was stopped out from under it by
                // `terminate()`) is still reported.
            }
        }
    }

    private func appendStandardError(_ data: Data) {
        standardErrorBuffer.append(data)
        guard standardErrorBuffer.count > Self.maximumStandardErrorBytes else { return }
        // Keep the tail, not the head: a failing process's useful
        // diagnostic is almost always its last output, not its startup
        // banner.
        let overflow = standardErrorBuffer.count - Self.maximumStandardErrorBytes
        let cut = standardErrorBuffer.index(standardErrorBuffer.startIndex, offsetBy: overflow)
        standardErrorBuffer.removeSubrange(standardErrorBuffer.startIndex..<cut)
        isStandardErrorTruncated = true
    }

    /// `Process` isn't `Sendable`; the cancellation handler only touches the
    /// thread-safe `isRunning`/`terminate`.
    private final class ProcessBox: @unchecked Sendable {
        private let process: Process
        init(_ process: Process) { self.process = process }
        func terminateIfRunning() {
            if process.isRunning { process.terminate() }
        }
    }

    /// Reads one descriptor with `DispatchIO` on a serial queue of its own and
    /// vends the bytes as an `AsyncThrowingStream` of chunks.
    ///
    /// `DispatchIO` rather than a blocking read on a `Task.detached`: the
    /// latter parks a thread of Swift's fixed-width cooperative pool for as
    /// long as the child is silent, two per live channel, which starves every
    /// other async task in the host process once enough channels are open.
    /// `DispatchIO` rather than `FileHandle.readabilityHandler`: both stay off
    /// the cooperative pool, but `terminate()` force-closes descriptors while
    /// a read may be in flight, and `readabilityHandler` against a closed
    /// descriptor raises an Objective-C exception Swift cannot catch, whereas
    /// `DispatchIO.close(flags: .stop)` has a defined interaction with exactly
    /// that path.
    ///
    /// The queue is **serial**, so chunks are yielded in the order they were
    /// read; the stream is unbounded, so none is dropped. A reordered or lost
    /// chunk would desynchronise a JSON-RPC session permanently, which is the
    /// same reasoning that keeps the message stream unbounded.
    ///
    /// `@unchecked Sendable` because the lock, not the compiler, is what makes
    /// the finish-exactly-once guarantee hold across the dispatch queue, the
    /// consuming task and `terminate()`.
    private final class DescriptorReader: @unchecked Sendable {
        /// Chunks in arrival order; finishes on EOF or on `stop()`, and
        /// throws if the read itself fails.
        let chunks: AsyncThrowingStream<Data, Error>

        private let closer: HandleCloser
        private let dispatchChannel: DispatchIO
        private let continuation: AsyncThrowingStream<Data, Error>.Continuation
        private let lock = NSLock()
        private var hasFinishedStream = false
        private var hasClosedDescriptor = false

        init(handle: FileHandle, label: String) {
            let closer = HandleCloser(handle)
            self.closer = closer
            let queue = DispatchQueue(label: label)
            var producedContinuation: AsyncThrowingStream<Data, Error>.Continuation!
            chunks = AsyncThrowingStream<Data, Error>(bufferingPolicy: .unbounded) {
                producedContinuation = $0
            }
            continuation = producedContinuation

            // The `DispatchIO` channel owns the descriptor from here: its
            // cleanup handler is the single place it is closed, which is what
            // makes closing it safe while a read is outstanding. `FileHandle`
            // records the close, so its own `deinit` does not repeat it.
            dispatchChannel = DispatchIO(
                type: .stream,
                fileDescriptor: handle.fileDescriptor,
                queue: queue,
                cleanupHandler: { _ in closer.close() }
            )
            // Deliver as soon as a single byte is available (a JSON-RPC reply
            // must not wait for a full buffer), but never more than one chunk
            // at a time.
            dispatchChannel.setLimit(lowWater: 1)
            dispatchChannel.setLimit(highWater: SubprocessChannel.readChunkSize)

            // `length: .max` means "until EOF": the handler is invoked
            // repeatedly with successive chunks, then once with `done`.
            // `self` is captured strongly on purpose — the handler is the
            // only thing that will finish the stream and release the
            // descriptor, so it must outlive every other reference. The cycle
            // it forms is broken by `finish(with:)`, which every terminal path
            // (EOF, error, `stop()`) goes through.
            dispatchChannel.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
                if let data, !data.isEmpty {
                    self.continuation.yield(Self.makeData(from: data))
                }
                if error != 0 {
                    // `ECANCELED` is what a deliberate `stop()` looks like
                    // from in here; that is an ordinary end of stream, not a
                    // failure to report.
                    if error == ECANCELED {
                        self.finish(with: nil, closingDescriptor: true)
                    } else {
                        self.finish(
                            with: NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil),
                            closingDescriptor: true
                        )
                    }
                    return
                }
                if done {
                    self.finish(with: nil, closingDescriptor: true)
                }
            }
        }

        /// Wakes the consumer and nothing else: finishes the chunk stream so
        /// a `for await` parked on a silent child returns, while leaving the
        /// `DispatchIO` channel and the descriptor open.
        ///
        /// This is the half `onCancel` wants, and keeping it separate from
        /// `stop()` is load-bearing. Closing the read end of the child's
        /// stdout/stderr makes the child's next write raise SIGPIPE — the
        /// parent's `F_SETNOSIGPIPE` covers only its own write end of the
        /// child's *stdin* — so a graceful child that flushes a shutdown log
        /// from its SIGTERM handler dies of a signal instead, and
        /// `terminationGraceSeconds` buys nothing. Waking the consumer is a
        /// fact about the consumer; closing the descriptor is a fact about
        /// the child. Do not merge these two methods back together.
        ///
        /// Chunks the still-live read delivers afterwards are yielded into a
        /// terminated continuation, which returns `.terminated` and drops
        /// them. Idempotent.
        func finishStream() {
            finish(with: nil, closingDescriptor: false)
        }

        /// Ends the stream *and* releases the descriptor without waiting for
        /// EOF. Idempotent, and safe to call while a read is in flight.
        func stop() {
            finish(with: nil, closingDescriptor: true)
        }

        private func finish(with error: Error?, closingDescriptor: Bool) {
            lock.lock()
            let shouldFinishStream = !hasFinishedStream
            hasFinishedStream = true
            let shouldClose = closingDescriptor && !hasClosedDescriptor
            if shouldClose { hasClosedDescriptor = true }
            lock.unlock()

            if shouldFinishStream {
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            guard shouldClose else { return }
            // `.stop` cancels any outstanding read rather than letting it
            // linger; the cleanup handler then closes the descriptor.
            dispatchChannel.close(flags: .stop)
        }

        /// Owns the read end and closes it exactly once, from the
        /// `DispatchIO` cleanup handler. A separate object rather than a bare
        /// `FileHandle` capture so what the `@Sendable` cleanup closure holds
        /// is itself `Sendable`, and so the descriptor has one owner: the
        /// channel that reads it.
        private final class HandleCloser: @unchecked Sendable {
            private let handle: FileHandle
            init(_ handle: FileHandle) { self.handle = handle }
            func close() { try? handle.close() }
        }

        private static func makeData(from dispatchData: DispatchData) -> Data {
            var result = Data()
            result.reserveCapacity(dispatchData.count)
            dispatchData.enumerateBytes { buffer, _, _ in
                result.append(buffer)
            }
            return result
        }
    }

    /// A lock-protected box so `deinit` — which is nonisolated — can stop the
    /// readers `launch()` created.
    private final class DescriptorReaderBox: @unchecked Sendable {
        private let lock = NSLock()
        private var readers: [DescriptorReader] = []

        func set(standardOutput: DescriptorReader, standardError: DescriptorReader) {
            lock.lock()
            readers = [standardOutput, standardError]
            lock.unlock()
        }

        func stopAll() {
            lock.lock()
            let pending = readers
            readers.removeAll()
            lock.unlock()
            for reader in pending { reader.stop() }
        }
    }

    /// Bridges `Process.terminationHandler` — a single closure Foundation
    /// fires once — to any number of independent async `wait()` callers.
    /// `@unchecked Sendable` because the lock, not the compiler, is what
    /// makes concurrent `wait()` calls and the one `terminationHandler`
    /// firing safe together.
    private final class ExitWaiter: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        private var waiters: [CheckedContinuation<Int32, Never>] = []

        /// Installs the handler. Call this *before* `process.run()` so there
        /// is no window in which an immediately-exiting child can finish
        /// unobserved.
        init(process: Process) {
            process.terminationHandler = { [weak self] finishedProcess in
                self?.resolve(status: finishedProcess.terminationStatus)
            }
        }

        /// Covers the remaining race explicitly: Foundation may already have
        /// reaped a very short-lived child by the time `run()` returns.
        /// Resolving twice is harmless — `resolve` keeps the first status.
        func resolveIfAlreadyExited(_ process: Process) {
            if !process.isRunning {
                resolve(status: process.terminationStatus)
            }
        }

        private func resolve(status: Int32) {
            lock.lock()
            guard self.status == nil else {
                lock.unlock()
                return
            }
            self.status = status
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            for waiter in pending {
                waiter.resume(returning: status)
            }
        }

        func wait() async -> Int32 {
            if let status = peekStatus() {
                return status
            }
            // The lock usage below is split into plain (non-`async`)
            // methods deliberately: `NSLock.lock()`/`unlock()` are
            // unavailable directly inside an `async` function body under
            // strict concurrency, even when no suspension point sits
            // between them.
            return await withCheckedContinuation { continuation in
                register(continuation)
            }
        }

        private func peekStatus() -> Int32? {
            lock.lock()
            defer { lock.unlock() }
            return status
        }

        private func register(_ continuation: CheckedContinuation<Int32, Never>) {
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    /// A lock-protected box so `waitUntilExit()` and `terminate()` can reach
    /// the `ExitWaiter` installed by `launch()` without actor isolation.
    /// `nonisolated(unsafe)` is deliberately avoided here — the lock is the
    /// actual safety mechanism, not an unchecked promise.
    private final class ExitWaiterBox: @unchecked Sendable {
        private let lock = NSLock()
        private var waiter: ExitWaiter?

        func set(_ waiter: ExitWaiter) {
            lock.lock()
            self.waiter = waiter
            lock.unlock()
        }

        func get() -> ExitWaiter? {
            lock.lock()
            defer { lock.unlock() }
            return waiter
        }
    }
}
