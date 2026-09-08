import AgenticToolkitCore
import AgenticToolkitLanguage
import SwiftUI
import Combine
import CodeEditSourceEditor
import CodeEditLanguages
import LanguageServerProtocol
import os

// MARK: - Editor State

/// Observable state for the file viewer: what to show, the bounded cache of
/// documents this pane has open, and load/unload/save orchestration.
///
/// Internal rather than private so the tests can drive a selection sequence
/// and assert that a cached document's storage and editor survive it — the
/// behaviour this task exists for, and one that a compile cannot show.
@MainActor
final class FileEditorState: ObservableObject {

    /// How many documents one pane keeps live at once, LRU by last selection.
    ///
    /// A bound exists because a cached document is not free: it holds a
    /// mounted `TextViewController` with its own layout manager, selection
    /// manager, gutter, minimap and tree-sitter parse tree, plus a reference
    /// on the app-wide `TextDocumentStore` that every other window's file
    /// browser then pays for. Browsing a couple of hundred files in a session
    /// is ordinary; keeping a couple of hundred live editors is not. Undo
    /// across the eight most recently visited files is the feature — the
    /// ninth-most-recent losing its undo stack is the accepted cost.
    static let maximumCachedDocuments = 8

    /// What the viewer is showing for the current file.
    enum Display: Equatable {
        /// Nothing selected, or a directory — no editor is shown.
        case empty
        /// Still reading.
        case loading
        /// A cached document, live in its own `SourceEditor` — see `slotsByURI`.
        case text(uri: DocumentUri)
        /// Handed to QuickLook — an image, a PDF, a movie, or a file too large
        /// for the editor.
        case quickLook(URL)
        /// Unreadable.
        case unavailable
    }

    /// One document this pane has opened: its `TextDocument`/`TextDocumentStorage`
    /// pair, the language it was detected as, its own `SourceEditor` cursor/scroll
    /// state, and the token keeping its autosave-on-change handler registered.
    /// Never rebuilt for a URI already present — see the type-level comment on
    /// `FileEditorContentView` for why that specifically is load-bearing.
    private struct Slot {
        let document: TextDocument
        let storage: TextDocumentStorage
        let language: CodeLanguage
        var sourceEditorState: SourceEditorState
        let changeObservation: TextDocumentObservation

        /// The language-server objects for this document. Held here because
        /// `SourceEditor` stores the two delegates `weak` and keeps a
        /// coordinator only for as long as its controller lives, so something
        /// has to own all three — and the slot's lifetime is exactly the cached
        /// editor's, so eviction releases them with everything else the
        /// document owns. `nil` when the pane has no language services, or (for
        /// the jump delegate) no way to open another file.
        let completionDelegate: LSPCompletionDelegate?
        let jumpToDefinitionDelegate: LSPJumpToDefinitionDelegate?
        let annotationCoordinator: LSPEditorAnnotationCoordinator?

        /// The semantic-token highlighter and the tree-sitter client it is
        /// layered over, held for the same reason as the three above and for
        /// one more: `SourceEditor.paramsAreEqual` compares highlight providers
        /// by `ObjectIdentifier`, so a fresh pair on each render would look like
        /// a different editor every time and tear the whole `Highlighter` down.
        /// Constructed once here, they are the *same objects* on every render.
        ///
        /// The `TreeSitterClient` is stored rather than left to `SourceEditor`'s
        /// own default because that default is only reached when
        /// `highlightProviders` is `nil` — passing an array means passing every
        /// provider in it, tree-sitter included.
        let semanticTokenProvider: SemanticTokenHighlightProvider?
        let treeSitterClient: TreeSitterClient?
    }

    private let documentStore: TextDocumentStore
    private let saveScheduler: TextDocumentSaveScheduler

    /// This pane's project language servers, or `nil` if it has none. The
    /// *holder* rather than the registry itself, so the per-project objects
    /// later tasks add beside it change no signature in this stack.
    private let languageServices: ProjectLanguageServices?

    /// How a cross-file go-to-definition target is shown. Injected from the
    /// view that owns the selection; this type knows nothing about a file tree.
    private let openFile: (@MainActor (URL) -> Void)?

    /// How the current file is being shown.
    @Published private(set) var display: Display = .empty

    /// Each open document's completion trigger characters, as its language
    /// server declares them.
    ///
    /// `@Published` because this is the one piece of a slot that arrives
    /// *after* the slot is built: resolving it needs an `await` on the session
    /// actor. A change here re-runs `makeEditor`, whose new
    /// `SourceEditorConfiguration` is diffed against the mounted controller's,
    /// and `Peripherals.didSetOnController` reacts to this field specifically —
    /// so a set that lands seconds after the editor was built still reaches it.
    ///
    /// Not a hardcoded default: `[".", "(", ":"]` are sourcekit-lsp's answer,
    /// and every other server has its own. The registry exists precisely
    /// because that answer differs per language.
    @Published private(set) var completionTriggerCharacters: [DocumentUri: Set<String>] = [:]

