import AgenticToolkitCore
import AgenticToolkitLanguage
import SwiftUI
import AppKit
import Combine
import CodeEditSourceEditor
import CodeEditLanguages
import LanguageServerProtocol
import os

/// Shows whatever the file tree has selected.
///
/// Text files open in an editable, syntax-highlighted source editor; edits are
/// persisted through a `TextDocumentStore`-backed `TextDocument` and debounced
/// autosave, not the ad hoc save-on-selection-change this used to be. Everything
/// else — images, PDFs, movies — goes to QuickLook, so clicking a file shows the
/// file rather than an apology (`principle-of-least-astonishment`).
///
/// Colors and font come from the app theme in the environment, so the editor
/// follows a theme switch like the rest of the UI and there is no second
/// palette to keep in step (see `SemanticPalette.editorTheme`).
public struct FileEditorView: View {
    /// The currently selected file tree node, or `nil` if nothing is selected.
    public let selectedNode: FileTreeNode?

    /// Owned here rather than inside the content view. Selecting a directory
    /// or nothing switches which branch of `body` exists, and SwiftUI destroys
    /// the branch it leaves — taking a `@StateObject` living in it, and with it
    /// any unsaved edits, before anything had a chance to write them
    /// (`explicit-over-implicit` about who owns the open file).
    @StateObject private var editorState: FileEditorState

    /// - Parameters:
    ///   - documentStore: The app-wide open-document registry. Injected, never
    ///     constructed here — a `TextDocumentStore`'s refcounted `open`/`close`
    ///     only means anything with exactly one shared instance across the app
    ///     (see `TextDocumentCoordinator`, which every host constructs once).
    ///   - saveScheduler: The app-wide debounced autosave scheduler, likewise
    ///     shared rather than built per view.
    public init(
        selectedNode: FileTreeNode?,
        documentStore: TextDocumentStore,
        saveScheduler: TextDocumentSaveScheduler
    ) {
        self.selectedNode = selectedNode
        self._editorState = StateObject(
            wrappedValue: FileEditorState(documentStore: documentStore, saveScheduler: saveScheduler)
        )
    }

    /// Whether the selection is something the editor can open at all.
    private var openableNode: FileTreeNode? {
        guard let node = selectedNode, !node.isDirectory, !node.isPackage else { return nil }
        return node
    }

    /// One view, always the same one — deliberately *not* a `Group` with an
    /// `if`/`else`.
    ///
    /// A conditional here is `_ConditionalContent`: selecting a directory
    /// switches branches, and SwiftUI destroys the branch it leaves. That took
    /// down every cached `SourceEditor` at once, and remounting them ran
    /// `makeNSViewController` → `TextView.setTextStorage(_:)` →
    /// `_undoManager?.clearStack()` for every file the pane had ever opened.
    /// Clicking a folder therefore erased the undo history this whole design
    /// exists to preserve. The placeholder is now just another state of
    /// `FileEditorState.display`, drawn inside the one always-mounted content
    /// view.
    public var body: some View {
        FileEditorContentView(editorState: editorState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { showSelection() }
            .onChange(of: selectedNode) { showSelection() }
    }

    /// Opens what is selected now, or clears the editor if the selection is a
    /// directory or nothing. Flushing the outgoing file's pending save is
    /// `FileEditorState`'s job, because only it knows which URI is outgoing.
    private func showSelection() {
        if let node = openableNode {
            editorState.load(from: node.url)
        } else {
            editorState.unload()
        }
    }
}

// MARK: - Placeholder

/// Shown when no file is selected or when a directory is selected.
private struct EditorPlaceholderView: View {
    public let message: String

    @Environment(\.theme) private var theme

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(theme.tertiaryText)

