//
//  LanguageServerSession.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Foundation
import LanguageClient
import LanguageServerProtocol
import OSLog

/// Why a session is not running, and what the server said about it on the way
/// down. Both halves matter: a language server that fails to start almost
/// always explains itself on stderr, and losing that text makes the next bug a
/// guessing game.
public struct LanguageServerFailure: Sendable {

    /// The framing error, the unexpected exit, or the handshake failure that
    /// ended the session. The **first** cause wins: a transport error that
    /// killed the child is a better explanation than the
    /// `dataStreamClosed` or wall-clock expiry it goes on to produce.
    public let error: any Error

    /// Everything the child wrote to stderr, bounded and possibly prefixed with
    /// a truncation marker — see `SubprocessChannel.standardErrorText()`.
    public let standardErrorText: String

    public init(error: any Error, standardErrorText: String) {
        self.error = error
        self.standardErrorText = standardErrorText
    }
}

/// Explicit state rather than an optional error nobody reads: a session that
/// died from a framing error must be distinguishable from one that shut down
/// because we asked it to.
public enum LanguageServerSessionState: Sendable {
    /// Never started.
    case idle
    /// `start()` is in flight. A child may or may not exist yet.
    case starting
    /// The `initialize` handshake completed; the server is usable.
    case running
    /// `stop()` completed. Terminal.
    case stopped
    /// The server died, or never started. Terminal.
    case failed(LanguageServerFailure)
}

extension LanguageServerSessionState {
    /// The failure, when there is one. Saves every caller a `case` binding.
    public var failure: LanguageServerFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}

/// `Equatable` so a caller — and every test in `LanguageServerSessionTests` —
/// can say *which* failure it expects rather than only that one happened.
public enum LanguageServerSessionError: Error, LocalizedError, Sendable, Equatable {
    /// `start()` was called on a session whose `stop()` has already run.
    /// Stopping is terminal; restarting means a new session, because
    /// `SubprocessChannel` is single-launch.
    case sessionHasBeenStopped
    /// The server's stdout ended without a framing error and without our
    /// asking — it exited on its own. `status` is `nil` when the exit status
    /// could not be collected within its budget (a backgrounded grandchild can
    /// hold the descriptors open indefinitely).
    case serverExited(status: Int32?)
    /// A request was made on a session that is not `.running`.
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .sessionHasBeenStopped:
            "The language server session was stopped; start a new session instead."
        case .serverExited(let status):
            if let status {
                "The language server exited with status \(status)."
            } else {
                "The language server exited."
            }
        case .notRunning:
            "The language server is not running."
        }
    }
}

/// The surface the registry and Tasks 3.2-3.6 consume. Backed by
/// `LanguageServerSession` in production; tests substitute a fake conforming
/// type via `LanguageServerRegistry.SessionFactory`.
public protocol LanguageServerSessionProtocol: Actor {
    nonisolated var id: UUID { get }
    nonisolated var name: String { get }
    /// Every LSP language id this server serves. Plain `String`s: the
    /// `CodeLanguage` -> language-id mapping lives in `AgenticToolkitMacOS`,
    /// which sits *above* this target.
    nonisolated var languageIds: [String] { get }

    var state: LanguageServerSessionState { get }

    func start() async throws
    func stop() async
}

