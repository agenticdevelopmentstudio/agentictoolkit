import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
@testable import AgenticToolkitLanguage

/// One thing a fake session was asked to do, with the parameters it was asked
/// with. `Equatable` because that is what lets a test say *which* notification
/// it expects rather than only how many — every LSP params type in it is
/// already `Hashable`.
enum RecordedCall: Equatable, Sendable {
    case start
    case stop
    case didOpen(DidOpenTextDocumentParams)
    case didChange(DidChangeTextDocumentParams)
    case didSave(DidSaveTextDocumentParams)
    case didClose(DidCloseTextDocumentParams)
}

/// What the fakes did, in order. Lock-guarded rather than isolated: `start()`,
/// `stop()` and the notifications all run on each session's own actor, off the
/// main one, and the assertions read from the main one.
final class SessionLog: @unchecked Sendable {

    /// One recorded call, tagged twice over.
    ///
    /// `sessionID` is the *configuration* id, which survives a session being
    /// replaced — that is exactly why it cannot identify the object. Every fake
    /// gets a fresh `instanceID` as well, so a test can say "the session that
    /// was replaced received nothing further".
    struct Entry: Sendable {
        let sessionID: UUID
        let instanceID: UUID
        let call: RecordedCall
    }

    private let lock = NSLock()
    private var recorded: [Entry] = []

    func record(sessionID: UUID, instanceID: UUID, call: RecordedCall) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(Entry(sessionID: sessionID, instanceID: instanceID, call: call))
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Every call one particular session object received, in order.
    func calls(forInstance instanceID: UUID) -> [RecordedCall] {
        entries.filter { $0.instanceID == instanceID }.map(\.call)
    }

    /// Configuration ids whose session actually performed a start, in order.
    var started: [UUID] {
        entries.filter { $0.call == .start }.map(\.sessionID)
    }

    /// Configuration ids whose session was stopped, in order.
    var stopped: [UUID] {
        entries.filter { $0.call == .stop }.map(\.sessionID)
    }
}

/// How a `FakeLanguageServerSession` should behave. Immutable and passed at
/// construction, so nothing has to be mutated across an isolation boundary in
/// the middle of a test.
struct FakeSessionBehavior: Sendable {

    /// What `capabilities()` answers once the session is `.running`. `nil` —
    /// the default, and what Task 3.1's fake always did — means the server
    /// published none.
    var capabilities: ServerCapabilities?

    /// When set, `start()` fails with it and the session lands in `.failed`.
    var startError: LanguageServerSessionError?

    /// When true, `start()` parks — **before** it writes any state — until
    /// `releaseHeldStart()`, so the session sits at `.idle` for as long as a
    /// test needs it to.
    ///
    /// This is what makes the retire race expressible. The registry starts
    /// every session it creates, and a fake that ran straight to `.running`
    /// would overwrite the very entry a test about a *late* write is trying to
    /// inspect.
    var holdsStart: Bool

    /// When true, `stop()` parks — **before** it writes any state — until
    /// `releaseHeldStop()`.
    ///
    /// This is what makes "shutdown waited for it" expressible. A teardown
    /// that runs to completion on its own is indistinguishable from one
    /// nobody waited for; a teardown that is still parked when `shutdown()`
    /// returns is a leak, and holding the stop is how a test gets to see the
    /// difference.
    var holdsStop: Bool

    /// Errors for successive `didOpen` calls; a `nil` entry (or running off the
    /// end) succeeds. `[.notRunning, nil]` is "the first open is dropped, the
    /// next one lands".
    var didOpenErrors: [LanguageServerSessionError?]

    /// The same, for `didChange`.
    var didChangeErrors: [LanguageServerSessionError?]

    init(
        capabilities: ServerCapabilities? = nil,
        startError: LanguageServerSessionError? = nil,
        didOpenErrors: [LanguageServerSessionError?] = [],
        didChangeErrors: [LanguageServerSessionError?] = [],
        holdsStart: Bool = false,
        holdsStop: Bool = false
    ) {
        self.capabilities = capabilities
        self.startError = startError
        self.didOpenErrors = didOpenErrors
        self.didChangeErrors = didChangeErrors
        self.holdsStart = holdsStart
        self.holdsStop = holdsStop
    }

    /// A server that declared the given sync capability and nothing else.
    static func syncing(_ sync: TwoTypeOption<TextDocumentSyncOptions, TextDocumentSyncKind>?) -> FakeSessionBehavior {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = sync
        return FakeSessionBehavior(capabilities: capabilities)
    }
}