            Text(message)
                .font(theme.font(.heading))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Editor Content

/// Loads the file and shows it the way `FilePreviewLoader` classified it.
///
/// Every document this pane has recently shown keeps its own `SourceEditor`,
/// mounted for as long as this view exists (see `FileEditorState.Slot`) —
/// never torn down and rebuilt on a later revisit. That, not `SourceEditor`'s
/// old `.id(loadGeneration)`, is what makes undo survive switching between
/// open files: `SourceEditor.updateNSViewController` never re-applies a
/// changed `NSTextStorage` (only `makeNSViewController` does, once), and
/// `TextView.setTextStorage(_:)` unconditionally clears the undo stack every
/// time it runs — so any design that re-attaches storage to one long-lived
/// text view, `.id()`-forced or not, loses undo on every switch. Keeping one
/// editor per document and only ever toggling which is visible avoids ever
/// calling `setTextStorage` a second time for the same document.
///
/// The editors live in `CachedEditorStackView`, an AppKit container, rather
/// than in a SwiftUI `ZStack`/`ForEach`. Showing one of several stacked
/// editors means hiding the rest *from AppKit*, not merely from the eye:
/// `alphaValue == 0` suppresses neither `NSView.hitTest(_:)` nor
/// `TextView.canBecomeKeyView`, so faded-out editors still took clicks and
/// still answered Tab. `isHidden` removes a view from both by documented
/// behaviour, and owning the container is what lets this set it.
private struct FileEditorContentView: View {
    /// Observed, not owned: the state outlives this view (see `FileEditorView`).
    @ObservedObject var editorState: FileEditorState

    @Environment(\.themePalette) private var appPalette