    private var slotsByURI: [DocumentUri: Slot] = [:]

    /// Every currently cached URI, in the order its editor was mounted —
    /// what `CachedEditorStack` iterates. Deliberately *not* reordered on
    /// selection: mount order is stable so nothing already on screen moves.
    /// Entries leave only by eviction. `@Published` so a newly-opened
    /// document's editor appears and an evicted one's disappears.
    @Published private(set) var openOrder: [DocumentUri] = []

    /// The same URIs, least-recently-selected first. This is what eviction
    /// reads; `openOrder` is what the view reads.
    private var recencyOrder: [DocumentUri] = []

    /// The URL of the currently loaded file.
    private var currentURL: URL?

    /// The in-flight read. Cancelled when a new selection arrives so a slow
    /// file can't land on top of a newer one.
    private var loadTask: Task<Void, Never>?

    /// One per open document, resolving that document's trigger characters.
    /// Kept so eviction can cancel a resolution for a slot that no longer
    /// exists, and so tests have something to await.
    private var triggerCharacterTasks: [DocumentUri: Task<Void, Never>] = [:]

    /// Holds the subscriptions to `registry.$sessions` and
    /// `registry.$sessionStates`.
    private var cancellables: Set<AnyCancellable> = []

    init(
        documentStore: TextDocumentStore,
        saveScheduler: TextDocumentSaveScheduler,
        languageServices: ProjectLanguageServices?,
        openFile: (@MainActor (URL) -> Void)?
    ) {
        self.documentStore = documentStore
        self.saveScheduler = saveScheduler
        self.languageServices = languageServices
        self.openFile = openFile

        // A session can appear *after* a slot is open: the registry creates one
        // when a language server is added or enabled in settings, and this pane
        // may already be showing a file of that language. Resolution at
        // slot-open time answers `[]` in that case, and with `openSlot` as the
        // only caller nothing would ever ask again — the completion window
        // never opening on `.` for that buffer, which is the defect the eager
        // resolution was added to fix, re-entering by another door.
        //
        // `LanguageServerDocumentSync` watches `registry.$sessions` for the
        // same reason; this is that pattern rather than a second one. The sink
        // closure is not `@Sendable`, so it inherits this class's `@MainActor`.
        // Doing the work in a `Task` also gets us off `@Published`'s `willSet`:
        // `registry.sessions` still holds the *old* dictionary while the sink
        // runs, and `resolveTriggerCharacters()` reads it back through
        // `registry.session(forLanguageId:)`.
        //
        // **Two publishers, because they answer two different questions.**
        // `$sessions` answers *which server serves this language* — it emits
        // when a session is created, retired or replaced. `$sessionStates`
        // answers *what that server is doing* — it emits when the same session
        // moves between `.idle`, `.starting`, `.running`, `.failed` and
        // `.stopped`. Trigger characters depend on both, because a session's
        // capabilities are unreadable until it is running.
        //
        // The second sink closes a case the first cannot see. The registry
        // installs a session in `sessions` and then starts it in a `Task`; the
        // outcome of that start — running, or a `start()` that threw — never
        // touches `sessions`, so `$sessions` stays silent through it. A slot
        // opened during the handshake therefore resolved `[]` (capabilities are
        // `nil` until the session is running) and, with `$sessions` as the only
        // trigger, nothing ever asked again: the buffer's trigger characters
        // stayed empty forever and `.` never opened the completion window.
        let registry = languageServices?.registry
        registry?.$sessions
            .sink { [weak self] _ in self?.resolveTriggerCharactersForOpenSlots() }
            .store(in: &cancellables)
        registry?.$sessionStates
            .sink { [weak self] _ in self?.resolveTriggerCharactersForOpenSlots() }
            .store(in: &cancellables)
    }

    /// Re-asks every open slot for its completion trigger characters.
    ///
    /// One method rather than two identical sink bodies: both publishers mean
    /// the same thing to this class — *what a slot last resolved may now be
    /// wrong* — and the resolution is idempotent and republishes nothing when
    /// the answer is unchanged.
    private func resolveTriggerCharactersForOpenSlots() {
        for uri in slotsByURI.keys {
            startTriggerCharacterResolution(for: uri)
        }
    }

