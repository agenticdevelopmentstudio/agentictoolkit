//
//  LanguageServerDocumentSync.swift
//  AgenticToolkit
//

import Combine
import Foundation
import LanguageServerProtocol

/// Connects the two halves that have never been connected: the `@MainActor`
/// document model (`TextDocumentStore`) and the `actor` language-server
/// sessions (`LanguageServerRegistry`). Every open, edit, save and close of a
/// document is forwarded to whichever live sessions claim that document's
/// language, so a server knows which files exist and what is in them.
///
/// Without it a language server is talking to a client that has never told it a
/// single file exists, and every request answers "unknown document".
///
/// **Where the isolation seam is handled.** This class does exactly two things
/// off the main actor's back: it captures a complete, `Sendable` snapshot of
/// each store event *synchronously, in the callback*, and it hands that
/// snapshot to a per-session `DocumentSyncPipeline` through a synchronous,
/// order-preserving `yield`. Nothing here awaits inside the store's observer,
/// and nothing in the pipeline ever reaches back to a `TextDocument`. That
/// division is the whole design; see `DocumentSyncPipeline` for the argument.
///
/// It never calls `session.stop()`. The registry owns session lifecycle, and
/// stopping a session the registry still lists would be this layer reaching
/// outside itself.
@MainActor
public final class LanguageServerDocumentSync {

    /// One live session, its queue, and the task draining that queue.
    ///
    /// The drain task handle lives here on the main actor rather than inside
    /// the actor it drains: an actor cannot hand `self` to a task it creates in
    /// its own initialiser without escaping a partially-initialised actor, and
    /// "`shutdown()` awaits every drain task" is trivially true when the handles
    /// are all in one main-actor dictionary.
    private struct PipelineEntry {
        let session: any LanguageServerSessionProtocol
        let pipeline: DocumentSyncPipeline
        let drainTask: Task<Void, Never>
    }

    private let store: TextDocumentStore
    private let registry: LanguageServerRegistry

    /// Keyed by configuration id, which is what `registry.sessions` is keyed by.
    private var pipelines: [UUID: PipelineEntry] = [:]

    /// Drain tasks for sessions that have gone away, kept only until they
    /// finish so `shutdown()` can await them. Keyed by a monotonic token rather
    /// than the configuration id, because the same id can be retired twice —
    /// two quick settings edits — before the first drain has ended.
    private var retiring: [Int: Task<Void, Never>] = [:]
    private var nextRetirementToken = 0

    /// The language id each open URI was opened with.
    ///
    /// Needed because `TextDocumentStore` removes the document from its table
    /// *before* it emits `.closed`, so `store.document(for:)` is already `nil`
    /// when the close event arrives and there is nothing left to ask. It also
    /// saves a dictionary lookup on every keystroke.
    private var languageIdsByURI: [DocumentUri: String] = [:]

    private var storeObservation: TextDocumentStoreObservation?
    private var cancellables: Set<AnyCancellable> = []
    private var isStarted = false
    private var isShutDown = false

    public init(store: TextDocumentStore, registry: LanguageServerRegistry) {
        self.store = store
        self.registry = registry
    }

    // MARK: - Lifecycle

    /// Installs the observers. Idempotent, and a no-op after `shutdown()`.
    ///
    /// Subscribing to `registry.$sessions` delivers the registry's *current*
    /// sessions synchronously, so a sync started after the registry has already
    /// reconciled picks up everything that is already running — which is the
    /// ordinary startup path, not an edge case.
    public func start() {
        guard !isStarted, !isShutDown else { return }
        isStarted = true

        for document in store.openDocuments where isInWorkspaceScope(document.uri) {
            languageIdsByURI[document.uri] = document.languageId
        }

        storeObservation = store.addObserver { [weak self] event in
            self?.handle(event)
        }

        // Non-`@Sendable` closure, so it inherits this class's `@MainActor`
        // isolation — the same shape `LanguageServerRegistry` uses for its own
        // settings subscription.
        //
        // The emitted dictionary is used and `registry.sessions` is never
        // re-read here: `@Published` fires from `willSet`, so the property is
        // still the *old* value for the duration of this callback. Reading it
        // would see a session set that is one mutation behind the event being
        // delivered.
        registry.$sessions
            .sink { [weak self] sessions in
                self?.reconcilePipelines(with: sessions)
            }
            .store(in: &cancellables)
    }