    public var body: some View {
        ZStack {
            switch editorState.display {
            case .empty:
                EditorPlaceholderView(message: "Select a file to view its contents")

            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .text:
                // The active document's own `SourceEditor` is in the stack
                // below; nothing to draw at this layer.
                Color.clear

            case .quickLook(let url):
                QuickLookPreview(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .unavailable:
                EditorPlaceholderView(message: "Cannot open this file")
            }

            CachedEditorStack(
                uris: editorState.openOrder,
                activeURI: editorState.activeURI,
                makeEditor: makeEditor
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Builds the SwiftUI editor for one cached document. Called again on every
    /// update so a theme switch reaches an already-mounted editor: assigning a
    /// new `rootView` to an existing `NSHostingView` re-runs SwiftUI's update
    /// path (`updateNSViewController`), it does not remount the controller.
    private func makeEditor(_ uri: DocumentUri) -> AnyView {
        guard let storage = editorState.storage(for: uri),
              let language = editorState.language(for: uri) else {
            return AnyView(Color.clear)
        }
        return AnyView(
            SourceEditor(
                storage,
                language: language,
                configuration: SourceEditorConfiguration(
                    appearance: .init(
                        // Both derived from the one palette in the
                        // environment, so a theme switch repaints the
                        // editor's chrome, syntax and font together.
                        theme: appPalette.editorTheme,
                        font: appPalette.font(.code),
                        wrapLines: false
                    ),
                    peripherals: .init(
                        showGutter: true,
                        showMinimap: true
                    )
                ),
                state: editorState.sourceEditorStateBinding(for: uri)
            )
            .environment(\.themePalette, appPalette)
        )
    }
}

// MARK: - Cached editor stack

/// Mounts one `SourceEditor` per cached document in an AppKit container and
/// shows exactly one of them.
private struct CachedEditorStack: NSViewRepresentable {
    /// Every cached document, in mount order. Stable: a document keeps its
    /// place until it is evicted, so nothing here ever reorders an already
    /// mounted editor.
    let uris: [DocumentUri]

    /// The one document to show, or `nil` while a directory, a QuickLook file
    /// or nothing is selected.
    let activeURI: DocumentUri?

    let makeEditor: (DocumentUri) -> AnyView

    func makeNSView(context: Context) -> CachedEditorStackView {
        CachedEditorStackView()
    }

    func updateNSView(_ nsView: CachedEditorStackView, context: Context) {
        nsView.sync(uris: uris, activeURI: activeURI, makeEditor: makeEditor)
    }
}

/// The AppKit half of `CachedEditorStack`: a plain container holding one
/// `NSHostingView` per cached document, all pinned to its bounds, with every
/// inactive one `isHidden`.
///
/// `isHidden` rather than `alphaValue`/`opacity` is the whole point of this
/// type existing. AppKit has no alpha threshold in `hitTest(_:)`, so a
/// fully-transparent editor still swallowed clicks meant for the visible one,
/// and `TextView.canBecomeKeyView` tests `!isHiddenOrHasHiddenAncestor`, so a
/// transparent editor still answered Tab — putting the caret in a document
/// the user could not see and then autosaving their keystrokes into it. A
/// hidden view is excluded from both, by documented behaviour, rather than by
/// hoping SwiftUI's `allowsHitTesting` propagates into a representable's
/// AppKit subtree.
@MainActor
final class CachedEditorStackView: NSView {

    /// One host per cached document. The identity that must survive: as long
    /// as a URI's entry is in here, its `SourceEditor` — and therefore its
    /// `TextViewController`, its `NSTextStorage` and its undo stack — is
    /// never rebuilt.
    private var hostsByURI: [DocumentUri: NSHostingView<AnyView>] = [:]

    /// What `sync` was last told to show, so focus moves only when the shown
    /// document actually changes rather than on every SwiftUI update.
    private var shownURI: DocumentUri?

    /// Test seam: the host mounted for `uri`, or `nil`. Identity is the thing
    /// worth asserting — that this returns the *same object* across a
    /// selection round trip is what "the editor is not rebuilt" means.
    func host(for uri: DocumentUri) -> NSView? {
        hostsByURI[uri]
    }

    var mountedURIs: Set<DocumentUri> {
        Set(hostsByURI.keys)
    }

    func sync(uris: [DocumentUri], activeURI: DocumentUri?, makeEditor: (DocumentUri) -> AnyView) {
        let wanted = Set(uris)

        // Evicted documents lose their editor here — the only place a mounted
        // editor is ever torn down.
        for (uri, host) in hostsByURI where !wanted.contains(uri) {
            host.removeFromSuperview()
            hostsByURI.removeValue(forKey: uri)
        }

        for uri in uris {
            if let existing = hostsByURI[uri] {
                existing.rootView = makeEditor(uri)
            } else {
                mount(uri: uri, view: makeEditor(uri))
            }
        }

        for (uri, host) in hostsByURI {
            host.isHidden = uri != activeURI
        }

        guard shownURI != activeURI else { return }
        shownURI = activeURI
        moveFocusToShownEditor()
    }

    private func mount(uri: DocumentUri, view: AnyView) {
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hostsByURI[uri] = host
    }

    /// Puts the caret in the editor that just became visible.
    ///
    /// Only when focus already belonged to this stack (or to nothing). Before
    /// one-editor-per-document there was a single editor that simply kept
    /// first responder across a switch; restoring that is the point. Taking
    /// focus *unconditionally* would be a worse regression than the one being
    /// fixed: the file tree changes the selection on every arrow key, so
    /// grabbing first responder on selection change would make the tree
    /// impossible to walk with the keyboard after the first press.
    private func moveFocusToShownEditor() {
        guard let shownURI, let host = hostsByURI[shownURI], let window = host.window else { return }
        if let current = window.firstResponder as? NSView, !current.isDescendant(of: self) { return }
        guard let target = Self.firstKeyViewCandidate(in: host) else { return }
        window.makeFirstResponder(target)
    }

    /// The first descendant that will actually accept first responder — the
    /// editor's text view. Found by asking `NSView`'s own public API rather
    /// than by naming `CodeEditTextView.TextView`, which this module does not
    /// import: the scroll view, clip view, gutter and minimap all answer
    /// `false`, so the first `true` is the text view.
    private static func firstKeyViewCandidate(in view: NSView) -> NSView? {
        for subview in view.subviews {
            if subview.acceptsFirstResponder, subview.canBecomeKeyView {
                return subview
            }
            if let found = firstKeyViewCandidate(in: subview) {
                return found
            }
        }
        return nil
    }
}

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
    }

    private let documentStore: TextDocumentStore
    private let saveScheduler: TextDocumentSaveScheduler

    /// How the current file is being shown.
    @Published private(set) var display: Display = .empty

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

    init(documentStore: TextDocumentStore, saveScheduler: TextDocumentSaveScheduler) {
        self.documentStore = documentStore
        self.saveScheduler = saveScheduler
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

        slotsByURI[uri] = Slot(
            document: document,
            storage: storage,
            language: language,
            sourceEditorState: SourceEditorState(),
            changeObservation: changeObservation
        )
        openOrder.append(uri)
        touch(uri)
        evictOldestIfNeeded(keeping: uri)
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