/// Conforms to the protocol the registry and `LanguageServerDocumentSync`
/// consume, and does nothing else. It keeps the command, environment and root
/// it was built with, so a test can prove a *replacement* happened rather than
/// a reuse, and it records every call so a test can assert order.
///
/// Its lifecycle is deliberately faithful to `LanguageServerSession` in the one
/// respect that matters to callers: **a second `start()` does not start a second
/// server, and it reports the first one's outcome** — returning if the session
/// is running, throwing the failure's cause if it failed. Both
/// `LanguageServerRegistry.reconcile` and `LanguageServerDocumentSync` start
/// every session they see, so a fake that started twice would make "start was
/// called once" untestable, and one that returned success off a failed session
/// would hide the very defect that contract was written to close.
actor FakeLanguageServerSession: LanguageServerSessionProtocol {

    nonisolated let id: UUID
    /// Unique per object, unlike `id`, which is the configuration's and
    /// survives replacement.
    nonisolated let instanceID = UUID()
    nonisolated let name: String
    nonisolated let languageIds: [String]
    nonisolated let command: String
    nonisolated let rootURL: URL
    nonisolated let environment: [String: String]

    /// The push-diagnostics half of the protocol. The real session fills this
    /// from the server's `eventSequence`; here the test is the server, and
    /// `publish(_:)` is the wire.
    nonisolated let publishedDiagnostics: AsyncStream<PublishDiagnosticsParams>
    private nonisolated let diagnosticsContinuation: AsyncStream<PublishDiagnosticsParams>.Continuation

    /// The lifecycle half of the protocol, faithful to the real session in the
    /// one respect the registry depends on: every transition is published, in
    /// the order it was made, and the stream finishes at the end of `stop()`.
    nonisolated let stateChanges: AsyncStream<LanguageServerSessionState>
    private nonisolated let stateContinuation: AsyncStream<LanguageServerSessionState>.Continuation

    private(set) var state: LanguageServerSessionState = .idle

    /// Parked `start()` calls, when `behavior.holdsStart` is set.
    private var heldStarts: [CheckedContinuation<Void, Never>] = []

    /// Parked `stop()` calls, when `behavior.holdsStop` is set, and whether
    /// the release has already been given. The flag is what makes the release
    /// order-independent: a test that releases before the stop has arrived
    /// would otherwise park it forever.
    private var heldStops: [CheckedContinuation<Void, Never>] = []
    private var stopWasReleased = false
    private let log: SessionLog
    private let behavior: FakeSessionBehavior
    private var didOpenCount = 0
    private var didChangeCount = 0

    init(
        configuration: LanguageServerConfiguration,
        environment: [String: String],
        rootURL: URL,
        log: SessionLog,
        behavior: FakeSessionBehavior = FakeSessionBehavior()
    ) {
        let (stream, continuation) = AsyncStream.makeStream(of: PublishDiagnosticsParams.self)
        self.publishedDiagnostics = stream
        self.diagnosticsContinuation = continuation
        let (states, stateContinuation) = AsyncStream.makeStream(of: LanguageServerSessionState.self)
        self.stateChanges = states
        self.stateContinuation = stateContinuation
        self.id = configuration.id
        self.name = configuration.name
        self.languageIds = configuration.languageIds
        self.command = configuration.command
        self.rootURL = rootURL
        self.environment = environment
        self.log = log
        self.behavior = behavior
    }

    func start() async throws {
        switch state {
        case .idle:
            break
        case .starting, .running:
            // This fake's start has no suspension point, so `.starting` is not
            // observable from outside; a second caller only ever meets a settled
            // outcome. `LanguageServerSession` reaches the same place by
            // awaiting its held `startTask`.
            return
        case .failed(let failure):
            throw failure.error
        case .stopped:
            throw LanguageServerSessionError.sessionHasBeenStopped
        }
        record(.start)
        if behavior.holdsStart {
            await withCheckedContinuation { continuation in
                heldStarts.append(continuation)
            }
        }
        if let startError = behavior.startError {
            setState(.failed(LanguageServerFailure(error: startError, standardErrorText: "")))
            throw startError
        }
        setState(.running)
    }

    /// Resumes every `stop()` parked by `behavior.holdsStop`, and lets any
    /// later one through without parking.
    func releaseHeldStop() {
        stopWasReleased = true
        let held = heldStops
        heldStops = []
        for continuation in held {
            continuation.resume()
        }
    }

    /// Resumes every `start()` parked by `behavior.holdsStart`.
    func releaseHeldStart() {
        let held = heldStarts
        heldStarts = []
        for continuation in held {
            continuation.resume()
        }
    }

    func stop() async {
        if behavior.holdsStop && !stopWasReleased {
            await withCheckedContinuation { continuation in
                heldStops.append(continuation)
            }
        }
        setState(.stopped)
        record(.stop)
        // Finished here for the same reason the real session finishes it in
        // `teardown()`: a consumer's `for await` must terminate when the server
        // it is reading is gone. A fake that never finished would let a store
        // bug — an observation task that outlives its session — pass.
        diagnosticsContinuation.finish()
        // The state stream finishes at the end of `stop()`, after the terminal
        // state has been yielded — the real session's Ruling BA asymmetry,
        // mirrored here so a fake cannot hide a consumer that depends on it.
        stateContinuation.finish()
    }

    /// The single writer, exactly as `LanguageServerSession.setState(_:)` is.
    private func setState(_ next: LanguageServerSessionState) {
        state = next
        stateContinuation.yield(next)
    }

    /// Drives one transition from a test — the state and the stream together.
    func transition(to next: LanguageServerSessionState) {
        setState(next)
    }

    /// Yields a transition **without** the actor hop, leaving `state` alone.
    ///
    /// `nonisolated` for the same reason `publish(_:)` is, and it is what makes
    /// the retire race expressible: a test on the main actor can put a value
    /// into an observation task's hands and then reconcile *in the same
    /// synchronous step*, with no suspension in between for the registry to
    /// notice. `transition(to:)` would suspend at the actor hop and let the
    /// observation run first, which is the ordering the race is not about.
    nonisolated func yieldState(_ next: LanguageServerSessionState) {
        stateContinuation.yield(next)
    }

    /// Pushes one `publishDiagnostics` notification, as a server would.
    ///
    /// `nonisolated`, because the continuation is: yielding is synchronous and
    /// needs none of this actor's state, so a test can push without an `await`
    /// and without an ordering question about when the push lands relative to
    /// the actor's own queue.
    nonisolated func publish(_ params: PublishDiagnosticsParams) {
        diagnosticsContinuation.yield(params)
    }

    /// Ends the stream without stopping the session — the shape of a server
    /// that died on its own, which the real session's `publishStreamEnd` path
    /// does not currently cover.
    nonisolated func finishDiagnostics() {
        diagnosticsContinuation.finish()
    }

    // MARK: The traffic half of the protocol

    // Adjudication 2's whole point, and the reason `LanguageServerSession`
    // vends methods rather than its `InitializingServer`: a substitute has
    // to be writable in a few lines. Vending the server would force this
    // fake to spawn a real child, and `LanguageServerRegistry` only ever
    // hands out `any LanguageServerSessionProtocol`.
    //
    // Every request path answers "nothing", which is a valid LSP response
    // and exactly what Tasks 3.3-3.6 must already handle from a server
    // that has no result. `.notRunning` off a stopped session is the other
    // half of the contract they have to handle.

    private func requireRunning() throws {
        guard case .running = state else { throw LanguageServerSessionError.notRunning }
    }

    private func record(_ call: RecordedCall) {
        log.record(sessionID: id, instanceID: instanceID, call: call)
    }

    /// The scripted error for call number `index`, or `nil` to succeed.
    private func scriptedError(_ script: [LanguageServerSessionError?], at index: Int) -> LanguageServerSessionError? {
        guard index < script.count else { return nil }
        return script[index]
    }

    func capabilities() async -> ServerCapabilities? {
        // Gated on `.running` the way the real session is: it has no
        // `InitializingServer` to ask until the handshake has completed.
        guard case .running = state else { return nil }
        return behavior.capabilities
    }

    func standardErrorText() async -> String { "" }

    // A scripted failure is recorded *before* it is thrown: the notification
    // did reach the server object, and a test asserting the self-heal needs to
    // see the attempt that failed as well as the re-open that repaired it. A
    // `requireRunning()` refusal is not recorded — nothing reached the server.

    func didOpen(_ params: DidOpenTextDocumentParams) async throws {
        try requireRunning()
        record(.didOpen(params))
        let error = scriptedError(behavior.didOpenErrors, at: didOpenCount)
        didOpenCount += 1
        if let error { throw error }
    }

    func didChange(_ params: DidChangeTextDocumentParams) async throws {
        try requireRunning()
        record(.didChange(params))
        let error = scriptedError(behavior.didChangeErrors, at: didChangeCount)
        didChangeCount += 1
        if let error { throw error }
    }

    func didSave(_ params: DidSaveTextDocumentParams) async throws {
        try requireRunning()
        record(.didSave(params))
    }

    func didClose(_ params: DidCloseTextDocumentParams) async throws {
        try requireRunning()
        record(.didClose(params))
    }

    func completion(_ params: CompletionParams) async throws -> CompletionResponse {
        try requireRunning()
        return nil
    }

    func hover(_ params: TextDocumentPositionParams) async throws -> HoverResponse {
        try requireRunning()
        return nil
    }

    func definition(_ params: TextDocumentPositionParams) async throws -> DefinitionResponse {
        try requireRunning()
        return nil
    }

    func diagnostics(_ params: DocumentDiagnosticParams) async throws -> DocumentDiagnosticReport {
        try requireRunning()
        return DocumentDiagnosticReport(kind: .full, items: [])
    }

    func semanticTokensFull(_ params: SemanticTokensParams) async throws -> SemanticTokensResponse {
        try requireRunning()
        return nil
    }
}

extension LanguageServerSessionState {

    /// The case as a word.
    ///
    /// `LanguageServerSessionState` is deliberately not `Equatable` — `.failed`
    /// carries `any Error` — so a name is what a test can actually compare, and
    /// it is what a failure message needs to read. Payload assertions go
    /// through `failure` beside this, never instead of it.
    var caseName: String {
        switch self {
        case .idle: return "idle"
        case .starting: return "starting"
        case .running: return "running"
        case .stopped: return "stopped"
        case .failed: return "failed"
        }
    }
}
