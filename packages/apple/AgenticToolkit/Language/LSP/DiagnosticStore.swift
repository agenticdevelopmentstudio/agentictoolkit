//
//  DiagnosticStore.swift
//  AgenticToolkit
//

import Combine
import Foundation
import LanguageServerProtocol

/// One server's last word about one document: the diagnostics it published and
/// the document version it published them against.
///
/// The version is recorded rather than acted on — see `DiagnosticStore`'s note
/// on stale versions — so that a later task can implement version-aware
/// behaviour without having to change what is stored.
public struct DocumentDiagnostics: Equatable, Sendable {

    /// Exactly what the server sent, including the empty array, which is how
    /// LSP says "this file is clean now".
    public let diagnostics: [Diagnostic]

    /// The document version the server was answering about, when it said. Most
    /// servers omit it.
    public let version: Int?

    public init(diagnostics: [Diagnostic], version: Int?) {
        self.diagnostics = diagnostics
        self.version = version
    }
}

/// Everything the language servers have said, unasked, about the documents in
/// one project — the receiving end of `LanguageServerSessionProtocol`'s
/// `publishedDiagnostics`.
///
/// It holds no AppKit and no app vocabulary: a URI-to-array map fed by an
/// `AsyncStream`. That is why it lives in the Language framework rather than
/// beside `ProjectLanguageServices` in `macOS/` — it can be tested against a
/// fake session with no editor, no window and no run loop.
///
/// **On stale versions.** `PublishDiagnosticsParams.version` is optional and
/// many servers never populate it. This store therefore *stores what the server
/// sent* and never drops a set because its version looks old: dropping is how a
/// client ends up with a permanently empty overlay against a server that omits
/// the field. The consequence is accepted and is not a defect — as the user
/// types, the stored ranges refer to text that has moved, and stay wrong until
/// the next publish arrives. A squiggle a few characters out of place for a
/// fraction of a second is a far better failure than no squiggle at all.
///
/// **One consumer per session.** `AsyncStream` supports a single iterator, so
/// exactly one object may iterate a session's `publishedDiagnostics`, and this
/// is it. `observe(_:)` refuses a session it is already observing for that
/// reason.
@MainActor
public final class DiagnosticStore: ObservableObject {

    /// What every server has said about every document, keyed by URI.
    ///
    /// Published so a view can subscribe; `diagnostics(for:)` and
    /// `publisher(for:)` are the two shapes callers actually want.
    ///
    /// **Keyed by URI alone, not by (session, URI).** Two servers claiming the
    /// same file would overwrite each other here. That is deliberate for now:
    /// the registry serves one session per language id, a document has one
    /// language, and inventing a merge policy for a configuration nothing can
    /// currently produce would be a guess with no way to test it.
    @Published public private(set) var documents: [DocumentUri: DocumentDiagnostics] = [:]

    /// One live observation: the session being read, and the task reading it.
    ///
    /// The session is held on purpose. `ObjectIdentifier` is an address, and an
    /// address identifies an object only for as long as that object is alive —
    /// so a map keyed by one is sound only while it also guarantees its keys'
    /// objects are alive. Holding the session here is that guarantee, written
    /// where the key is stored rather than left to the fact that the reading
    /// task's own capture happens to do the same thing.
    private struct Observation {
        let session: any LanguageServerSessionProtocol
        let task: Task<Void, Never>
    }

    /// One observation per session object, keyed by identity rather than by
    /// configuration id: a session that is *replaced* keeps its id, and both
    /// objects can be alive at once while the old one drains.
    ///
    /// **Entries are retired when their stream ends, not only at `shutdown()`.**
    /// Two things go wrong without that. The map grows for the life of the app,
    /// one entry per server restart — and the registry replaces a session
    /// whenever its `SessionDescriptor` changes, so restarts are ordinary. And,
    /// far worse, a dead session's key stays in the map: a later session
    /// allocated at that freed address hashes to the same key, `observe(_:)`
    /// finds a non-nil entry and returns, and that session's diagnostics never
    /// reach the store — permanently, with nothing reporting it. On screen it
    /// looks like a server that is still starting up, because the previous
    /// session's diagnostics are deliberately left in place during a restart.
    private var observations: [ObjectIdentifier: Observation] = [:]

    private var cancellables: Set<AnyCancellable> = []
    private var isShutDown = false

    public init() {}

    // MARK: - Observing

    /// Reads one session's published diagnostics until the session's stream
    /// finishes or `shutdown()` cancels the read.
    ///
    /// Idempotent per session object: asking twice is a no-op rather than a
    /// second iterator, because a second iterator over an `AsyncStream` splits
    /// the events arbitrarily between the two and neither sees them all.
    public func observe(_ session: some LanguageServerSessionProtocol) {
        guard !isShutDown else { return }
        let key = ObjectIdentifier(session)
        guard observations[key] == nil else { return }

        // `Task {}` inside a `@MainActor` method inherits main-actor isolation,
        // so `apply(_:)` below runs on the actor that owns `documents` — no
        // hop, no `assumeIsolated`, and no window in which a second writer can
        // interleave between reading the map and writing it.
        //
        // The invariant this loop relies on: **nothing is read before an await
        // and used after it.** `params` is delivered by the await itself, and
        // `apply(_:)` re-reads `isShutDown` and `documents` synchronously each
        // time. A `shutdown()` that lands while this task is parked is seen on
        // the very next iteration.
        //
        // `[weak self]` so an abandoned store — one whose owner was released
        // without calling `shutdown()` — does not keep itself alive through a
        // task parked on a live server's stream.
        let task = Task { [weak self] in
            for await params in session.publishedDiagnostics {
                guard let self else { return }
                self.apply(params)
            }
            // The stream is finished: this session will publish nothing more,
            // and this is the point at which its key stops identifying it.
            self?.finishedObserving(key)
        }
        // Stored after the task is made, and safe to be: this method runs to
        // completion on the main actor before the task body can begin, so the
        // entry is always in the map before `finishedObserving` could remove
        // it. A stream that is already finished does not change that.
        observations[key] = Observation(session: session, task: task)
    }

