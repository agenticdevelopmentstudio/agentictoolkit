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
    /// A document notification or an LSP request was made on a session that is
    /// not `.running`.
    ///
    /// Every traffic method on `LanguageServerSessionProtocol` throws this
    /// rather than writing into a transport that is starting, torn down, or
    /// dead. That check is the reason the session vends *methods* instead of
    /// its `InitializingServer`: a handle handed out once keeps working after
    /// `stop()` has closed the descriptor underneath it, and a write into a
    /// closed descriptor is how `JSONRPCSession` ends up resuming one
    /// continuation twice.
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
///
/// LSP traffic is expressed as **methods on this protocol**, not as a handle to
/// the underlying `InitializingServer`. Two reasons, and both are load-bearing:
///
/// - A fake has to be implementable in a few lines. Vending an
///   `InitializingServer` would make every fake either spawn a real child or
///   stop being able to stand in at all, and `LanguageServerRegistry` only ever
///   hands out `any LanguageServerSessionProtocol`.
/// - A handle is an unrevoked capability. Its holder keeps sending after
///   `stop()`, into a descriptor `SubprocessChannel.terminate()` has closed.
///   A method checks `state` on the actor first and throws `.notRunning`.
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

    // MARK: What the server can do

    /// The server's capabilities, or `nil` if it is not initialized.
    /// Tasks 3.3-3.6 gate their features on this.
    ///
    /// **Every conformer must answer `nil` unless the session is `.running`** —
    /// not merely "has a server" or "has ever initialized". A caller is
    /// entitled to read a non-`nil` answer as "this session is live and offers
    /// this capability", and `LSPCompletionDelegate` depends on exactly that
    /// reading: its cache-hit guard and its opportunistic re-cache in
    /// `completionSuggestionsRequested` both rely on this method going `nil`
    /// for a dead session instead of re-checking liveness at every call site
    /// (`LSPCompletionDelegate.swift:262-276`). This is stated here, on the
    /// protocol, because it once was not: this task exists because
    /// `LanguageServerSession`'s implementation and a test fake diverged on
    /// exactly this method, and a contract that lives only on one conformer
    /// leaves the next conformer free to diverge the same way.
    func capabilities() async -> ServerCapabilities?

    /// Everything the server wrote to stderr, bounded. The one place a
    /// "the editor has no completions and nobody knows why" report can be
    /// turned into a cause.
    func standardErrorText() async -> String

    // MARK: Document synchronisation

    /// `textDocument/didOpen`. Task 3.2 sends one per editor that opens a file
    /// this server claims; a server that never sees the open answers every
    /// later request with "unknown document".
    func didOpen(_ params: DidOpenTextDocumentParams) async throws

    /// `textDocument/didChange`. Task 3.2's edit forwarding. The server's view
    /// of the buffer is only as current as the last of these it received.
    func didChange(_ params: DidChangeTextDocumentParams) async throws

    /// `textDocument/didSave`. Declared in `clientCapabilities`
    /// (`didSave: true`), so a server may legitimately wait for it — several
    /// only re-run diagnostics on save.
    func didSave(_ params: DidSaveTextDocumentParams) async throws

    /// `textDocument/didClose`. Task 3.2's counterpart to `didOpen`; without it
    /// a server keeps indexing buffers no editor is showing any more.
    func didClose(_ params: DidCloseTextDocumentParams) async throws

    // MARK: Requests

    /// `textDocument/completion` — Task 3.3.
    func completion(_ params: CompletionParams) async throws -> CompletionResponse

    /// `textDocument/hover` — Task 3.4, alongside push diagnostics below.
    func hover(_ params: TextDocumentPositionParams) async throws -> HoverResponse

    /// `textDocument/definition` — Task 3.3's go-to-definition.
    func definition(_ params: TextDocumentPositionParams) async throws -> DefinitionResponse

    /// `textDocument/diagnostic`, the **pull** model. Nothing calls it.
    ///
    /// Task 3.4 built the diagnostics the editor actually shows on the *push*
    /// model — `publishedDiagnostics` below — because that is what servers
    /// send unasked and what makes a squiggle appear without a poll. This
    /// stays because the request is part of the surface a server may prefer,
    /// and removing it would cost a later task the round trip to add it back.
    func diagnostics(_ params: DocumentDiagnosticParams) async throws -> DocumentDiagnosticReport

    /// `textDocument/semanticTokens/full` — Task 3.5.
    func semanticTokensFull(_ params: SemanticTokensParams) async throws -> SemanticTokensResponse

    // MARK: What the server says without being asked

    /// Every `textDocument/publishDiagnostics` the server pushes, in the order
    /// it sent them.
    ///
    /// This is the only server-initiated traffic any conformer surfaces, and
    /// it is a stream rather than a request because push diagnostics have no
    /// request: a server sends them when it decides it has something to say.
    ///
    /// **Ordering.** Diagnostics arrive in send order, because one task drains
    /// one `AsyncStream` and yields into another unbounded one in receipt
    /// order. **No ordering is guaranteed against traffic the client sent.** A
    /// `publishDiagnostics` received just after a `didChange` need not reflect
    /// that change — it may well be the previous version's answer, still in
    /// flight — so a consumer must not treat receipt as acknowledgement.
    ///
    /// **One consumer, and only one.** `AsyncStream` supports a single
    /// iterator: two `for await` loops over this property split the events
    /// between them arbitrarily and neither sees them all. The symptom is
    /// "some diagnostics randomly missing", which is close to undiagnosable
    /// from a bug report. `DiagnosticStore` is the one consumer; anything else
    /// that wants diagnostics subscribes to the store.
    ///
    /// **When it finishes.** On `stop()`, and on a `start()` that failed —
    /// both route through `teardown()`, which is the only place the
    /// continuation is finished. It does **not** finish when a running server
    /// dies on its own: that path publishes `.failed` and leaves the session
    /// standing, so the stream stays open until someone stops the session. A
    /// consumer that cannot wait for that must cancel its own iteration, which
    /// is what `DiagnosticStore.shutdown()` does.
    nonisolated var publishedDiagnostics: AsyncStream<PublishDiagnosticsParams> { get }

    /// Every transition this session's `state` makes, in the order it made
    /// them.
    ///
    /// A stream rather than a poll because a lifecycle failure is a *moment*,
    /// not a value anyone thinks to go and read: a server whose `start()` threw
    /// stays in `LanguageServerRegistry.sessions` looking exactly like one that
    /// started, `$sessions` never emits again, and the only trace of the
    /// failure is one line in the log. This is the signal that carries it out.
    ///
    /// **Ordering.** Transitions arrive in the order they were written, because
    /// every write goes through one synchronous helper on the actor — the state
    /// is assigned and yielded in the same actor step, with no suspension
    /// between them, so no second writer can interleave.
    ///
    /// **One consumer, and only one.** `AsyncStream` supports a single
    /// iterator: two `for await` loops over this property split the transitions
    /// between them arbitrarily and neither sees them all, which shows up as a
    /// status indicator that is stuck on a state the server left. The one
    /// consumer is `LanguageServerRegistry`, which republishes what it reads as
    /// `sessionStates`; anything that wants a session's state observes the
    /// registry.
    ///
    /// **When it finishes.** At the end of `stop()`, after the terminal state
    /// has been yielded — deliberately **not** in `teardown()`, which is where
    /// `publishedDiagnostics` finishes. The asymmetry is forced by `stop()`:
    /// teardown is where the *transport* dies, but this stream's last word,
    /// `.stopped`, is written *after* teardown returns. Finishing in teardown
    /// would yield `.stopped` into a finished continuation, where it is
    /// silently dropped, and the last thing a status panel ever heard about a
    /// server the user just disabled would be "running".
    ///
    /// It does **not** finish when a running server dies on its own: that path
    /// publishes `.failed` and leaves the session standing, exactly as
    /// `publishedDiagnostics` does. A `.failed` nobody can read is the defect
    /// this stream exists to fix.
    ///
    /// **What it is not:** a replacement for `state`. A consumer that wants the
    /// current value asks the actor; this carries transitions. A late
    /// subscriber misses what already happened, which is why
    /// `LanguageServerRegistry` subscribes at the moment it creates a session
    /// and seeds the initial `.idle` itself.
    nonisolated var stateChanges: AsyncStream<LanguageServerSessionState> { get }
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
        /// How long `stop()` waits for a `start()` it is racing before it
        /// abandons it and tears down anyway. See `teardown()` step 1: the
        /// wait is what makes the child reapable, and the bound is what stops
        /// a server that never answers `initialize` from wedging app quit.
        public var abandonedStartBudgetSeconds: TimeInterval
        /// How long `teardown()` waits for requests already on the wire before
        /// it closes the transport under them. See `teardown()` step 2: the
        /// wait is what keeps a request write from failing into a responder
        /// `readSequenceFinished()` has already drained — one
        /// `CheckedContinuation` resumed twice, which traps the process — and
        /// the bound is what stops a server that answers nothing from wedging
        /// app quit.
        ///
        /// Larger than `shutdownBudgetSeconds` on purpose: a request the user
        /// just issued has a reply coming, where a `shutdown` a server is
        /// ignoring never will.
        public var outstandingRequestBudgetSeconds: TimeInterval
        /// How long the exit status of a server whose stdout has already ended
        /// is waited for. Bounded because a child that has exited while a
        /// grandchild it backgrounded still holds the descriptors makes the
        /// wait unbounded — the same hazard
        /// `SubprocessChannel.standardErrorText()` documents.
        public var exitStatusBudgetSeconds: TimeInterval
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
            abandonedStartBudgetSeconds: TimeInterval = 1,
            outstandingRequestBudgetSeconds: TimeInterval = 2,
            exitStatusBudgetSeconds: TimeInterval = 1,
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
            self.abandonedStartBudgetSeconds = abandonedStartBudgetSeconds
            self.outstandingRequestBudgetSeconds = outstandingRequestBudgetSeconds
            self.exitStatusBudgetSeconds = exitStatusBudgetSeconds
            self.clientName = clientName
            self.clientVersion = clientVersion
        }
    }

    public nonisolated let id: UUID
    public nonisolated let name: String
    public nonisolated let languageIds: [String]

    /// The initialized server, once `start()` has completed.
    ///
    /// **Private, and it stays private.** Every caller reaches the server
    /// through the traffic methods below, which check `state` on this actor
    /// first. A handed-out reference cannot be revoked by `stop()`: its holder
    /// would keep writing into a descriptor `terminate()` has closed, which is
    /// the JSONRPC path that resumes one continuation twice and traps the
    /// process.
    private var server: InitializingServer?

    /// Written **only** through `setState(_:)`, so that every transition is
    /// published on `stateChanges` by construction rather than by inspection.
    /// The `.idle` default is the one exception, and it is not a transition:
    /// nothing is subscribed at initialiser time, and yielding into a stream
    /// nobody holds would be a lie about ordering. The registry seeds `.idle`
    /// itself, at the moment it creates the session.
    public private(set) var state: LanguageServerSessionState = .idle

    /// The in-flight `start()`, held so `stop()` can wait for it.
    ///
    /// This is what makes teardown *ordered with respect to* the start rather
    /// than concurrent with it — see `teardown()` step 1. `MCPClient` holds its
    /// `connectTask` for exactly the same reason and against exactly the same
    /// ordering: work that publishes a child from inside a suspension cannot be
    /// torn down beside it, only after it.
    private var startTask: Task<Void, Error>?

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

    /// How many request round trips are on the wire right now.
    ///
    /// The counterpart of `startTask` for the *other* half of this file's
    /// traffic, and it exists for the same reason: a request publishes a write
    /// to the child's stdin from inside a suspension, where no guard on this
    /// actor can see it, so teardown cannot be sound beside one — only after
    /// it. Requests only, not notifications: a notification write that fails
    /// after the transport is gone throws a transport error its caller can act
    /// on, where a request write that fails after `readSequenceFinished()` has
    /// drained its responder resumes one `CheckedContinuation` twice, which is
    /// a `fatalError`.
    ///
    /// Maintained only by `trackingOutstandingRequest(_:)`, whose `defer` is
    /// what makes the decrement unconditional across return, throw and
    /// cancellation alike.
    private var outstandingRequests = 0

    /// Teardowns parked on `outstandingRequests` reaching zero.
    ///
    /// Keyed rather than a bare array so that resuming one is a
    /// `removeValue(forKey:)` — exactly-once by construction, which is the
    /// property this whole change exists to protect and therefore the last
    /// place to reintroduce a double resume. More than one entry is possible:
    /// `stop()` is idempotent but not serialised, and `start()`'s failure path
    /// tears down too.
    private var requestBarrierWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Where the stream-end handler records what it saw, **synchronously**.
    ///
    /// The handler also hops onto this actor to publish `.failed`, but that hop
    /// is a suspension, and `start()`'s own failure path runs concurrently with
    /// it. Reading the box instead of waiting for the hop is what makes "the
    /// transport error beats the `dataStreamClosed` it caused" a guarantee
    /// rather than a race.
    private nonisolated let streamEnd = StreamEndBox()

    /// Server-pushed `textDocument/publishDiagnostics`. See the protocol
    /// requirement for the ordering and single-consumer contracts.
    public nonisolated let publishedDiagnostics: AsyncStream<PublishDiagnosticsParams>

    /// The write end of `publishedDiagnostics`.
    ///
    /// `nonisolated let` on purpose: it is yielded into from the drain task
    /// below, synchronously, with no isolated state read across a suspension —
    /// the same shape `DocumentSyncPipeline` uses and for the same reason. An
    /// isolated method for the drain loop to call would put a hop between the
    /// event arriving and the event being published, and the ordering
    /// guarantee would go with it.
    private nonisolated let diagnosticsContinuation: AsyncStream<PublishDiagnosticsParams>.Continuation

    /// Every transition `state` makes. See the protocol requirement for the
    /// ordering, single-consumer and finish contracts.
    public nonisolated let stateChanges: AsyncStream<LanguageServerSessionState>

    /// The write end of `stateChanges`.
    ///
    /// `nonisolated let` for the same reason as `diagnosticsContinuation`: it
    /// is yielded into synchronously from `setState(_:)`, in the same actor
    /// step as the assignment it reports, so nothing can interleave between
    /// the write and its publication.
    ///
    /// Default (unbounded) buffering, deliberately. A `.bufferingNewest(1)`
    /// would drop `.starting` whenever `.running` followed it quickly, and
    /// `.starting` is exactly the transition that distinguishes "still
    /// handshaking" from "never started".
    private nonisolated let stateContinuation: AsyncStream<LanguageServerSessionState>.Continuation

    /// Drains `InitializingServer.eventSequence` for the one notification this
    /// session re-exposes. Held so `teardown()` can end it.
    ///
    /// It deliberately captures neither `self` nor anything isolated: a drain
    /// loop that reached back onto this actor would suspend inside the loop,
    /// and every guard it read would be stale by the time it published.
    private var eventDrainTask: Task<Void, Never>?

    public init(configuration: Configuration) {
        self.id = configuration.id
        self.name = configuration.name
        self.languageIds = configuration.languageIds
        self.configuration = configuration
        let (stream, continuation) = AsyncStream.makeStream(of: PublishDiagnosticsParams.self)
        self.publishedDiagnostics = stream
        self.diagnosticsContinuation = continuation
        let (states, stateContinuation) = AsyncStream.makeStream(of: LanguageServerSessionState.self)
        self.stateChanges = states
        self.stateContinuation = stateContinuation
    }

    /// The **only** writer of `state`, and the reason `stateChanges` can
    /// promise ordering: the assignment and the yield are one actor step, so a
    /// consumer reads transitions in the order they were made.
    private func setState(_ next: LanguageServerSessionState) {
        state = next
        stateContinuation.yield(next)
    }

    // MARK: - Lifecycle

    /// Spawns the server, builds the JSON-RPC stack over it, and runs the
    /// `initialize` handshake under `initializeBudgetSeconds`.
    ///
    /// The work runs in a **held task** (`startTask`) rather than inline, so a
    /// concurrent `stop()` has something to wait for. That is the whole
    /// lifecycle argument, and the guards are not a substitute for it: a guard
    /// decided before a suspension protects the *actor's* state, but the child
    /// process and the child's stdin are external resources that
    /// `LanguageServerChannel.connect` and `initializeIfNeeded()` publish from
    /// inside their suspensions, where no guard on this actor can see them. A
    /// `stop()` that tore down beside such a suspension would leave an
    /// unreapable child (`SubprocessChannel.terminate()` before `launch()` is a
    /// no-op that sets no barrier) or close stdin under an in-flight
    /// `initialize` write. `teardown()` waits instead.
    ///
    /// What the guards do cover: `isStopped` is decided before this method's
    /// first suspension, so a `stop()` that completed first can never be
    /// overtaken; and `.starting` is published before the first suspension so a
    /// `stop()` landing mid-start sees a session that claims to own a child.
    ///
    /// **Every caller learns the outcome, not just the first one.** A second
    /// call landing while the first is still `.starting` joins the held
    /// `startTask` and returns — or throws — exactly when the first does; a
    /// call on a `.running` session returns; a call on a `.failed` one throws
    /// the failure's cause. That matters because more than one component starts
    /// a session on purpose: `LanguageServerRegistry.reconcile` starts every
    /// session it creates, and `LanguageServerDocumentSync` starts every session
    /// it sees, since `start()` returning is the only "the handshake is done"
    /// signal a session has. When the loser returned immediately, it went on to
    /// ask `capabilities()` of a session that had no `InitializingServer` yet,
    /// got `nil`, and concluded the server had published no capabilities at all.
    ///
    /// On failure the session lands in `.failed`, carrying the cause and the
    /// server's stderr, and the error is rethrown — to every caller.
    public func start() async throws {
        guard !isStopped else { throw LanguageServerSessionError.sessionHasBeenStopped }

        switch state {
        case .idle:
            break

        case .starting:
            // The handle exists for exactly this: it is held from the statement
            // after `setState(.starting)` — with no suspension in between, so
            // a joiner that observes `.starting` observes the task too — and
            // `teardown()` already waits on it the same way.
            //
            // The one exception is the sliver in which the owning call has
            // caught a failure, cleared the handle, and is suspended inside
            // `fail(with:)` collecting stderr. A joiner there returns without a
            // running server, which is the pre-existing behaviour and is
            // harmless: every traffic method and `capabilities()` gate on
            // `.running`, so the joiner's next question gets the same answer the
            // `.failed` it is about to see would have given.
            if let startTask {
                try await startTask.value
            }
            return

        case .running:
            return

        case .failed(let failure):
            throw failure.error

        case .stopped:
            // Unreachable: `isStopped` is set before `stop()`'s first
            // suspension and is checked above. Throwing rather than returning
            // keeps the two spellings of "stopped" answering alike.
            throw LanguageServerSessionError.sessionHasBeenStopped
        }

        // Claimed before the first suspension. From here until this method
        // returns, `stop()` must behave as though a child exists, because for
        // most of that span one does.
        setState(.starting)

        let task = Task { try await self.performStart() }
        startTask = task
        do {
            try await task.value
            if startTask == task { startTask = nil }
        } catch {
            // Cleared *before* the teardown below, so that teardown's step 1
            // does not try to await the task it is running inside.
            if startTask == task { startTask = nil }
            await fail(with: error)
            await teardown()
            throw error
        }
    }

    /// The body of `start()`. Runs on this actor, and its completion is what
    /// `teardown()` waits for — so every child it spawns and every request it
    /// issues is either finished or ruled out before teardown touches the
    /// transport.
    ///
    /// It throws the *diagnosed* cause rather than the raw error, because the
    /// stream-end box may hold a better explanation than the symptom that
    /// surfaced here. Publishing `.failed` and tearing down are `start()`'s
    /// job, not this method's: doing them here would mean tearing down from
    /// inside the task teardown is waiting for.
    private func performStart() async throws {
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
        // Published before the launch suspension so `teardown()` has something
        // to terminate — but publishing it is *not* what makes the child
        // reapable, and reading it that way is how this file got its first
        // orphan. `SubprocessChannel.terminate()` guards on the channel's own
        // `hasLaunched` and does nothing whatsoever before the spawn: it leaves
        // no barrier, so a `launch()` that completes afterwards still produces
        // a child, and by then `stop()` has finished and nothing will ever kill
        // it. What closes that window is `teardown()` awaiting `startTask`
        // before it terminates, so the spawn has already happened or been ruled
        // out by the time `terminate()` runs.
        self.channel = channel

        let connected: LanguageServerChannel
        do {
            connected = try await LanguageServerChannel.connect(over: channel) { [weak self] error in
                self?.recordStreamEnd(error)
            }
        } catch {
            throw await diagnosedCause(for: error)
        }

        // A `stop()` may have landed while the line above was suspended. It has
        // set `isStopped` — that is decided before its first suspension — but it
        // has *not* necessarily terminated the channel: a `terminate()` that ran
        // before the spawn completed did nothing at all. So this returns rather
        // than building a JSON-RPC stack over a child that is about to die, and
        // the child (if the spawn did complete) is `teardown()`'s to reap, which
        // it can do because it waits for this task first.
        //
        // The `isStopped` half also keeps the `initialize` write below from ever
        // being issued after a stop was observed — an in-flight write is what
        // `terminate()` closing stdin turns into a double-resumed continuation.
        guard !isStopped, case .starting = state else { return }
        self.bridge = connected

        // `addMessageFraming: false`: `SubprocessChannel` already frames.
        let connection = JSONRPCServerConnection(
            dataChannel: connected.dataChannel,
            addMessageFraming: false
        )
        let params = makeInitializeParams()
        let server = InitializingServer(server: connection) { params }
        self.server = server

        // Attached here — before the handshake, not after — because
        // `InitializingServer` builds its `eventSequence` from an
        // `AsyncStreamTap` with the default unbounded buffering policy, so
        // events that arrive before a consumer attaches are buffered rather
        // than dropped. Attaching early therefore costs nothing and removes
        // the question of how this orders against `initializeIfNeeded()`.
        //
        // The captures are the whole safety argument: a `nonisolated`
        // continuation and a `nonisolated` sequence, both read *here*, in this
        // actor step, and neither re-read afterwards. The loop body reads no
        // actor state at all, so there is no guard in it that a suspension
        // could make stale.
        self.eventDrainTask = Task { [continuation = diagnosticsContinuation, events = server.eventSequence] in
            for await event in events {
                guard case .notification(.textDocumentPublishDiagnostics(let params)) = event
                else { continue }
                continuation.yield(params)
            }
        }

        do {
            let budget = configuration.initializeBudgetSeconds
            _ = try await withWallClockBudget(budget) { try await server.initializeIfNeeded() }
        } catch {
            throw await diagnosedCause(for: error)
        }

        guard !isStopped, case .starting = state else { return }
        setState(.running)
    }

    /// Stops the server and retires this session permanently.
    ///
    /// Teardown is ordered, and every unbounded half is bounded: wait out the
    /// `start()` this call is racing, then the requests already on the wire
    /// (under `outstandingRequestBudgetSeconds`), then `shutdown` + `exit`
    /// (both inside `InitializingServer.shutdownAndExit()`, under
    /// `shutdownBudgetSeconds`), then `SubprocessChannel.terminate()` as the
    /// backstop, which always runs. The order is argued step by step on
    /// `teardown()`.
    ///
    /// `terminate()` costs up to 2.5 s flat per channel, is **not** cancellable,
    /// and the budgets do not share between channels — so a caller stopping
    /// several sessions must do it in a `withTaskGroup`, never a `for` loop.
    /// `LanguageServerRegistry` has **two** multi-session teardown paths —
    /// `reconcile` retiring superseded sessions, and `shutdown()` at app quit —
    /// and both route through `LanguageServerRegistry.stopAll`, which is that
    /// task group. A third path must route through it too rather than looping.
    ///
    /// A session that had already `.failed` keeps that state: how it died is
    /// more useful than the fact that it was then stopped.
    public func stop() async {
        // Set before the first suspension, so it is visible to every `start()`
        // that has not already entered this actor.
        isStopped = true
        await teardown()
        // A session that had already `.failed` keeps that state; every other
        // path lands on `.stopped`. Written as one branch rather than an early
        // `return` so that the finish below is reached on both.
        if case .failed = state {
            // Nothing to publish: `.failed` was yielded when it was recorded.
        } else {
            setState(.stopped)
        }
        // **Here, and deliberately not in `teardown()`** — where
        // `diagnosticsContinuation` finishes. Teardown is where the transport
        // dies, but this stream's last word is written *after* teardown
        // returns, two lines above. Finishing in teardown would yield
        // `.stopped` into a finished continuation, where it is dropped without
        // a trace, and the last thing a status panel ever heard about a server
        // the user just disabled would be "running" — permanently, because a
        // stopped session makes no further transitions.
        //
        // `stop()` is the only finisher, and `isStopped` makes it run its
        // course once, so this is "finished exactly once, on every stop path"
        // by construction. A running server that dies on its own does *not*
        // come through here: it publishes `.failed` and leaves the session
        // standing, the same contract `publishedDiagnostics` carries.
        stateContinuation.finish()
    }

    /// The server's capabilities, or `nil` if it is not initialized.
    /// Tasks 3.3-3.6 gate their features on this.
    ///
    /// Gated on `.running`, not merely on `server` being set, and that first
    /// clause is load-bearing: a server that dies on its own does not go
    /// through `teardown()` (see `stop()`'s doc), so `server` stays set and
    /// `InitializingServer.state` stays `.initialized` after a crash. Without
    /// the `.running` check this method would keep answering the *pre-crash*
    /// capabilities forever, and every caller above would keep treating a dead
    /// session as though its features were still on offer. This is also the
    /// only enforcement point for that: `LSPCompletionDelegate` relies on this
    /// method returning `nil` for a dead session rather than re-checking
    /// liveness itself at every call site.
    public func capabilities() async -> ServerCapabilities? {
        guard case .running = state, let server else { return nil }
        return await server.capabilities
    }

    /// Everything the server wrote to stderr. Available after a failure (where
    /// it is also carried on the failure state) and while running.
    ///
    /// Deliberately not gated on `.running`: the state this is most needed in
    /// is `.failed`.
    public func standardErrorText() async -> String {
        guard let channel else { return "" }
        return await channel.standardErrorText()
    }

    // MARK: - Traffic

    /// The one gate every notification and request goes through.
    ///
    /// It is a *synchronous* actor method on purpose: the check and the handle
    /// it returns are decided in the same actor step, so a `stop()` cannot land
    /// between them. What it does **not** cover is a `stop()` landing after it
    /// returns and before the write reaches the descriptor, and the two halves
    /// of this file's traffic fare differently there.
    ///
    /// For the four `sendNotification` paths that window is benign: the write
    /// fails with a transport error rather than silently succeeding, which is
    /// an outcome a caller can act on.
    ///
    /// For the five request methods it is not. A request write that fails after
    /// `readSequenceFinished()` has already drained its responder resumes one
    /// `CheckedContinuation` twice — this file's own HIGH-1, a `fatalError`,
    /// and not an outcome any caller can act on.
    ///
    /// **That window is closed by a barrier, not by this gate.** Every request
    /// goes through `trackingOutstandingRequest(_:)`, which counts the round
    /// trip in `outstandingRequests` for its whole duration, and `teardown()`
    /// step 2 waits for that count to reach zero before it touches the
    /// transport — the same shape as its step 1 wait on `startTask`, and for
    /// the identical reason: work that publishes a write from inside a
    /// suspension cannot be torn down beside it, only after it.
    ///
    /// The barrier is bounded by `outstandingRequestBudgetSeconds`, so what
    /// survives is the residue rather than the defect: a server that answers
    /// *nothing* for the whole budget still has its transport closed under a
    /// request, and the narrow write-versus-drain interleaving is possible
    /// again from there. That is the same trade the other budgets in this file
    /// make — an app that cannot quit is not a better outcome than a rare
    /// crash — and it is reached only after a deliberate wait, where before
    /// there was none at all.
    private func runningServer() throws -> InitializingServer {
        guard !isStopped, case .running = state, let server else {
            throw LanguageServerSessionError.notRunning
        }
        return server
    }

    public func didOpen(_ params: DidOpenTextDocumentParams) async throws {
        try await runningServer().sendNotification(.textDocumentDidOpen(params))
    }

    public func didChange(_ params: DidChangeTextDocumentParams) async throws {
        try await runningServer().sendNotification(.textDocumentDidChange(params))
    }

    public func didSave(_ params: DidSaveTextDocumentParams) async throws {
        try await runningServer().sendNotification(.textDocumentDidSave(params))
    }

    public func didClose(_ params: DidCloseTextDocumentParams) async throws {
        try await runningServer().sendNotification(.textDocumentDidClose(params))
    }

    /// Runs one request round trip against the running server, counted for its
    /// whole duration so `teardown()` can wait it out.
    ///
    /// The gate and the increment happen in the same actor step — `runningServer()`
    /// is synchronous and nothing suspends before `outstandingRequests += 1` —
    /// so a request that passes the gate is *always* visible to a teardown
    /// that runs afterwards. Getting that ordering wrong the other way round
    /// is the whole bug: a request counted only after its first suspension
    /// leaves a window in which the gate has said yes, the write is on its way,
    /// and teardown sees a count of zero.
    ///
    /// The `defer` is what makes the decrement unconditional. A request that
    /// throws — `.notRunning` cannot reach here, but a transport error or a
    /// cancellation can — must still release the barrier, or the first failed
    /// request makes every later teardown pay the full budget for nothing.
    private func trackingOutstandingRequest<T: Sendable>(
        _ send: (InitializingServer) async throws -> T
    ) async throws -> T {
        let server = try runningServer()
        outstandingRequests += 1
        defer { finishOutstandingRequest() }
        return try await send(server)
    }

    /// Retires one round trip and, if it was the last, releases every parked
    /// teardown.
    ///
    /// Synchronous and isolated, so the decrement and the resumes are one
    /// actor step: nothing can start a new request between "the count reached
    /// zero" and "the waiters were released", which would otherwise let a
    /// teardown wake to a transport that is busy again.
    ///
    /// Each waiter is resumed exactly once because the dictionary is emptied
    /// before any resume runs — the resumes cannot re-enter and find an entry
    /// that is still there.
    private func finishOutstandingRequest() {
        outstandingRequests -= 1
        guard outstandingRequests == 0, !requestBarrierWaiters.isEmpty else { return }
        let waiters = requestBarrierWaiters
        requestBarrierWaiters.removeAll()
        for waiter in waiters.values { waiter.resume() }
    }

    /// Suspends until no request is on the wire. Unbounded on its own;
    /// `teardown()` is what bounds it.
    ///
    /// The guard and the registration are one actor step —
    /// `withCheckedContinuation` runs its body synchronously, before it
    /// suspends — so there is no window in which the count drops to zero
    /// between "there is something to wait for" and "here is the waiter",
    /// which would park a teardown nothing would ever wake.
    ///
    /// The wait drains rather than treading water because nothing can be
    /// *added* to it while it runs: every path that reaches `teardown()` has
    /// already made the session unusable to `runningServer()` first — `stop()`
    /// sets `isStopped` before its first suspension, and `start()`'s failure
    /// branch publishes `.failed` before it tears down — so a request arriving
    /// mid-teardown throws `.notRunning` instead of joining the count. Without
    /// that, a busy editor could hold the barrier open until the budget
    /// expired and the wait would buy nothing.
    ///
    /// When `teardown()`'s budget wins the race, the waiter registered here
    /// stays in the dictionary and the abandoned task stays suspended on it.
    /// That is deliberate and it is bounded: `teardown()` goes on to terminate
    /// the child, `JSONRPCSession` drains every outstanding responder, the
    /// count reaches zero and the waiter is resumed and dropped. One
    /// continuation per abandoned teardown, released by the very step the
    /// abandonment was in aid of.
    private func awaitOutstandingRequests() async {
        guard outstandingRequests > 0 else { return }
        let id = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestBarrierWaiters[id] = continuation
        }
    }

    public func completion(_ params: CompletionParams) async throws -> CompletionResponse {
        try await trackingOutstandingRequest {
            try await $0.sendRequest(.completion(params, ClientRequest.NullHandler))
        }
    }

    public func hover(_ params: TextDocumentPositionParams) async throws -> HoverResponse {
        try await trackingOutstandingRequest {
            try await $0.sendRequest(.hover(params, ClientRequest.NullHandler))
        }
    }

    public func definition(_ params: TextDocumentPositionParams) async throws -> DefinitionResponse {
        try await trackingOutstandingRequest {
            try await $0.sendRequest(.definition(params, ClientRequest.NullHandler))
        }
    }

    public func diagnostics(_ params: DocumentDiagnosticParams) async throws -> DocumentDiagnosticReport {
        try await trackingOutstandingRequest {
            try await $0.sendRequest(.diagnostics(params, ClientRequest.NullHandler))
        }
    }

    public func semanticTokensFull(_ params: SemanticTokensParams) async throws -> SemanticTokensResponse {
        try await trackingOutstandingRequest {
            try await $0.sendRequest(.semanticTokensFull(params, ClientRequest.NullHandler))
        }
    }

    // MARK: - Teardown

    /// Releases the child, in the one order that is sound under every
    /// interleaving of `start()` and `stop()`.
    ///
    /// The shape is `MCPClient.teardown()`'s, for the same reason: work that
    /// publishes an external resource from inside a suspension cannot be
    /// cancelled out of existence, only waited for.
    ///
    /// 1. **Wait out the in-flight `start()`, bounded.** This is the step the
    ///    rest depends on. Two windows in `performStart()` are invisible to any
    ///    guard on this actor — the suspension inside
    ///    `LanguageServerChannel.connect`, where `SubprocessChannel.launch()`
    ///    spawns the child, and the suspension inside `initializeIfNeeded()`,
    ///    where a write to the child's stdin is outstanding. Terminating beside
    ///    either one is what produced both HIGH findings: `terminate()` before
    ///    the spawn is a **no-op that sets no barrier**, so the spawn completes
    ///    afterwards and nothing is left to reap it; and `terminate()` during
    ///    the write closes stdin under `JSONRPCSession`, which then fails the
    ///    request's responder from its write path *and* again from
    ///    `readSequenceFinished()` — one continuation resumed twice, which traps
    ///    the process. Waiting first covers both in every ordering step 1
    ///    completes: when step 4 runs the spawn has happened or been ruled out,
    ///    and the write has completed or failed on its own. When step 1's own
    ///    budget expires — the case the next paragraph exists to justify —
    ///    neither half holds. The spawn half is admitted at step 6 below. The
    ///    write half is weaker still: `startTask.value` completing does not
    ///    await the budget loser `withWallClockBudget` abandoned, so after an
    ///    `initialize` budget expiry that loser is still live and its write can
    ///    still be outstanding when step 4 closes stdin. Both are residues, not
    ///    covered cases.
    ///
    ///    The task is **not** cancelled first, which is where this departs from
    ///    `MCPClient`. Cancelling would resume `performStart()` immediately
    ///    through `withWallClockBudget`'s cancellation handler while the
    ///    `initialize` write is still outstanding inside JSONRPC — reopening the
    ///    exact window this step exists to close. The budget, not cancellation,
    ///    is what bounds the wait.
    ///
    ///    The bound is `abandonedStartBudgetSeconds`, and it exists so a server
    ///    that never answers `initialize` cannot make app quit hang. A start
    ///    still in flight when teardown runs is abandoned by definition, so
    ///    cutting it short costs it nothing real; its error still reaches its
    ///    own caller, because `start()` awaits the task's completion and
    ///    rethrows from there.
    /// 2. **Wait out the requests already on the wire, bounded.** Step 1's
    ///    argument, one traffic path over. A request write is published from
    ///    inside a suspension too — `JSONRPCSession` registers the responder,
    ///    then hops through the data channel and onto `SubprocessChannel` to do
    ///    the write — and closing stdin beside one is what makes the write path
    ///    fail a responder that `readSequenceFinished()` has *already* drained.
    ///    One `CheckedContinuation` resumed twice is
    ///    `SWIFT TASK CONTINUATION MISUSE`, a `fatalError` that takes the app
    ///    with it. `runningServer()`'s gate cannot cover this: it decides
    ///    before the write, and the hazard is after. Only waiting can.
    ///
    ///    Notifications are deliberately **not** waited on. A notification
    ///    write that loses this race fails with a transport error its caller
    ///    can act on; there is no responder to resume twice, so there is
    ///    nothing here to protect.
    ///
    ///    Before step 3, not after: the whole point is to let requests finish
    ///    while the transport is still whole, and a `shutdown` request racing
    ///    the user's `hover` is a worse ordering than the reverse. The bound is
    ///    `outstandingRequestBudgetSeconds`, and the residue when it expires is
    ///    stated on `runningServer()`.
    /// 3. **Graceful `shutdown` + `exit`, under `shutdownBudgetSeconds`.** A
    ///    server that ignores `shutdown`, or that is already dead, is not a
    ///    teardown failure — step 4 is the answer to both.
    /// 4. **`terminate()`, unconditional.** The backstop, and what makes this
    ///    actor the only owner of the child.
    /// 5. **`drain()`.** `terminate()` finishes the frame stream itself after
    ///    waiting out its own pump-drain grace, so this is already finishing or
    ///    done. Waiting is what delivers the frames a graceful child wrote
    ///    between SIGTERM and `exit`. It is bounded in every ordering because
    ///    `bridge` is only non-nil once step 4 has a launched channel to
    ///    terminate.
    /// 6. **`terminate()` again.** Only step 1's budget expiring can make this
    ///    more than a no-op: an abandoned start that resumes afterwards and
    ///    completes its spawn leaves a child step 4 could not have seen. A
    ///    second `terminate()` on a live channel reaps it, and
    ///    `SubprocessChannel.terminate()` is idempotent — a second call awaits
    ///    the first call's own termination task rather than repeating the 2.5 s.
    ///    This is `MCPClient.teardown()`'s closing `terminate()`, one transport
    ///    over.
    ///
    ///    What it does not close is the sliver in which an abandoned start
    ///    resumes and spawns *between* steps 4 and 6. Closing that needs a
    ///    terminate-before-launch barrier inside `SubprocessChannel`, which is
    ///    out of this task's scope; reaching it at all requires a start wedged
    ///    for the whole of `abandonedStartBudgetSeconds` that then resumes
    ///    within microseconds.
    /// 7. **End `publishedDiagnostics`.** Last, so the notifications step 5
    ///    delivered are yielded before the consumer's `for await` terminates.
    ///    This is the only place the continuation is finished, which is what
    ///    makes "finished exactly once, on every stop path" true by
    ///    construction rather than by inspection.
    private func teardown() async {
        if let startTask {
            _ = try? await withWallClockBudget(configuration.abandonedStartBudgetSeconds) {
                _ = try? await startTask.value
            }
        }

        // Step 2. Bounded the same way step 1 is, and by the same argument: a
        // request that will never be answered must not be allowed to make app
        // quit hang. The budget losing is not a failure to report — it means
        // the residue on `runningServer()` is back in play for the remaining
        // requests, which is what the steps below then do their best with.
        _ = try? await withWallClockBudget(configuration.outstandingRequestBudgetSeconds) {
            await self.awaitOutstandingRequests()
        }

        if let server {
            let budget = configuration.shutdownBudgetSeconds
            do {
                try await withWallClockBudget(budget) { try await server.shutdownAndExit() }
            } catch {
                // Losing the reason would make a hung shutdown invisible, so it
                // is logged and not rethrown.
                let message = error.localizedDescription
                logger.debug("Graceful LSP shutdown did not complete: \(message, privacy: .public)")
            }
        }

        await channel?.terminate()
        await bridge?.drain()
        await channel?.terminate()

        // After the drain, not before it. `drain()` is what delivers the
        // frames a graceful child wrote between SIGTERM and `exit`, and a
        // `publishDiagnostics` among them is a real answer the consumer should
        // still see. Cancelling first would cut the `for await` short —
        // `AsyncStream`'s iterator checks cancellation — and lose them.
        //
        // The finish is unconditional and this is the only place it happens,
        // so every stop path ends the consumer's iteration exactly once: a
        // `finish()` on an already-finished continuation is a no-op, and a
        // `yield` after it is dropped rather than trapping.
        eventDrainTask?.cancel()
        eventDrainTask = nil
        diagnosticsContinuation.finish()

        server = nil
        bridge = nil
        // `channel` is deliberately kept, and this is an intra-object
        // invariant rather than a retain that grows: it is terminated and
        // inert, and it is where `standardErrorText()` reads from after a
        // failure. Nothing accumulates, because a retired session is dropped
        // from `LanguageServerRegistry.sessions` whole — the channel goes with
        // it, captured stderr buffer and all.
    }

    // MARK: - Failure

    /// Called synchronously from the bridge's stream-end handler, off this
    /// actor. Records first, then hops on to publish — see `streamEnd`.
    private nonisolated func recordStreamEnd(_ error: (any Error)?) {
        streamEnd.record(error)
        Task { [weak self] in await self?.publishStreamEnd() }
    }

    /// Publishes the failure for a stream end nobody asked for.
    ///
    /// The cause comes straight out of the box rather than through
    /// `diagnosedCause(for:)`: this path *is* the stream end, so it has no
    /// fallback to fall back to. A recorded transport error is the explanation;
    /// its absence means the server exited at a frame boundary, which
    /// `serverExited(status:)` says exactly. Routing it through a fallback of
    /// `.notRunning` used to surface "The language server is not running." to
    /// the user as the *cause* of the server not running.
    private func publishStreamEnd() async {
        // A stop we asked for ends the stream too; that is not a failure.
        guard !isStopped else { return }
        switch state {
        case .idle, .stopped, .failed: return
        case .starting, .running: break
        }
        let cause: any Error
        if let recorded = streamEnd.value.error {
            cause = recorded
        } else {
            cause = LanguageServerSessionError.serverExited(status: await exitStatus())
        }
        await fail(with: cause)
    }

    /// The most informative cause for a failure that surfaced as `fallback`.
    ///
    /// A stream that has already ended explains *why* a request failed;
    /// `ProtocolTransportError.dataStreamClosed` or a `WallClockBudgetExceeded`
    /// only says that it did. Reading the box is synchronous, so this does not
    /// race the handler's own hop onto this actor. Callers are `performStart()`'s
    /// two failure paths, where `fallback` is the real error the operation threw.
    private func diagnosedCause(for fallback: any Error) async -> any Error {
        let ended = streamEnd.value
        guard ended.didEnd else { return fallback }
        if let error = ended.error { return error }
        return LanguageServerSessionError.serverExited(status: await exitStatus())
    }

    private func exitStatus() async -> Int32? {
        guard let channel else { return nil }
        // `try?` on both levels, and they mean different things: the outer one
        // swallows the budget expiry, the inner one a wait that was never
        // launched or was cancelled. All three are "no status to report",
        // which is exactly what `nil` says here.
        return try? await withWallClockBudget(configuration.exitStatusBudgetSeconds) {
            try? await channel.waitUntilExit()
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
        setState(.failed(LanguageServerFailure(error: error, standardErrorText: text)))
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
            // Two of this initialiser's defaults are promises we cannot keep,
            // so both are spelled out as `false` rather than inherited. They
            // are written here, together, because they fail the same way: a
            // conforming server takes the declaration at its word, sends what
            // it was told we could render, and the tokens are silently lost or
            // silently misplaced. Neither surfaces as an error.
            //
            // `overlappingTokenSupport` defaults to `true`, and
            // `SemanticTokenHighlightProvider.decode` drops any token that
            // starts before the previous one ended — it must, because
            // `StyledRangeContainer.applyHighlightResult` lays runs end to end
            // and skips an overlapping one anyway. Declaring `false` turns that
            // from data loss into a request the server never makes; the drop
            // stays as a defensive path, and logs, for a server that sends
            // overlap regardless.
            //
            // `multilineTokenSupport` defaults to `true` and is equally wrong:
            // the decoder we render through, `TokenRepresentation.decodeTokens`,
            // computes every token's end as `Position(line: line, character:
            // startChar + length)` — always the *same* line. A multiline token
            // would be painted as a same-line range of the wrong length,
            // colouring characters that have nothing to do with the symbol.
            //
            // Neither is a default anyone should restore without changing the
            // renderer first. `augmentsSyntaxTokens: true`, by contrast, is
            // correct for us and is left inherited: tree-sitter highlights
            // underneath the semantic layer, so a server that takes that hint
            // sends fewer tokens and we lose nothing.
            semanticTokens: SemanticTokensClientCapabilities(
                overlappingTokenSupport: false,
                multilineTokenSupport: false
            )
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
