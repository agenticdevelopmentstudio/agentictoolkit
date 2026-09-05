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
            case .launchFailed(let reason):
                return "Failed to launch the subprocess: \(reason)"
            case .exited(let status, let standardError):
                return "The subprocess exited with status \(status): \(standardError)"
            }
        }
    }

    private let configuration: Configuration

    private var process: Process?
    private var standardInputPipe: Pipe?
    private var standardOutputPipe: Pipe?
    private var standardErrorPipe: Pipe?

    private var hasLaunched = false
    private var isTerminated = false

    private var messageStream: AsyncThrowingStream<Data, Error>?
    private var messageContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var pumpTask: Task<Void, Never>?
    private var standardErrorTask: Task<Void, Never>?
    private var standardErrorBuffer = Data()

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
        process.standardInput = standardInputPipe
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        do {
            try process.run()
        } catch {
            // Nothing launched, so there is no running child to leave behind.
            throw ChannelError.launchFailed("\(error)")
        }

        self.process = process
        self.standardInputPipe = standardInputPipe
        self.standardOutputPipe = standardOutputPipe
        self.standardErrorPipe = standardErrorPipe
        hasLaunched = true

        startMessagePump(process: process, standardOutputPipe: standardOutputPipe)
        startStandardErrorDrain(standardErrorPipe: standardErrorPipe)
    }

    /// Framed messages from the child's stdout. Finishes on EOF; throws on a
    /// framing error. Calling this before `launch()` throws `.notLaunched`.
    public func messages() throws -> AsyncThrowingStream<Data, Error> {
        guard let messageStream else { throw ChannelError.notLaunched }
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
    public func sendRaw(_ bytes: Data) throws {
        guard let standardInputPipe else { throw ChannelError.notLaunched }
        try standardInputPipe.fileHandleForWriting.write(contentsOf: bytes)
    }

    /// Closes stdin so the child sees EOF and can finish.
    public func closeInput() {
        try? standardInputPipe?.fileHandleForWriting.close()
    }

    /// Everything the child wrote to stderr, decoded UTF-8. Available after
    /// `terminate()` or normal exit.
    public func standardErrorText() -> String {
        String(data: standardErrorBuffer, encoding: .utf8) ?? ""
    }

    /// Terminates the child if still running, closes all three pipes, and
    /// finishes the message stream. Idempotent.
    public func terminate() {
        guard !isTerminated else { return }
        isTerminated = true

        let pumpTask = pumpTask
        let standardErrorTask = standardErrorTask
        let standardOutputPipe = standardOutputPipe
        let standardErrorPipe = standardErrorPipe

        pumpTask?.cancel()
        standardErrorTask?.cancel()
        if let process, process.isRunning {
            process.terminate()
        }
        messageContinuation?.finish()

        // Stdin is only ever written from this actor, so closing it here is
        // safe; the stdout/stderr *read* ends are a different story.
        try? standardInputPipe?.fileHandleForWriting.close()

        // `FileHandle.AsyncBytes` raises an uncaught `NSFileHandleOperation-
        // Exception` — not a catchable Swift error, so it crashes the whole
        // process — if its file descriptor is closed while a read is still
        // in flight. `pumpTask` and `standardErrorTask` are iterating exactly
        // those file handles, so closing them here on the actor, concurrently
        // with those detached tasks, is that race. Cancelling the tasks and
        // sending the child SIGTERM (above) makes both reads end promptly
        // through ordinary EOF; deferring the close until they actually have
        // finished closes all three pipes as documented, without the race.
        Task.detached {
            _ = await pumpTask?.value
            _ = await standardErrorTask?.value
            try? standardOutputPipe?.fileHandleForReading.close()
            try? standardErrorPipe?.fileHandleForReading.close()
        }
    }

    /// Waits for exit and returns the status. Returns immediately if already
    /// exited.
    public func waitUntilExit() -> Int32 {
        guard let process else { return 0 }
        process.waitUntilExit()
        return process.terminationStatus
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
    /// `messageStream`. Runs detached from the actor so a synchronous
    /// `waitUntilExit()` call never blocks it — it only ever hops onto the
    /// actor implicitly via the `Sendable` continuation it yields to, never
    /// by awaiting an actor method.
    private func startMessagePump(process: Process, standardOutputPipe: Pipe) {
        let processBox = ProcessBox(process)
        let framing = configuration.framing

        var producedContinuation: AsyncThrowingStream<Data, Error>.Continuation!
        let stream = AsyncThrowingStream<Data, Error> { producedContinuation = $0 }
        messageStream = stream
        messageContinuation = producedContinuation
        let continuation = producedContinuation!

        let pumpTask = Task.detached {
            var decoder = MessageFramingDecoder(framing: framing)
            do {
                try await withTaskCancellationHandler {
                    for try await byte in standardOutputPipe.fileHandleForReading.bytes {
                        try Task.checkCancellation()
                        for frame in try decoder.consume(Data([byte])) {
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
                    // eagerly: this loop only observes cancellation on the
                    // next byte, which a silent child never sends —
                    // terminating closes its stdout so the read wakes with
                    // EOF instead of hanging forever.
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
    private func startStandardErrorDrain(standardErrorPipe: Pipe) {
        standardErrorTask = Task.detached {
            var collected = Data()
            do {
                for try await byte in standardErrorPipe.fileHandleForReading.bytes {
                    collected.append(byte)
                }
            } catch {
                // Best-effort: whatever arrived before the read failed (e.g.
                // the pipe was closed out from under it by `terminate()`) is
                // still reported.
            }
            await self.appendStandardError(collected)
        }
    }

    private func appendStandardError(_ data: Data) {
        standardErrorBuffer.append(data)
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
}