/// One running language server: the child process, the JSON-RPC plumbing over
/// it, and the `initialize` handshake.
///
/// The stack, and who owns what:
///
/// ```
/// SubprocessChannel(framing: .contentLength)   <- this actor owns the child
///   -> LanguageServerChannel -> JSONRPC.DataChannel
///   -> JSONRPCServerConnection(dataChannel:, addMessageFraming: false)
///   -> InitializingServer                      <- does the handshake
/// ```
///
/// `InitializingServer` already performs the `initialize` handshake lazily,
/// special-cases `shutdown` and `exit`, and tracks capabilities the server
/// registers and deregisters at runtime. None of that is rewritten here.
///
/// There is exactly **one** owner of the child — this actor, through its
/// `SubprocessChannel` — so there is no second `Process` to fall out of step
/// with, the defect that shaped `MCPClient`.
public actor LanguageServerSession: LanguageServerSessionProtocol {

    public struct Configuration: Sendable {
        public var id: UUID
        public var name: String
        public var languageIds: [String]
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        /// The workspace root sent as `rootUri`. `LanguageServerRegistry`
        /// resolves it from the configuration's root markers.
        public var rootURL: URL
        /// How long `start()` waits for the `initialize` handshake. A cold
        /// `sourcekit-lsp` indexing a large package is the slow case; the
        /// bound exists so a server that never answers cannot wedge a caller.
        public var initializeBudgetSeconds: TimeInterval
        /// How long the graceful `shutdown` + `exit` half of teardown may take
        /// before `SubprocessChannel.terminate()` takes over. A server that
        /// ignores `shutdown` must not hold up the app.
        public var shutdownBudgetSeconds: TimeInterval
        public var clientName: String
        public var clientVersion: String

        public init(
            id: UUID = UUID(),
            name: String,
            languageIds: [String],
            executableURL: URL,
            arguments: [String] = [],
            environment: [String: String] = [:],
            rootURL: URL,
            initializeBudgetSeconds: TimeInterval = 30,
            shutdownBudgetSeconds: TimeInterval = 2,
            clientName: String = "AgenticToolkit",
            clientVersion: String = "1.0.0"
        ) {
            self.id = id
            self.name = name
            self.languageIds = languageIds
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.rootURL = rootURL
            self.initializeBudgetSeconds = initializeBudgetSeconds
            self.shutdownBudgetSeconds = shutdownBudgetSeconds
            self.clientName = clientName
            self.clientVersion = clientVersion
        }
    }

    /// How long the exit status of a server whose stdout has already ended is
    /// waited for. Bounded because a child that has exited while a grandchild
    /// it backgrounded still holds the descriptors makes the wait unbounded —
    /// the same hazard `SubprocessChannel.standardErrorText()` documents.
    private static let exitStatusBudgetSeconds: TimeInterval = 1

    public nonisolated let id: UUID
    public nonisolated let name: String
    public nonisolated let languageIds: [String]

    /// The initialized server, once `start()` has completed. Tasks 3.2-3.6
    /// send their notifications and requests through this.
    public private(set) var server: InitializingServer?

    public private(set) var state: LanguageServerSessionState = .idle

    /// Set by `stop()` before its first suspension, and never cleared.
    ///
    /// This is the flag every concurrent path reads, and it is why `state`
    /// alone is not enough: a `stop()` that runs to completion *before* a
    /// queued `start()` has entered this actor leaves nothing for teardown to
    /// find, and without the flag that `start()` would spawn a child no one
    /// holds a reference to. Mirrors `MCPClient.isShutDown`, for the same
    /// reason and the same reachable ordering (the registry starts both from
    /// unstructured `Task`s).
    private var isStopped = false

    private let configuration: Configuration
    private var channel: SubprocessChannel?
    private var bridge: LanguageServerChannel?

    /// Where the stream-end handler records what it saw, **synchronously**.
    ///
    /// The handler also hops onto this actor to publish `.failed`, but that hop
    /// is a suspension, and `start()`'s own failure path runs concurrently with
    /// it. Reading the box instead of waiting for the hop is what makes "the
    /// transport error beats the `dataStreamClosed` it caused" a guarantee
    /// rather than a race.
    private nonisolated let streamEnd = StreamEndBox()

    public init(configuration: Configuration) {
        self.id = configuration.id
        self.name = configuration.name
        self.languageIds = configuration.languageIds
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Spawns the server, builds the JSON-RPC stack over it, and runs the
    /// `initialize` handshake under `initializeBudgetSeconds`.
    ///
    /// Every guard here is decided **before** the suspension it protects, and
    /// the state is published before the suspension rather than after it — the
    /// `.starting` case exists precisely because a `Bool` cannot express "a
    /// child may already be running but `start()` has not resumed to record
    /// it", and a `stop()` landing in that window would otherwise find nothing
    /// to reap.
    ///
    /// Calling twice is a no-op; a concurrent second call made while the first
    /// is still `.starting` is the same no-op and returns immediately rather
    /// than waiting. On failure the session lands in `.failed`, carrying the
    /// cause and the server's stderr, and the error is rethrown.
    public func start() async throws {
        guard !isStopped else { throw LanguageServerSessionError.sessionHasBeenStopped }
        guard case .idle = state else { return }
        // Claimed before the first suspension. From here until this method
        // returns, `stop()` must behave as though a child exists, because for
        // most of that span one does.
        state = .starting

        let channel = SubprocessChannel(configuration: .init(
            executableURL: configuration.executableURL,
            arguments: configuration.arguments,
            environment: configuration.environment,
            // A language server needs `PATH` and `HOME` to launch at all, and
            // a configuration only ever carries overrides.
            environmentPolicy: .mergeOverParent,
            // Module-qualified: `LanguageServerProtocol` declares its own
            // `MessageFraming`, so the bare name is ambiguous in this file.
            // Both types are load-bearing; neither gets renamed.
            framing: AgenticToolkitCore.MessageFraming.contentLength
        ))
        // Published before the launch suspension, so a `stop()` that lands
        // mid-launch has something to terminate. `terminate()` guards on the
        // channel's own `hasLaunched`, so it is a no-op if the spawn has not
        // happened yet and a real kill if it has.
        self.channel = channel

        let connected: LanguageServerChannel
        do {
            connected = try await LanguageServerChannel.connect(over: channel) { [weak self] error in
                self?.recordStreamEnd(error)
            }
        } catch {
            let cause = await diagnosedCause(for: error)
            await fail(with: cause)
            await teardown()
            throw cause
        }

        // A `stop()` that landed while the line above was suspended has already
        // terminated the channel. Building a JSON-RPC stack over a dead child
        // would publish a server nobody can use.
        guard case .starting = state else { return }
        self.bridge = connected

        // `addMessageFraming: false`: `SubprocessChannel` already frames.
        let connection = JSONRPCServerConnection(
            dataChannel: connected.dataChannel,
            addMessageFraming: false
        )
        let params = makeInitializeParams()
        let server = InitializingServer(server: connection) { params }
        self.server = server

        do {
            let budget = configuration.initializeBudgetSeconds
            _ = try await withWallClockBudget(budget) { try await server.initializeIfNeeded() }
        } catch {
            let cause = await diagnosedCause(for: error)
            await fail(with: cause)
            await teardown()
            throw cause
        }

        guard case .starting = state else { return }
        state = .running
    }

    /// Stops the server and retires this session permanently.
    ///
    /// Teardown is ordered, and the graceful half is bounded:
    /// `shutdown` request, then `exit` notification (both inside
    /// `InitializingServer.shutdownAndExit()`, under
    /// `shutdownBudgetSeconds`), then `SubprocessChannel.terminate()` as the
    /// backstop, which always runs.
    ///
    /// `terminate()` costs up to 2.5 s flat per channel, is **not** cancellable,
    /// and the budgets do not share between channels — so a caller stopping
    /// several sessions must do it in a `withTaskGroup`, never a `for` loop.
    /// `LanguageServerRegistry.reconcile` is the only multi-session teardown
    /// path in this task and does exactly that.
    ///
    /// A session that had already `.failed` keeps that state: how it died is
    /// more useful than the fact that it was then stopped.
    public func stop() async {
        // Set before the first suspension, so it is visible to every `start()`
        // that has not already entered this actor.
        isStopped = true
        await teardown()
        if case .failed = state { return }
        state = .stopped
    }

    /// Everything the server wrote to stderr. Available after a failure (where
    /// it is also carried on the failure state) and while running.
    public func standardErrorText() async -> String {
        guard let channel else { return "" }
        return await channel.standardErrorText()
    }

    /// The server's capabilities, or `nil` if it is not initialized.
    /// Tasks 3.3-3.6 gate their features on this.
    public func capabilities() async -> ServerCapabilities? {
        guard let server else { return nil }
        return await server.capabilities
    }

    // MARK: - Teardown

    private func teardown() async {
        if let server {
            let budget = configuration.shutdownBudgetSeconds
            do {
                try await withWallClockBudget(budget) { try await server.shutdownAndExit() }
            } catch {
                // A server that ignores `shutdown`, or that is already dead, is
                // not a teardown failure — `terminate()` below is the answer to
                // both. Losing the reason would make a hung shutdown invisible,
                // so it is logged and not rethrown.
                let message = error.localizedDescription
                logger.debug("Graceful LSP shutdown did not complete: \(message, privacy: .public)")
            }
        }

        // The backstop, unconditional: it is what makes this actor the only
        // owner of the child.
        await channel?.terminate()

        // `terminate()` finishes the frame stream itself, after waiting out its
        // own pump-drain grace, so this is already finishing or done. Waiting
        // is what delivers the frames a graceful child wrote between SIGTERM
        // and `exit`; finishing without waiting would discard them.
        await bridge?.drain()

        server = nil
        bridge = nil
        // `channel` is deliberately kept: it is terminated and inert, and it is
        // where `standardErrorText()` reads from after a failure.
    }

    // MARK: - Failure

    /// Called synchronously from the bridge's stream-end handler, off this
    /// actor. Records first, then hops on to publish — see `streamEnd`.
    private nonisolated func recordStreamEnd(_ error: (any Error)?) {
        streamEnd.record(error)
        Task { [weak self] in await self?.publishStreamEnd() }
    }

    private func publishStreamEnd() async {
        // A stop we asked for ends the stream too; that is not a failure.
        guard !isStopped else { return }
        switch state {
        case .idle, .stopped, .failed: return
        case .starting, .running: break
        }
        let cause = await diagnosedCause(for: LanguageServerSessionError.notRunning)
        await fail(with: cause)
    }

    /// The most informative cause for a failure that surfaced as `fallback`.
    ///
    /// A stream that has already ended explains *why* a request failed;
    /// `ProtocolTransportError.dataStreamClosed` or a `WallClockBudgetExceeded`
    /// only says that it did. Reading the box is synchronous, so this does not
    /// race the handler's own hop onto this actor.
    private func diagnosedCause(for fallback: any Error) async -> any Error {
        let ended = streamEnd.value
        guard ended.didEnd else { return fallback }
        if let error = ended.error { return error }
        return LanguageServerSessionError.serverExited(status: await exitStatus())
    }

    private func exitStatus() async -> Int32? {
        guard let channel else { return nil }
        return try? await withWallClockBudget(Self.exitStatusBudgetSeconds) {
            await channel.waitUntilExit()
        }
    }

    /// Publishes `.failed`, first cause wins.
    ///
    /// Both guards are repeated after the stderr read: that read is a
    /// suspension long enough for a `stop()` or a second failure to land, and
    /// overwriting either would replace the real explanation with a
    /// consequence of it.
    private func fail(with error: any Error) async {
        guard !isStopped else { return }
        switch state {
        case .stopped, .failed: return
        case .idle, .starting, .running: break
        }
        let text = await channel?.standardErrorText() ?? ""
        guard !isStopped else { return }
        switch state {
        case .stopped, .failed: return
        case .idle, .starting, .running: break
        }
        state = .failed(LanguageServerFailure(error: error, standardErrorText: text))
    }

    // MARK: - Handshake

    /// Declares **only** what Tasks 3.2-3.6 implement: text document sync,
    /// completion, hover, definition, publishDiagnostics and semanticTokens.
    ///
    /// Nothing else — no workspace edits, no code actions, no rename. A server
    /// told we support a capability we do not honour sends requests we drop on
    /// the floor, and the failure then surfaces as the editor mysteriously not
    /// working rather than as an error.
    private static let clientCapabilities = ClientCapabilities(
        workspace: nil,
        textDocument: TextDocumentClientCapabilities(
            synchronization: TextDocumentSyncClientCapabilities(
                dynamicRegistration: false,
                willSave: false,
                willSaveWaitUntil: false,
                didSave: true
            ),
            completion: CompletionClientCapabilities(
                dynamicRegistration: false,
                completionItem: CompletionClientCapabilities.CompletionItem(
                    snippetSupport: false,
                    commitCharactersSupport: false,
                    documentationFormat: [.markdown, .plaintext],
                    deprecatedSupport: true,
                    preselectSupport: false
                ),
                contextSupport: true
            ),
            hover: HoverClientCapabilities(
                dynamicRegistration: false,
                contentFormat: [.markdown, .plaintext]
            ),
            definition: DefinitionClientCapabilities(
                dynamicRegistration: false,
                linkSupport: true
            ),
            publishDiagnostics: PublishDiagnosticsClientCapabilities(
                relatedInformation: true,
                versionSupport: true
            ),
            semanticTokens: SemanticTokensClientCapabilities()
        ),
        window: nil,
        general: nil,
        experimental: nil
    )

    private func makeInitializeParams() -> InitializeParams {
        InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            clientInfo: InitializeParams.ClientInfo(
                name: configuration.clientName,
                version: configuration.clientVersion
            ),
            locale: nil,
            rootPath: nil,
            rootUri: configuration.rootURL.documentUri,
            initializationOptions: nil,
            capabilities: Self.clientCapabilities,
            trace: nil,
            workspaceFolders: nil
        )
    }
}

extension LanguageServerSession: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// The one stream-end record for a session, written from off-actor and read
/// on-actor without a suspension in between.
///
/// `@unchecked Sendable` because the lock, not the compiler, is what makes the
/// first-write-wins and the synchronous read hold.
private final class StreamEndBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didEnd = false
    private var error: (any Error)?

    /// Records the first end. Later calls are ignored: the stream ends once,
    /// and a second report could only be less informative.
    func record(_ error: (any Error)?) {
        lock.lock()
        defer { lock.unlock() }
        guard !didEnd else { return }
        didEnd = true
        self.error = error
    }

    var value: (didEnd: Bool, error: (any Error)?) {
        lock.lock()
        defer { lock.unlock() }
        return (didEnd, error)
    }
}