    // Isolated explicitly (SE-0371): a MainActor class's deinit is
    // nonisolated by default, and `documentStore.close` is MainActor-isolated.
    // `isolated deinit` hops to the actor before running, the same shape as
    // `TextDocumentStoreObservation.deinit`.
    //
    // This pane releases every document it still has cached when it itself
    // goes away (the containing tab or window closes) — not on every
    // file-to-file switch, which is deliberately *not* paired 1:1 with
    // `store.open` here: closing on every switch would destroy the
    // `NSTextStorage` and with it the undo stack this design exists to keep.
    //
    // Flush, never cancel. `cancel(uri:)` is not reference-counted, so a pane
    // closing while another pane is mid-edit on the same file would throw
    // away *that* pane's pending save and silently lose the edit. The flush
    // and the close run in a `Task` because the flush is `async` and a deinit
    // cannot await; both the store and the scheduler are app-wide and outlive
    // this object, so the work is safe to finish a tick later. Closing a tick
    // late is harmless: reopening the same file in the meantime bumps the
    // refcount first, so the deferred close only ever drops this pane's own
    // reference.
    isolated deinit {
        loadTask?.cancel()
        for task in triggerCharacterTasks.values {
            task.cancel()
        }
        let scheduler = saveScheduler
        let store = documentStore
        let uris = openOrder
        Task { @MainActor in
            for uri in uris {
                await scheduler.flushPendingSave(uri: uri)
                store.close(uri: uri)
            }
        }
    }

    /// The document whose editor should be visible, if any.
    var activeURI: DocumentUri? {
        if case .text(let uri) = display { return uri }
        return nil
    }

    func storage(for uri: DocumentUri) -> TextDocumentStorage? {
        slotsByURI[uri]?.storage
    }

    func language(for uri: DocumentUri) -> CodeLanguage? {
        slotsByURI[uri]?.language
    }

    func document(for uri: DocumentUri) -> TextDocument? {
        slotsByURI[uri]?.document
    }

    func completionDelegate(for uri: DocumentUri) -> LSPCompletionDelegate? {
        slotsByURI[uri]?.completionDelegate
    }

    func jumpToDefinitionDelegate(for uri: DocumentUri) -> LSPJumpToDefinitionDelegate? {
        slotsByURI[uri]?.jumpToDefinitionDelegate
    }

    func annotationCoordinator(for uri: DocumentUri) -> LSPEditorAnnotationCoordinator? {
        slotsByURI[uri]?.annotationCoordinator
    }

    /// The highlight providers one cached document's editor is built with, in
    /// priority order, or `nil` to leave `SourceEditor` its own default.
    ///
    /// **The order is the feature, and it is the opposite of what "layered over
    /// tree-sitter" sounds like.** `StyledRangeContainer` resolves an overlap in
    /// favour of the *lower* provider id, and a provider's id is its index in
    /// this array — so the semantic provider goes first, at index 0, and
    /// tree-sitter second. Appended instead, it would compile, run, send
    /// requests and never paint a character.
    ///
    /// `nil` rather than `[TreeSitterClient()]` when there is no semantic
    /// provider: that is what `SourceEditor` already does with `nil`, and
    /// building the client here would only add a fresh object per render for
    /// `paramsAreEqual` to notice.
    func highlightProviders(for uri: DocumentUri) -> [any HighlightProviding]? {
        guard let slot = slotsByURI[uri],
              let semanticTokenProvider = slot.semanticTokenProvider,
              let treeSitterClient = slot.treeSitterClient else { return nil }
        return [semanticTokenProvider, treeSitterClient]
    }

