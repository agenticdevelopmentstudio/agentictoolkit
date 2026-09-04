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
    @StateObject private var editorState: EditorState

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
            wrappedValue: EditorState(documentStore: documentStore, saveScheduler: saveScheduler)
        )
    }

    /// Whether the selection is something the editor can open at all.
    private var openableNode: FileTreeNode? {
        guard let node = selectedNode, !node.isDirectory, !node.isPackage else { return nil }
        return node
    }

    public var body: some View {
        Group {
            if openableNode != nil {
                FileEditorContentView(editorState: editorState)
            } else {
                EditorPlaceholderView(message: "Select a file to view its contents")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { showSelection() }
        .onChange(of: selectedNode) { showSelection() }
    }

    /// Flushes whatever was pending on the outgoing file, then opens what is
    /// selected now. Both halves run for every selection change, including the
    /// ones that show no editor at all.
    private func showSelection() {
        editorState.flushOutgoingSave()
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
/// Every document this pane has ever shown keeps its own `SourceEditor`,
/// mounted for as long as this view exists (see `EditorState.Slot`) — never
/// torn down and rebuilt on a later revisit. That, not `SourceEditor`'s old
/// `.id(loadGeneration)`, is what makes undo survive switching between open
/// files: `SourceEditor.updateNSViewController` never re-applies a changed
/// `NSTextStorage` (only `makeNSViewController` does, once), and
/// `TextView.setTextStorage(_:)` unconditionally clears the undo stack every
/// time it runs — so any design that re-attaches storage to one long-lived
/// text view, `.id()`-forced or not, loses undo on every switch. Keeping one
/// editor per document and only ever toggling which is visible avoids ever
/// calling `setTextStorage` a second time for the same document.
private struct FileEditorContentView: View {
    /// Observed, not owned: the state outlives this view (see `FileEditorView`).
    @ObservedObject var editorState: EditorState

    @Environment(\.themePalette) private var appPalette

    public var body: some View {
        ZStack {
            switch editorState.display {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .text:
                // The active document's own `SourceEditor` is one of the
                // overlays below; nothing to draw at this layer.
                Color.clear

            case .quickLook(let url):
                QuickLookPreview(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .unavailable:
                EditorPlaceholderView(message: "Cannot open this file")
            }

            ForEach(editorState.openOrder, id: \.self) { uri in
                if let storage = editorState.storage(for: uri), let language = editorState.language(for: uri) {
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
                    .opacity(isActive(uri) ? 1 : 0)
                    .allowsHitTesting(isActive(uri))
                    .accessibilityHidden(!isActive(uri))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isActive(_ uri: DocumentUri) -> Bool {
        if case .text(let activeURI) = editorState.display { return activeURI == uri }
        return false
    }
}

// MARK: - Editor State

/// Observable state for the file viewer: what to show, the cache of every
/// document this pane has opened, and load/unload/save orchestration.
@MainActor
private final class EditorState: ObservableObject {

    /// What the viewer is showing for the current file.
    enum Display: Equatable {
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
    @Published private(set) var display: Display = .loading

    private var slotsByURI: [DocumentUri: Slot] = [:]

    /// Every URI this pane has ever opened, in first-opened order — what
    /// `FileEditorContentView` iterates to mount one `SourceEditor` per cached
    /// document. `@Published` so a newly-opened document's editor appears.
    @Published private(set) var openOrder: [DocumentUri] = []

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
    // nonisolated by default, and `documentStore.close`/`saveScheduler.cancel`
    // are MainActor-isolated. `isolated deinit` hops to the actor before
    // running, the same shape as `TextDocumentStoreObservation.deinit`.
    //
    // This pane closes every document it ever opened when it itself goes
    // away (the containing tab or window closes) — not on every file-to-file
    // switch, which is deliberately *not* paired 1:1 with `store.open` here;
    // see the class-level rationale in the Task 1.3 report for why closing on
    // every switch would defeat both undo-preservation and the dirty
    // indicator's ability to keep tracking a document the user switched away
    // from but has not saved yet.
    isolated deinit {
        loadTask?.cancel()
        for uri in openOrder {
            saveScheduler.cancel(uri: uri)
            documentStore.close(uri: uri)
        }
    }

    func storage(for uri: DocumentUri) -> TextDocumentStorage? {
        slotsByURI[uri]?.storage
    }

    func language(for uri: DocumentUri) -> CodeLanguage? {
        slotsByURI[uri]?.language
    }

    func sourceEditorStateBinding(for uri: DocumentUri) -> Binding<SourceEditorState> {
        Binding(
            get: { [weak self] in self?.slotsByURI[uri]?.sourceEditorState ?? SourceEditorState() },
            set: { [weak self] newValue in self?.slotsByURI[uri]?.sourceEditorState = newValue }
        )
    }

    /// Reads `url` off the main thread and shows it however it classifies. A
    /// URI already cached (this pane has shown it before) is shown immediately
    /// with no re-read of disk and no rebuild of its editor — both the "switch
    /// back and the edit is still there" and the undo-survival requirements
    /// depend on that document never being touched again after its first open.
    func load(from url: URL) {
        loadTask?.cancel()
        guard url != currentURL else { return }
        currentURL = url

        let uri = url.documentUri
        if slotsByURI[uri] != nil {
            display = .text(uri: uri)
            return
        }

        display = .loading

        loadTask = Task { [weak self] in
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
    /// URI for the life of this pane.
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
    }

    /// The selection has moved to a directory or to nothing. Hides the editor
    /// but keeps every cached slot exactly as it is — nothing is closed or
    /// rebuilt, so returning to a file later loses neither its edits nor its
    /// undo history.
    func unload() {
        loadTask?.cancel()
        currentURL = nil
        display = .loading
    }

    /// Flushes any pending debounced save before the selection moves on, so a
    /// switch inside the 1s debounce window never drops the last second of
    /// typing. At most one cached document can have a save pending at any
    /// moment — this runs before every switch, and nothing else in this pane
    /// schedules a save — so flushing the whole scheduler here is equivalent
    /// to a per-URI flush without `TextDocumentSaveScheduler` needing one.
    func flushOutgoingSave() {
        let scheduler = saveScheduler
        Task { await scheduler.flushPendingSaves() }
    }
}

extension EditorState: Loggable {
    public static nonisolated let logger = makeLogger()
}
