//
//  DocumentSyncPipeline.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import OSLog

/// What a server asked for in `ServerCapabilities.textDocumentSync`, reduced to
/// three plain values.
///
/// The wire type is a `TwoTypeOption` wrapping an options struct whose own
/// fields are all optional, so "does this server want `didOpen`" is a
/// three-level question every call site would otherwise answer for itself.
/// Answering it once, into an `Equatable` value, is also what makes the mapping
/// testable without a server.
public struct ResolvedTextDocumentSync: Equatable, Sendable {

    /// Whether to send `didOpen`/`didClose` at all.
    public var openClose: Bool

    /// How to send `didChange`; `.none` means "do not send it".
    public var change: TextDocumentSyncKind

    /// `nil` means "do not send `didSave`". Otherwise `includeText` decides
    /// whether the notification carries the document's text.
    public var save: SaveOptions?

    public init(openClose: Bool, change: TextDocumentSyncKind, save: SaveOptions?) {
        self.openClose = openClose
        self.change = change
        self.save = save
    }

    /// Everything off — what a server that declared no `textDocumentSync` gets.
    ///
    /// Spelled `disabled` rather than `none` so `sync = .disabled` can never be
    /// read as `Optional.none` at a call site.
    public static let disabled = ResolvedTextDocumentSync(openClose: false, change: .none, save: nil)

    /// The fixed mapping from the declared capability.
    ///
    /// `openClose` defaults to **`true`** when a server sends
    /// `TextDocumentSyncOptions` without it: a server that declares a change
    /// kind and omits `openClose` is relying on the protocol's default-on
    /// behaviour, and the two failure modes are wildly asymmetric — a stray
    /// `didOpen` to a server that ignores it costs one notification, while
    /// omitting `didOpen` makes every later request answer "unknown document".
    ///
    /// `nil` is not an error. It means "send this server nothing at all", which
    /// is a legitimate configuration and is not logged as a problem.
    public static func resolve(
        _ value: TwoTypeOption<TextDocumentSyncOptions, TextDocumentSyncKind>?
    ) -> ResolvedTextDocumentSync {
        switch value {
        case nil:
            return .disabled
        case .optionB(let kind):
            // A bare kind carries no options, so `save` stays off: a server
            // that wants `didSave` has to say so in the options form.
            return ResolvedTextDocumentSync(openClose: true, change: kind, save: nil)
        case .optionA(let options):
            return ResolvedTextDocumentSync(
                openClose: options.openClose ?? true,
                change: options.change ?? .none,
                save: options.effectiveSave
            )
        }
    }
}

/// One document lifecycle fact, captured whole on the main actor.
///
/// Every case carries **everything** the eventual notification needs, because
/// the send happens later and on a different actor. Reaching back to a
/// `TextDocument` from the pipeline would pair a version captured then with a
/// text read now, and the two drift apart the moment a second edit lands while
/// the first send is in flight — which is exactly how a server's mirror of a
/// buffer silently diverges from what the user is looking at.
///
/// `.changed` therefore carries the incremental changes **and** the full text
/// as of the same version; which one goes on the wire is the server's choice,
/// made later, from facts that were true at the same instant.
///
/// Named `DocumentSyncEvent` rather than the brief's `SyncEvent` because the
/// toolkit already ships an `AgenticToolkitSync` framework, and a bare
/// `SyncEvent` in a second framework is a name collision waiting for the first
/// file that imports both.
enum DocumentSyncEvent: Sendable {
    case opened(uri: DocumentUri, languageId: String, version: Int, text: String)
    /// Carries `languageId` in addition to the brief's sketch: D6's rule 2 turns
    /// a change to a document the server does not have into a `didOpen`, and a
    /// `TextDocumentItem` cannot be built without it. Reading it back off the
    /// store at send time is exactly the cross-isolation reach D2 forbids.
    case changed(
        uri: DocumentUri,
        languageId: String,
        version: Int,
        text: String,
        changes: [TextDocumentContentChangeEvent]
    )
    case saved(uri: DocumentUri, text: String)
    case closed(uri: DocumentUri)
}