    /// Stops observing, finishes every queue, and returns only once every drain
    /// task has run to completion — so no notification is still in flight when
    /// it returns.
    ///
    /// Every piece of mutable state is taken and cleared **before the first
    /// await**, so a store event or a registry emission that lands during the
    /// drain finds a sync with nothing to do rather than a half-torn-down one.
    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true

        let entries = Array(pipelines.values)
        let retiringTasks = Array(retiring.values)
        pipelines = [:]
        retiring = [:]
        languageIdsByURI = [:]
        // Dropping the token unregisters the store observer; emptying the set
        // cancels the registry subscription.
        storeObservation = nil
        cancellables = []

        // Every stream is ended first, so the drains below run concurrently
        // rather than each waiting for the previous one's server.
        for entry in entries {
            entry.pipeline.finish()
        }
        for entry in entries {
            await entry.drainTask.value
        }
        for task in retiringTasks {
            await task.value
        }
    }

    /// A net under `shutdown()`, not a replacement for it.
    ///
    /// `shutdown()` remains the contract, and only it can *await* the drains —
    /// a deinit cannot. But a drain loop is `for await event in events` over an
    /// `.unbounded` stream, so it ends on exactly one thing: `finish()`. An
    /// owner that is released without calling `shutdown()` would leave every
    /// drain task running forever, each one strongly holding its session and,
    /// through it, a live language-server subprocess. That is an expensive
    /// failure to diagnose from a user report — an orphaned `sourcekit-lsp`
    /// with no window attached to it — and this class currently has no way to
    /// defend itself against the mistake, which Task 3.3 is the first place
    /// able to make.
    ///
    /// Finishing the continuations is all that is needed and all that is safe:
    /// `finish()` is `nonisolated` and synchronous, it delivers the events
    /// already queued before terminating the loop, and each drain task then
    /// runs to completion on its own and releases its session. Retiring tasks
    /// have already had `finish()` called on their pipelines by `retire(_:)`,
    /// so they need nothing here.
    ///
    /// Isolated explicitly (SE-0371): a `@MainActor` class's deinit is
    /// `nonisolated` by default and `pipelines` is main-actor state, so the
    /// deinit has to hop to the actor before reading it. Same shape as
    /// `TextDocumentStoreObservation.deinit`.
    isolated deinit {
        for entry in pipelines.values {
            entry.pipeline.finish()
        }
    }

    // MARK: - Sessions

    private func reconcilePipelines(with sessions: [UUID: any LanguageServerSessionProtocol]) {
        guard !isShutDown else { return }

        // Retire first: a session that was *replaced* keeps its configuration
        // id, so the new pipeline must not be built on top of the old entry.
        for (id, entry) in pipelines {
            if let current = sessions[id], ObjectIdentifier(current) == ObjectIdentifier(entry.session) {
                continue
            }
            pipelines.removeValue(forKey: id)
            retire(entry)
        }

        for (id, session) in sessions where pipelines[id] == nil {
            addPipeline(id: id, session: session)
        }
    }

    private func addPipeline(id: UUID, session: any LanguageServerSessionProtocol) {
        let pipeline = DocumentSyncPipeline(session: session)

        // The task's first statement is `session.start()`, and that placement is
        // load-bearing in two ways.
        //
        // 1. `start()` is the only "the handshake is done" signal a session has
        //    — there is no state stream — and it is `async throws`, so awaiting
        //    it before draining makes ordering free: every queued event lands
        //    behind a server that is either running or known to have failed.
        //
        // 2. It does not matter which caller wins the start race, and there is
        //    a race: this runs inside `registry.$sessions`' `willSet`, i.e.
        //    *before* `LanguageServerRegistry.reconcile` creates its own start
        //    task for the same session, and both are main-actor isolated at the
        //    same priority. Whichever call arrives second joins the first
        //    rather than returning early — `LanguageServerSession.start()`
        //    awaits the in-flight `startTask` and reports its outcome — so by
        //    the time *this* `start()` has returned, the handshake has
        //    definitively completed or definitively failed. That is what lets
        //    `DocumentSyncPipeline` resolve the sync capability once, right
        //    after this await, and read `capabilities()` as a real answer: a
        //    `nil` there means the server published none, never "not yet".
        let drainTask = Task {
            var startFailure: (any Error)?
            do {
                try await session.start()
            } catch {
                startFailure = error
            }
            await pipeline.run(startFailure: startFailure)
        }

        pipelines[id] = PipelineEntry(session: session, pipeline: pipeline, drainTask: drainTask)

        // D7: a new session has nothing open, and the registry reconciles from
        // settings long after documents are open. Replay is therefore the
        // ordinary startup path, not a recovery path.
        replayOpenDocuments(to: pipeline, session: session)
    }

    private func replayOpenDocuments(to pipeline: DocumentSyncPipeline, session: any LanguageServerSessionProtocol) {
        // `languageIds` is `nonisolated`, so claiming needs no await and the
        // whole replay stays in this one main-actor turn.
        let claimed = Set(session.languageIds.map { $0.lowercased() })
        guard !claimed.isEmpty else { return }

        for document in store.openDocuments
        where claimed.contains(document.languageId.lowercased()) && isInWorkspaceScope(document.uri) {
            pipeline.enqueue(.opened(
                uri: document.uri,
                languageId: document.languageId,
                version: document.version,
                text: document.text
            ))
        }
    }

    private func retire(_ entry: PipelineEntry) {
        entry.pipeline.finish()

        let token = nextRetirementToken
        nextRetirementToken += 1
        // Held so `shutdown()` can await it, and self-removing so a long-lived
        // sync does not accumulate one entry per settings edit. The task cannot
        // start before this assignment: it is main-actor isolated and the main
        // actor is busy running this method.
        retiring[token] = Task { [weak self] in
            await entry.drainTask.value
            self?.retiring.removeValue(forKey: token)
        }
    }

    // MARK: - Documents

    /// The store's observer. Synchronous by contract, and every fact the
    /// eventual notification needs is captured here, in this turn.
    private func handle(_ event: TextDocumentEvent) {
        guard !isShutDown else { return }

        switch event {
        case .opened(let uri, let languageId, let version, let text):
            // The one place an out-of-workspace document can enter this class.
            // See `isInWorkspaceScope(_:)` for why this guard, the seeding loop
            // in `start()` and the one in `replayOpenDocuments` are the only
            // three needed.
            guard isInWorkspaceScope(uri) else { return }
            languageIdsByURI[uri] = languageId
            enqueue(
                .opened(uri: uri, languageId: languageId, version: version, text: text),
                languageId: languageId
            )

        case .changed(let uri, let version, let changes):
            guard let languageId = languageIdsByURI[uri], let text = store.document(for: uri)?.text else { return }
            // Reading the text here is safe and reading it later is not.
            // `TextDocument.apply(_:)` mutates the text, bumps the version and
            // *then* notifies, all without suspending, so within this callback
            // `text` and `version` describe the same edit. A pipeline that
            // fetched the text when it got round to sending would pair this
            // version with the text of a later edit — the divergence D2 exists
            // to prevent.
            enqueue(
                .changed(uri: uri, languageId: languageId, version: version, text: text, changes: changes),
                languageId: languageId
            )

        case .dirtyStateChanged(let uri, let isDirty):
            // The only save-shaped signal the store emits: `TextDocument`'s
            // dirty flag clearing. An explicit hook would mean changing
            // `TextDocumentSaveScheduler`'s reviewed contract.
            //
            // Known false positive, deliberately not suppressed:
            // `TextDocument.replaceAll(with:)` — a reload from disk — also
            // calls `setDirty(false)`, so a reload emits a `didSave` carrying
            // text the server is about to be told about again by the `.changed`
            // that follows. One harmless notification; machinery to filter it
            // out would cost more than it saves.
            guard !isDirty else { return }
            guard let languageId = languageIdsByURI[uri], let text = store.document(for: uri)?.text else { return }
            enqueue(.saved(uri: uri, text: text), languageId: languageId)

        case .closed(let uri):
            // The store removed the document before emitting this, so the
            // language id has to come from what was recorded at open time.
            guard let languageId = languageIdsByURI.removeValue(forKey: uri) else { return }
            enqueue(.closed(uri: uri), languageId: languageId)
        }
    }

    // MARK: - Workspace scope

    /// Whether `uri` names a file inside this sync's workspace root.
    ///
    /// A `TextDocumentStore` is app-wide: one window's Quick Note, another
    /// project's file, a scratch buffer under `/tmp` all live in the same store.
    /// A language server started for *this* project has no business being told
    /// about any of them — a `didOpen` for a file outside the root it was
    /// initialised with is at best noise and at worst makes the server index a
    /// tree the user never opened.
    ///
    /// **Why three call sites are enough.** Every other path through this class
    /// is gated on a lookup in `languageIdsByURI` — `.changed`, `.saved` and
    /// `.closed` all `guard let languageId = languageIdsByURI[uri]` and give up
    /// when it misses. So a URI that never gets *into* that table can never
    /// produce a later notification. There are exactly three places a URI enters
    /// the table or reaches a pipeline without going through it: the seeding
    /// loop in `start()`, the `.opened` case in `handle(_:)`, and the replay
    /// loop in `replayOpenDocuments(to:session:)`. Guarding those three is
    /// therefore equivalent to guarding all seven, and cheaper: the scope test
    /// touches the filesystem (symlink resolution), and putting it on the
    /// keystroke path would pay that cost on every edit.
    ///
    /// **Accepted gap.** The root a session is actually initialised with is
    /// resolved by walking *up* from the workspace looking for a root marker, so
    /// it can be an ancestor of `registry.workspaceURL` — a package inside a
    /// monorepo checkout, say. Filtering on `workspaceURL` therefore rejects
    /// some documents the server would have accepted. That is the conservative
    /// side of the error: the cost is a file in a sibling directory not getting
    /// completions, versus a server being fed a tree the user never opened.
    /// Narrowing this to the session's own root would mean asking each session
    /// for its root — an `await` per event on the synchronous store-callback
    /// path — which is not a trade worth making here.
    private func isInWorkspaceScope(_ uri: DocumentUri) -> Bool {
        // Not a file URL — a `untitled:` buffer, or something unparseable. The
        // servers this layer drives are all filesystem-backed, so out of scope.
        guard let url = URL(string: uri), url.isFileURL else { return false }

        let root = workspaceScopeComponents
        guard !root.isEmpty else { return false }

        // Path *components*, never a string prefix: `/Users/me/proj-old` has
        // `/Users/me/proj` as a string prefix but is a different directory.
        let components = Self.scopeComponents(of: url)
        guard components.count >= root.count else { return false }
        return Array(components.prefix(root.count)) == root
    }

    /// Resolved, standardized path components for one URL.
    ///
    /// Both sides of the comparison go through this. Symlink resolution matters
    /// on macOS specifically: `NSTemporaryDirectory()` hands back `/var/folders/...`
    /// which resolves to `/private/var/folders/...`, and `/tmp` resolves to
    /// `/private/tmp`, so a workspace and a document naming the same directory
    /// by different routes would otherwise fail to match.
    ///
    /// What is resolved is the deepest part of the path that is *on disk*, with
    /// whatever is missing appended unresolved. `resolvingSymlinksInPath()` is
    /// a no-op for a path that does not exist, so resolving the whole path
    /// normalises a workspace root (which always exists) while leaving a
    /// document that does not exist alone — and the two then share no prefix.
    /// A file open in the editor and absent from disk is ordinary: switch to a
    /// branch that never had it, or restart the server for a buffer that was
    /// never saved. Walking up to the deepest existing ancestor keeps both
    /// sides normalised the same way, and is identical to resolving the whole
    /// path whenever the whole path exists — which is what keeps a symlinked
    /// *root* matching documents named by its resolved path.
    private static func scopeComponents(of url: URL) -> [String] {
        var candidate = url.standardizedFileURL
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            // "/" is its own parent: stop rather than loop forever.
            guard parent.pathComponents != candidate.pathComponents else { break }
            missingComponents.insert(candidate.lastPathComponent, at: 0)
            candidate = parent
        }
        return candidate.resolvingSymlinksInPath().pathComponents + missingComponents
    }

    /// Computed once, on first use rather than in `init`, because resolving
    /// symlinks hits the filesystem and a sync is constructed before anything
    /// has asked it a question.
    private lazy var workspaceScopeComponents: [String] = Self.scopeComponents(of: registry.workspaceURL)

    /// Routes one snapshot to every pipeline whose session claims `languageId`.
    ///
    /// Routing is by `session.languageIds` rather than by
    /// `registry.configuration(forLanguageId:)` so that it is the *same*
    /// question `replayOpenDocuments` asks. If the two disagreed, a session
    /// could receive a `didOpen` and then none of that document's edits — the
    /// worst of both worlds. Two enabled configurations claiming one language
    /// is possible only among the user's own entries, and both servers getting
    /// the traffic is the honest reading of "enabled".
    private func enqueue(_ event: DocumentSyncEvent, languageId: String) {
        let wanted = languageId.lowercased()
        for entry in pipelines.values
        where entry.session.languageIds.contains(where: { $0.lowercased() == wanted }) {
            entry.pipeline.enqueue(event)
        }
    }
}