    /// The configuration one cached document's editor is built with.
    ///
    /// Built here rather than inline in the view because
    /// `peripherals.codeSuggestionTriggerCharacters` is the live path by which
    /// a language server's trigger set reaches the editor —
    /// `CodeSuggestionDelegate.completionTriggerCharacters()` is never called by
    /// this package — and a path that load-bearing has to be reachable from a
    /// test. `FileEditorContentView.makeEditor` passes the result of exactly
    /// this call to `SourceEditor`, so asserting on it asserts on what the
    /// editor is given.
    func editorConfiguration(for uri: DocumentUri, palette: SemanticPalette) -> SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                // Both derived from the one palette in the environment, so a
                // theme switch repaints the editor's chrome, syntax and font
                // together.
                theme: palette.editorTheme,
                font: palette.font(.code),
                wrapLines: false
            ),
            peripherals: SourceEditorConfiguration.Peripherals(
                showGutter: true,
                showMinimap: true,
                codeSuggestionTriggerCharacters: completionTriggerCharacters[uri] ?? []
            )
        )
    }

    func sourceEditorStateBinding(for uri: DocumentUri) -> Binding<SourceEditorState> {
        Binding(
            get: { [weak self] in self?.slotsByURI[uri]?.sourceEditorState ?? SourceEditorState() },
            set: { [weak self] newValue in self?.slotsByURI[uri]?.sourceEditorState = newValue }
        )
    }

    /// Test seam: awaits whatever read `load(from:)` started, so a test can
    /// assert against the state the load produced rather than poll for it.
    func awaitPendingLoad() async {
        await loadTask?.value
    }

    /// Test seam: awaits every in-flight trigger-character resolution, so a
    /// test can assert against the configuration a resolved slot builds rather
    /// than poll for it.
    func awaitPendingTriggerCharacterResolution() async {
        for task in triggerCharacterTasks.values {
            await task.value
        }
    }

    /// Reads `url` off the main thread and shows it however it classifies. A
    /// URI already cached (this pane has shown it recently) is shown
    /// immediately with no re-read of disk and no rebuild of its editor — both
    /// the "switch back and the edit is still there" and the undo-survival
    /// requirements depend on that document never being touched again after
    /// its first open.
    func load(from url: URL) {
        loadTask?.cancel()
        guard url != currentURL else { return }
        let outgoing = currentURL?.documentUri
        currentURL = url

        let uri = url.documentUri
        if slotsByURI[uri] != nil {
            touch(uri)
            display = .text(uri: uri)
            // Nothing is opened on this path, so there is no open to order
            // the flush against — it only has to happen, not to happen
            // first. See `load`'s other path for the case the ordering
            // requirement is actually about.
            flushInBackground(outgoing)
            return
        }

        display = .loading

        let scheduler = saveScheduler
        loadTask = Task { [weak self] in
            // Awaited, not fire-and-forget: the outgoing file's pending save
            // is on disk *before* the incoming document is opened. Doing this
            // as a detached `Task` and then loading synchronously — which is
            // what this used to be — provided no ordering at all.
            if let outgoing {
                await scheduler.flushPendingSave(uri: outgoing)
            }

            let content = await FilePreviewLoader.read(url)
            guard let self, !Task.isCancelled, self.currentURL == url else { return }

            switch content {
            case .text(let text):
                self.openSlot(uri: uri, url: url, text: text)
                self.display = .text(uri: uri)
                logger.info("Loaded file: \(url.lastPathComponent, privacy: .public)")

            case .quickLook:
                self.display = .quickLook(url)

            case .unavailable:
                self.display = .unavailable
            }
        }
    }

    /// Opens `uri` on the shared store and wraps it in a `TextDocumentStorage`,
    /// wiring its changes to the autosave scheduler. Called at most once per
    /// URI per stay in the cache.
    private func openSlot(uri: DocumentUri, url: URL, text: String) {
        let language = LanguageDetection.language(for: url)
        let languageId = LanguageDetection.lspLanguageId(for: language)
        let document = documentStore.open(uri: uri, languageId: languageId, text: text)
        let storage = TextDocumentStorage(document: document)

        let scheduler = saveScheduler
        // [weak document]: this closure is retained by `document`'s own
        // change-handler dictionary for as long as `changeObservation` (held
        // in `Slot`, held in `slotsByURI`, held by `self`) is alive. Capturing
        // `document` strongly here would have it keep itself alive through
        // its own handler storage — the same reason `TextDocumentStorage.init`
        // captures `[weak self]` for its own change handler.
        let changeObservation = document.addChangeHandler { [weak document] _, _ in
            guard let document else { return }
            scheduler.schedule(document)
        }

        // All four are per-document, because every offset<->`Position`
        // conversion they do is resolved against this one document. A pane with
        // no language services simply has none of them, and `SourceEditor`
        // treats a `nil` delegate as "no completion" / "no jump", an empty
        // `coordinators:` as "no annotations", and a `nil` `highlightProviders:`
        // as "tree-sitter only", rather than failing.
        var completionDelegate: LSPCompletionDelegate?
        var jumpToDefinitionDelegate: LSPJumpToDefinitionDelegate?
        var annotationCoordinator: LSPEditorAnnotationCoordinator?
        var semanticTokenProvider: SemanticTokenHighlightProvider?
        var treeSitterClient: TreeSitterClient?
        if let languageServices {
            completionDelegate = LSPCompletionDelegate(
                document: document,
                registry: languageServices.registry
            )
            annotationCoordinator = LSPEditorAnnotationCoordinator(
                document: document,
                registry: languageServices.registry,
                store: languageServices.diagnostics
            )
            semanticTokenProvider = SemanticTokenHighlightProvider(
                document: document,
                registry: languageServices.registry
            )
            // Built beside it, not instead of it: the semantic provider paints
            // only the identifier roles a lexer cannot know, and everything
            // else on screen is still tree-sitter's.
            treeSitterClient = TreeSitterClient()
            if let openFile {
                jumpToDefinitionDelegate = LSPJumpToDefinitionDelegate(
                    document: document,
                    registry: languageServices.registry,
                    openFile: openFile
                )
            }
        }

        slotsByURI[uri] = Slot(
            document: document,
            storage: storage,
            language: language,
            sourceEditorState: SourceEditorState(),
            changeObservation: changeObservation,
            completionDelegate: completionDelegate,
            jumpToDefinitionDelegate: jumpToDefinitionDelegate,
            annotationCoordinator: annotationCoordinator,
            semanticTokenProvider: semanticTokenProvider,
            treeSitterClient: treeSitterClient
        )
        openOrder.append(uri)
        touch(uri)
        evictOldestIfNeeded(keeping: uri)

        // Resolved now rather than on the first completion request: the request
        // path is only reached once the window is already open, so a trigger
        // set discovered there is discovered too late to have opened it.
        startTriggerCharacterResolution(for: uri)
    }

    /// Resolves one slot's completion trigger characters and publishes them,
    /// replacing whatever resolution was already in flight for that URI.
    ///
    /// Called when the slot opens and again on every change to the registry's
    /// session set, so it has to be cheap to repeat: the delegate returns an
    /// answer it has already read from the session still serving the document
    /// without going near the server, and an unchanged set is not republished.
    private func startTriggerCharacterResolution(for uri: DocumentUri) {
        guard let completionDelegate = slotsByURI[uri]?.completionDelegate else { return }
        triggerCharacterTasks[uri]?.cancel()
        triggerCharacterTasks[uri] = Task { [weak self] in
            let characters = await completionDelegate.resolveTriggerCharacters()
            guard let self, !Task.isCancelled, self.slotsByURI[uri] != nil else { return }
            // Compared before assigning: every publication re-runs the view's
            // body and re-diffs the configuration of every mounted editor, and
            // most session changes mean nothing for most open documents.
            guard (self.completionTriggerCharacters[uri] ?? []) != characters else { return }
            self.completionTriggerCharacters[uri] = characters
        }
    }

    /// Records `uri` as the most recently selected document.
    private func touch(_ uri: DocumentUri) {
        recencyOrder.removeAll { $0 == uri }
        recencyOrder.append(uri)
    }

    /// Drops least-recently-selected documents until the cache is back inside
    /// its bound. The document just selected is never the victim.
    private func evictOldestIfNeeded(keeping uri: DocumentUri) {
        while openOrder.count > Self.maximumCachedDocuments {
            guard let victim = recencyOrder.first(where: { $0 != uri }) else { return }
            recencyOrder.removeAll { $0 == victim }
            openOrder.removeAll { $0 == victim }
            slotsByURI.removeValue(forKey: victim)
            triggerCharacterTasks.removeValue(forKey: victim)?.cancel()
            completionTriggerCharacters.removeValue(forKey: victim)
            release(uri: victim)
        }
    }

    /// Gives up this pane's reference to `uri`, writing anything still pending
    /// for it first.
    ///
    /// Flush, never `cancel(uri:)`: the scheduler is app-wide and its cancel
    /// is not reference-counted, so cancelling would drop a save another pane
    /// is waiting on. The store's `close` *is* reference-counted, so a
    /// document another pane still holds stays open.
    private func release(uri: DocumentUri) {
        let scheduler = saveScheduler
        let store = documentStore
        Task { @MainActor in
            await scheduler.flushPendingSave(uri: uri)
            store.close(uri: uri)
        }
    }

    /// Writes out `uri`'s pending save without blocking the caller. Used only
    /// where nothing is being opened, so there is no ordering to preserve.
    private func flushInBackground(_ uri: DocumentUri?) {
        guard let uri else { return }
        let scheduler = saveScheduler
        Task { @MainActor in
            await scheduler.flushPendingSave(uri: uri)
        }
    }

    /// The selection has moved to a directory or to nothing. Hides the editor
    /// but keeps every cached slot exactly as it is — nothing is closed or
    /// rebuilt, so returning to a file later loses neither its edits nor its
    /// undo history.
    func unload() {
        loadTask?.cancel()
        let outgoing = currentURL?.documentUri
        currentURL = nil
        display = .empty
        flushInBackground(outgoing)
    }
}

extension FileEditorState: Loggable {
    public static nonisolated let logger = makeLogger()
}