/// The FIFO that carries one session's document notifications, and the state
/// that must not be read from two isolation domains: which URIs it believes the
/// server has open, the resolved sync capability, and whether `start()` failed.
///
/// **Why a queue at all.** `TextDocumentStore`'s observer is a *synchronous*
/// main-actor callback and `LanguageServerSessionProtocol`'s notifications are
/// `async throws` on another actor, so the observer cannot await inline; it has
/// to hand the event off and return. A `Task { await session.didChange(...) }`
/// per event would do that — and would not preserve order, because unstructured
/// tasks are unordered. Two keystrokes would routinely reach the server
/// reversed. `AsyncStream.Continuation.yield` is synchronous, order-preserving
/// and callable from the main actor without awaiting, and exactly one task
/// drains it, awaiting each send in turn.
///
/// **Why one queue per session rather than per document.** Every document on
/// one server travels one wire, so one queue is strictly correct where
/// per-document queues merely look correct. The cost is that a slow send for
/// one document delays another on the same server; that cost is a write to a
/// pipe.
actor DocumentSyncPipeline {

    /// How many events are held while the server's capabilities are still
    /// unknown. See `resolvedSync()` for why that window exists at all. The
    /// bound is what keeps "never queue indefinitely waiting for a server"
    /// true: past it the oldest events are dropped, and D6's rule 2 repairs the
    /// server's view on the next edit.
    private static let pendingLimit = 256

    private let session: any LanguageServerSessionProtocol
    private let events: AsyncStream<DocumentSyncEvent>

    /// `nonisolated` so the main-actor observer can `yield` without awaiting.
    /// That is the whole point of the seam: yielding is synchronous and
    /// ordered, so no ordering decision is ever made off the main actor.
    private nonisolated let continuation: AsyncStream<DocumentSyncEvent>.Continuation

    /// Write-once. `nil` means "not settled yet", which is *not* the same as
    /// "this server wants nothing" — that is `.disabled`.
    private var sync: ResolvedTextDocumentSync?

    /// Set when the session reached a terminal state without ever publishing
    /// capabilities. Stops `resolvedSync()` asking again for ever.
    private var resolutionAbandoned = false

    /// Events that arrived before the capability was known. Bounded by
    /// `pendingLimit` and flushed, in order, the instant it becomes known.
    private var pending: [DocumentSyncEvent] = []

    /// What this client believes the server has open. Not authoritative — it is
    /// a belief, and every failed notification corrects it downward so the next
    /// change re-opens the document instead of editing one the server lost.
    private var openURIs: Set<DocumentUri> = []

    /// Set when `start()` threw. Every later event is dropped for the life of
    /// this pipeline: without that, a missing server binary means every
    /// keystroke re-spawns a failing subprocess. The registry replaces the
    /// session object when its configuration, secrets or resolved root change,
    /// and that replacement is the reset — fixing a bad command in settings
    /// gives you a fresh session and a fresh pipeline.
    private var startFailed = false

    init(session: any LanguageServerSessionProtocol) {
        let (stream, continuation) = AsyncStream<DocumentSyncEvent>.makeStream()
        self.session = session
        self.events = stream
        self.continuation = continuation
    }

    /// Enqueues one event. Synchronous, order-preserving, and callable from the
    /// main actor. Events yielded before `run(startFailure:)` is reached are
    /// buffered by the stream and drained in order behind it.
    nonisolated func enqueue(_ event: DocumentSyncEvent) {
        continuation.yield(event)
    }

    /// Ends the stream, which is what lets `run(startFailure:)` return. Safe to
    /// call more than once.
    nonisolated func finish() {
        continuation.finish()
    }

    /// Drains the queue until `finish()` is called.
    ///
    /// `startFailure` is the outcome of `session.start()`, awaited by the caller
    /// rather than here — see `LanguageServerDocumentSync.makeEntry` for why
    /// that call has to be the drain task's own first statement. To this actor
    /// the distinction is only "there is a server" versus "there is not, and
    /// never will be for this session object".
    func run(startFailure: (any Error)?) async {
        if let startFailure {
            startFailed = true
            let name = session.name
            let message = startFailure.localizedDescription
            Self.logger.error(
                """
                Language server \(name, privacy: .public) failed to start; \
                dropping document synchronisation: \(message, privacy: .public)
                """
            )
        } else {
            _ = await resolvedSync()
        }

        // The stream is drained on the failure path too: it has to terminate
        // when `finish()` is called, and an undrained queue behind a server that
        // will never run is a leak.
        for await event in events {
            guard !startFailed else { continue }
            await handle(event)
        }
    }

    // MARK: - Capability resolution

    /// The resolved capability, or `nil` while the server has not published one.
    ///
    /// `capabilities()` answering `nil` is precisely "the `initialize` handshake
    /// has not completed", and there is a reachable ordering in which this
    /// pipeline's own `session.start()` was a no-op because
    /// `LanguageServerRegistry.reconcile` had already started the same session
    /// — `LanguageServerSession.start()` returns immediately, without waiting,
    /// when the session is already `.starting`. Treating that `nil` as "this
    /// server wants nothing" would silence the pipeline permanently, so it is
    /// treated as "not yet" and asked again on the next event. Asking again is
    /// one actor hop, only while unresolved, and only when there is real work.
    ///
    /// It is bounded twice over: a session that reaches `.failed` or `.stopped`
    /// without capabilities is abandoned outright, and `pending` is capped.
    private func resolvedSync() async -> ResolvedTextDocumentSync? {
        if let sync { return sync }
        guard !resolutionAbandoned else { return nil }

        if let capabilities = await session.capabilities() {
            // Write-once, and this actor's single drain task is the only writer,
            // so nothing can have raced it across the await above.
            let resolved = ResolvedTextDocumentSync.resolve(capabilities.textDocumentSync)
            sync = resolved
            return resolved
        }

        switch await session.state {
        case .failed, .stopped:
            resolutionAbandoned = true
            pending.removeAll()
        case .idle, .starting, .running:
            break
        }
        return nil
    }

    // MARK: - Forwarding

    private func handle(_ event: DocumentSyncEvent) async {
        guard let sync = await resolvedSync() else {
            guard !resolutionAbandoned else { return }
            pending.append(event)
            if pending.count > Self.pendingLimit {
                pending.removeFirst(pending.count - Self.pendingLimit)
            }
            return
        }

        if !pending.isEmpty {
            let queued = pending
            pending = []
            for queuedEvent in queued {
                await forward(queuedEvent, sync: sync)
            }
        }
        await forward(event, sync: sync)
    }

    /// `sync` is passed rather than re-read after each await because it is
    /// write-once: once resolved it never changes, so a local copy cannot go
    /// stale across a suspension.
    private func forward(_ event: DocumentSyncEvent, sync: ResolvedTextDocumentSync) async {
        switch event {
        case .opened(let uri, let languageId, let version, let text):
            guard sync.openClose else { return }
            await sendDidOpen(uri: uri, languageId: languageId, version: version, text: text)

        case .changed(let uri, let languageId, let version, let text, let changes):
            await sendDidChange(
                uri: uri,
                languageId: languageId,
                version: version,
                text: text,
                changes: changes,
                sync: sync
            )

        case .saved(let uri, let text):
            guard let save = sync.save else { return }
            await sendDidSave(uri: uri, text: save.includeText == true ? text : nil)

        case .closed(let uri):
            guard sync.openClose, openURIs.contains(uri) else { return }
            await sendDidClose(uri: uri)
        }
    }

    private func sendDidChange(
        uri: DocumentUri,
        languageId: String,
        version: Int,
        text: String,
        changes: [TextDocumentContentChangeEvent],
        sync: ResolvedTextDocumentSync
    ) async {
        // D6 rule 2, and the reason a dropped notification costs one extra
        // full-text open rather than a permanently stale buffer: the server does
        // not have this document, so describing an edit to it is meaningless.
        // Send the whole document instead, at the version this snapshot was
        // taken at. Checked before the change kind because it is about the open
        // state, not about how changes travel — a `.none` server still wants its
        // opens repaired.
        if sync.openClose, !openURIs.contains(uri) {
            await sendDidOpen(uri: uri, languageId: languageId, version: version, text: text)
            return
        }

        let contentChanges: [TextDocumentContentChangeEvent]
        switch sync.change {
        case .none:
            return
        case .full:
            // Both `range` and `rangeLength` nil is LSP's own wire form for
            // whole-document replacement. One event per store event, never a
            // coalesced batch: the store already batches an edit batch into a
            // single change, and a coalescer that drops a superseded change is
            // one version-tracking mistake away from a permanently divergent
            // buffer.
            contentChanges = [TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: text)]
        case .incremental:
            contentChanges = changes
        }

        do {
            try await session.didChange(DidChangeTextDocumentParams(
                uri: uri,
                version: version,
                contentChanges: contentChanges
            ))
        } catch {
            openURIs.remove(uri)
            record(error, operation: "didChange", uri: uri)
        }
    }

    private func sendDidOpen(uri: DocumentUri, languageId: String, version: Int, text: String) async {
        do {
            try await session.didOpen(DidOpenTextDocumentParams(textDocument: TextDocumentItem(
                uri: uri,
                languageId: languageId,
                version: version,
                text: text
            )))
            openURIs.insert(uri)
        } catch {
            openURIs.remove(uri)
            record(error, operation: "didOpen", uri: uri)
        }
    }

    private func sendDidSave(uri: DocumentUri, text: String?) async {
        do {
            try await session.didSave(DidSaveTextDocumentParams(uri: uri, text: text))
        } catch {
            openURIs.remove(uri)
            record(error, operation: "didSave", uri: uri)
        }
    }

    private func sendDidClose(uri: DocumentUri) async {
        // Forgotten before the send rather than after it: whether the
        // notification lands or throws, this client is no longer holding the
        // document open, and a failed close that left the URI in the set would
        // suppress the re-open that repairs the next edit.
        openURIs.remove(uri)
        do {
            try await session.didClose(DidCloseTextDocumentParams(uri: uri))
        } catch {
            record(error, operation: "didClose", uri: uri)
        }
    }

    /// `.notRunning` is a typed, expected outcome — a document touched before
    /// `initialize` finished, or any event after `stop()` — so it is debug, not
    /// error. Anything else is a real transport or protocol failure.
    private func record(_ error: any Error, operation: String, uri: DocumentUri) {
        let name = session.name
        if let sessionError = error as? LanguageServerSessionError, sessionError == .notRunning {
            Self.logger.debug(
                """
                \(operation, privacy: .public) to \(name, privacy: .public) was dropped: \
                the server is not running (\(uri, privacy: .public))
                """
            )
        } else {
            let message = error.localizedDescription
            Self.logger.error(
                """
                \(operation, privacy: .public) to \(name, privacy: .public) failed \
                (\(uri, privacy: .public)): \(message, privacy: .public)
                """
            )
        }
    }
}

extension DocumentSyncPipeline: Loggable {
    static nonisolated let logger = makeLogger()
}
