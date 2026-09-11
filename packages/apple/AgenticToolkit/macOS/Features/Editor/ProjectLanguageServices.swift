//
//  ProjectLanguageServices.swift
//  AgenticToolkit
//

import AgenticToolkitLanguage
import Foundation

/// The language-server stack for one open project: a `LanguageServerRegistry`
/// rooted at that project's directory, and the `LanguageServerDocumentSync`
/// that feeds it every open, edit, save and close of a document inside it.
///
/// Tasks 3.1 and 3.2 built both halves; nothing constructed either of them.
/// This is the object that does, and it exists so that "start the language
/// servers for this project" and "stop them" are each one call from
/// `ProjectWindowManager` rather than two objects a window has to keep in step.
///
/// **Not an `AppFeature`.** `AppFeature.init()` self-registers into an app-wide
/// `AppFeatureRegistry`, which is the wrong scope by construction: there is one
/// of these per open project window, they come and go with those windows, and
/// an app-wide registry would keep every one of them alive for the life of the
/// process. Ownership belongs to the window; `ProjectsCoordinator` reaches them
/// through `ProjectWindowManager` when the app terminates.
@MainActor
public final class ProjectLanguageServices {

    /// The registry consumers query — the completion and go-to-definition
    /// delegates ask it for the session serving a language.
    public let registry: LanguageServerRegistry

    /// Private on purpose. The sync has no consumer-facing API: it is a wire
    /// between the document store and the registry, and every caller that needs
    /// something from this object needs the registry.
    private let sync: LanguageServerDocumentSync

    /// Held, not merely passed through to the sync, because `start()` needs it
    /// too: this object is the only one that holds both the document store and
    /// the diagnostic store, so it is the only place the two can be wired
    /// together.
    private let documentStore: TextDocumentStore

    /// Everything the servers have said, unasked, about this project's files.
    ///
    /// Public where `sync` is private because this one *does* have consumers:
    /// the editor's annotation coordinator subscribes to it per URI to draw the
    /// squiggles, and reads it to answer a hover without a round trip.
    public let diagnostics: DiagnosticStore

    private var isStarted = false
    private var isShutDown = false

    public init(documentStore: TextDocumentStore, registry: LanguageServerRegistry) {
        self.registry = registry
        self.documentStore = documentStore
        self.sync = LanguageServerDocumentSync(store: documentStore, registry: registry)
        self.diagnostics = DiagnosticStore()
    }

    /// Installs the document-sync observers. Idempotent, and a no-op after
    /// `shutdown()`.
    ///
    /// The registry needs no start call: it subscribes to the settings
    /// publishers in its own initialiser and has already reconciled by the time
    /// this runs.
    public func start() {
        guard !isStarted, !isShutDown else { return }
        isStarted = true
        sync.start()
        // Subscribes to `registry.$sessions`, so it picks up both the sessions
        // already running and every session started later — a file is routinely
        // open before its server has finished handshaking, and a store wired
        // only to what existed at construction would show nothing for it.
        diagnostics.observeSessions(from: registry)
        // And the other end of the store's lifetime: a document that closes
        // takes its diagnostics with it, instead of leaving them in a map that
        // grows by one entry per file the user has ever opened.
        diagnostics.observeDocuments(in: documentStore)
    }

    /// Tears the stack down, sync first.
    ///
    /// The order is load-bearing, not stylistic. `sync.shutdown()` finishes
    /// every pipeline queue and awaits the drain tasks, so it returns only once
    /// every `didClose`/`didSave` already queued has actually been written to a
    /// server that is still running. Shutting the registry down first would stop
    /// those servers underneath the drains, and every pending notification would
    /// fail against a dead subprocess.
    ///
    /// Best-effort by contract: it never throws, and a session that refuses to
    /// exit is the registry's problem to bound, not this one's.
    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        await sync.shutdown()
        // Before `registry.shutdown()`, for the same reason as the sync: the
        // store's observation tasks read streams owned by sessions the registry
        // is about to stop. Stopping them first would leave those tasks to be
        // ended by a stream finish arriving from underneath, which works but
        // makes the ordering accidental instead of stated. Synchronous — it
        // cancels tasks and does not await them, because nothing it could still
        // deliver is worth waiting for during teardown.
        diagnostics.shutdown()
        await registry.shutdown()
    }
}
