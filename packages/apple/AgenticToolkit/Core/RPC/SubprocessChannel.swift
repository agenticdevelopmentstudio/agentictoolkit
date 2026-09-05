import Darwin
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

    /// Bytes read per `FileHandle.read(upToCount:)` call, for both the
    /// stdout pump and the stderr drain. Feeding `MessageFramingDecoder`
    /// chunks this size, rather than one byte at a time via `FileHandle
    /// .bytes`, is half of what makes decoding linear instead of quadratic —
    /// the other half is the decoder's own scan cursor.
    private static let readChunkSize = 64 * 1024

    /// SIGTERM grace period before `terminate()` escalates to SIGKILL. A
    /// child that traps or ignores SIGTERM must not be able to hang
    /// `terminate()`, or leak the process and its descriptors, forever.
    private static let terminationGraceSeconds: TimeInterval = 2.0

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

    private var process: Process?
    private var standardInputPipe: Pipe?
    private var standardOutputPipe: Pipe?
    private var standardErrorPipe: Pipe?

    private var hasLaunched = false
    private var isTerminated = false
    private var hasVendedMessageStream = false

    private var messageStream: AsyncThrowingStream<Data, Error>?
    private var messageContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var pumpTask: Task<Void, Never>?
    private var standardErrorTask: Task<Void, Never>?
    private var standardErrorBuffer = Data()
    private var isStandardErrorTruncated = false

    public init(configuration: Configuration) {
        self.configuration = configuration
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
        _ = fcntl(standardInputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        process.standardInput = standardInputPipe
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        do {
            try process.run()
        } catch {
            // Nothing launched, so there is no running child to leave behind.
            throw ChannelError.launchFailed("\(error)")
        }

        exitWaiterBox.set(ExitWaiter(process: process))

        self.process = process
        self.standardInputPipe = standardInputPipe
        self.standardOutputPipe = standardOutputPipe
        self.standardErrorPipe = standardErrorPipe
        hasLaunched = true

        startMessagePump(process: process, standardOutputPipe: standardOutputPipe)
        startStandardErrorDrain(standardErrorPipe: standardErrorPipe)
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
    /// empty string. Awaits the drain task's completion first, so this is
    /// deterministic: it never returns a partial capture racing the child's
    /// own exit. That means calling this while the child is still running
    /// blocks until it exits — by design, this is meant to be read after
    /// `terminate()` or normal exit, not mid-run.
    ///
    /// Capped at the last `maximumStandardErrorBytes`; a truncated capture is
    /// prefixed with a marker rather than silently missing its start.
    public func standardErrorText() async -> String {
        _ = await standardErrorTask?.value
        let text = String(bytes: standardErrorBuffer, encoding: .utf8)
            ?? String(bytes: standardErrorBuffer, encoding: .isoLatin1)
            ?? ""
        guard isStandardErrorTruncated else { return text }
        return "[stderr truncated to the last \(Self.maximumStandardErrorBytes) bytes]\n" + text
    }

    /// Terminates the child if still running and finishes the message
    /// stream. Idempotent. A no-op if `launch()` was never called, and that
    /// case does not disarm a later `launch()` + `terminate()` on the same
    /// channel.
    ///
    /// Sends SIGTERM, waits up to `terminationGraceSeconds`, then escalates
    /// to SIGKILL, then closes the stdout/stderr read descriptors
    /// unconditionally — not after waiting for the pump/drain tasks to
    /// observe EOF on their own, which a child launched through a shell
    /// wrapper (`sh -c …`, `npx …`) can withhold forever if a grandchild
    /// still holds the write end. `FileHandle.read(upToCount:)` (unlike the
    /// exception-raising `.bytes` this pump no longer uses) reports a
    /// concurrent close as a catchable Swift error, so forcing the close
    /// here is safe rather than a crash risk.
    public func terminate() async {
        guard hasLaunched else { return }
        guard !isTerminated else { return }
        isTerminated = true

        pumpTask?.cancel()
        standardErrorTask?.cancel()
        messageContinuation?.finish()

        // Stdin is only ever written from this actor, so closing it here is
        // safe; the stdout/stderr read ends are handled below, once the
        // child is confirmed dead or forcibly killed.
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

        try? standardOutputPipe?.fileHandleForReading.close()
        try? standardErrorPipe?.fileHandleForReading.close()
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

    /// Reads the child's stdout, decodes it into frames, and drives
    /// `messageStream`. Runs detached from the actor so `waitUntilExit()`
    /// and `terminate()` never wait behind it.
    private func startMessagePump(process: Process, standardOutputPipe: Pipe) {
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
            let handle = standardOutputPipe.fileHandleForReading
            do {
                try await withTaskCancellationHandler {
                    while true {
                        try Task.checkCancellation()
                        guard let chunk = try handle.read(upToCount: Self.readChunkSize), !chunk.isEmpty else {
                            break
                        }
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
                    // Consuming task cancellation (the consumer went away, or
                    // `terminate()` was called) must tear the child down
                    // eagerly: this loop only observes cancellation between
                    // reads, which a silent child never prompts — terminating
                    // closes its stdout so the read wakes with EOF (or a
                    // thrown error) instead of hanging forever.
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
    /// Captures `self` weakly: a read that never returns (the same
    /// grandchild-holds-the-pipe case `terminate()`'s doc comment describes)
    /// must not keep this actor alive forever just because this task hasn't
    /// noticed yet. If every external reference to the channel is dropped,
    /// this task's `self?.appendStandardError` calls become harmless no-ops
    /// instead of a retain cycle.
    private func startStandardErrorDrain(standardErrorPipe: Pipe) {
        standardErrorTask = Task.detached { [weak self] in
            let handle = standardErrorPipe.fileHandleForReading
            while true {
                let chunk: Data?
                do {
                    chunk = try handle.read(upToCount: Self.readChunkSize)
                } catch {
                    // Best-effort: whatever arrived before the read failed
                    // (e.g. the pipe was closed out from under it by
                    // `terminate()`'s bounded close) is still reported.
                    break
                }
                guard let chunk, !chunk.isEmpty else { break }
                await self?.appendStandardError(chunk)
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

    /// Bridges `Process.terminationHandler` — a single closure Foundation
    /// fires once — to any number of independent async `wait()` callers.
    /// `@unchecked Sendable` because the lock, not the compiler, is what
    /// makes concurrent `wait()` calls and the one `terminationHandler`
    /// firing safe together.
    private final class ExitWaiter: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        private var waiters: [CheckedContinuation<Int32, Never>] = []

        init(process: Process) {
            process.terminationHandler = { [weak self] finishedProcess in
                self?.resolve(status: finishedProcess.terminationStatus)
            }
            // The process may already have exited before this handler was
            // installed (an immediately-failing child). `terminationHandler`
            // is documented to still fire for an already-terminated process,
            // but this covers the race explicitly rather than relying on
            // that timing.
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