    /// Retires one finished observation, which is what keeps every key in
    /// `observations` the key of a session that is still alive.
    ///
    /// Unconditional, and it can be: the only writer of `observations[key]` is
    /// `observe(_:)`, and it refuses while an entry is present — so between
    /// this task's creation and this call the entry can only be this task's
    /// own.
    private func finishedObserving(_ key: ObjectIdentifier) {
        observations[key] = nil
    }

    /// How many sessions are being read right now.
    ///
    /// Internal, for tests. Retiring an entry has exactly one externally
    /// visible consequence — the map is empty again once a session's stream
    /// ends — and asserting that directly is what makes the behaviour testable
    /// without relying on the allocator to actually hand a later session a
    /// freed address.
    var observationCount: Int { observations.count }

    /// Observes every session the registry has now **and every session it
    /// publishes later**.
    ///
    /// The "later" half is the whole point. A project window opens its files
    /// before a language server has finished starting — routinely, not as an
    /// edge case — so a store that only read the sessions present when it was
    /// built would show nothing for exactly the file the user is looking at.
    /// This is the same `registry.$sessions` subscription
    /// `LanguageServerDocumentSync.start()` uses, for the same reason.
    ///
    /// The emitted dictionary is used and `registry.sessions` is never re-read
    /// here: `@Published` fires from `willSet`, so the property still holds the
    /// *old* value for the duration of this callback.
    ///
    /// Sessions that disappear are not un-observed, and need not be: a session
    /// the registry has dropped is stopped, stopping finishes its stream, and
    /// the loop above ends on its own. What it leaves behind — the diagnostics
    /// that session published — stays visible until something replaces it,
    /// which is the right answer while a server restarts.
    public func observeSessions(from registry: LanguageServerRegistry) {
        guard !isShutDown else { return }
        registry.$sessions
            .sink { [weak self] sessions in
                guard let self else { return }
                for session in sessions.values {
                    self.observe(session)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Reading

    /// The diagnostics for one document; an empty array when a server has said
    /// nothing about it, and also when a server has said it is clean. The two
    /// are the same thing to every caller.
    public func diagnostics(for uri: DocumentUri) -> [Diagnostic] {
        documents[uri]?.diagnostics ?? []
    }

    /// The document version the current diagnostics for `uri` were published
    /// against, when the server said. `nil` covers both "no diagnostics" and
    /// "the server omitted the version", which is most of them.
    public func version(for uri: DocumentUri) -> Int? {
        documents[uri]?.version
    }

    /// One URI's diagnostics, on every change and once immediately.
    ///
    /// `removeDuplicates()` because the map republishes on any URI's change and
    /// a subscriber that redraws an editor should not redraw for a file it is
    /// not showing.
    public func publisher(for uri: DocumentUri) -> AnyPublisher<[Diagnostic], Never> {
        $documents
            .map { $0[uri]?.diagnostics ?? [] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - Writing

    /// Forgets one document, for when it closes. Not a server's "clean" — that
    /// is an empty array, which stays in the map.
    public func clear(uri: DocumentUri) {
        documents.removeValue(forKey: uri)
    }

    private func apply(_ params: PublishDiagnosticsParams) {
        // Re-read after every suspension rather than captured before the loop:
        // `shutdown()` may have run while this task was parked, and a write
        // after it would resurrect state the owner believes it has torn down.
        guard !isShutDown else { return }
        documents[params.uri] = DocumentDiagnostics(
            diagnostics: params.diagnostics,
            version: params.version
        )
    }

    // MARK: - Lifecycle

    /// Cancels every observation. Idempotent, like
    /// `ProjectLanguageServices.shutdown()`.
    ///
    /// `isShutDown` is set *first*, before anything is cancelled, so a
    /// notification already delivered into a task that has not yet been
    /// resumed is dropped by `apply(_:)` rather than racing the cancellation.
    /// Cancellation alone would be a race; the flag is what makes this
    /// deterministic.
    ///
    /// The stored diagnostics are left alone. Shutdown is teardown, and a view
    /// still on screen during it should keep showing what it was showing rather
    /// than flashing clean.
    public func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        for observation in observations.values {
            observation.task.cancel()
        }
        observations = [:]
        cancellables = []
    }

    /// A net under `shutdown()`, not a replacement for it: an owner released
    /// without shutting down would otherwise leave a task per session parked on
    /// a live stream forever, each holding its session — and through it a
    /// language-server subprocess — alive.
    ///
    /// Isolated explicitly (SE-0371): a `@MainActor` class's deinit is
    /// `nonisolated` by default and `observations` is main-actor state. Same
    /// shape as `LanguageServerDocumentSync.deinit`.
    isolated deinit {
        for observation in observations.values {
            observation.task.cancel()
        }
    }
}
