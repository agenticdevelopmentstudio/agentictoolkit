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
    ///   - languageServices: This project's language servers, or `nil` for a
    ///     browser that has none. No default value: a default would let a new
    ///     call site lose completion and go-to-definition without saying so.
    ///   - openFile: How to show a cross-file go-to-definition target. Supplied
    ///     from above rather than decided here — this view has no selection to
    ///     drive.
    public init(
        selectedNode: FileTreeNode?,
        documentStore: TextDocumentStore,
        saveScheduler: TextDocumentSaveScheduler,
        languageServices: ProjectLanguageServices?,
        openFile: (@MainActor (URL) -> Void)?
    ) {
        self.selectedNode = selectedNode
        self._editorState = StateObject(
            wrappedValue: FileEditorState(
                documentStore: documentStore,
                saveScheduler: saveScheduler,
                languageServices: languageServices,
                openFile: openFile
            )
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
                // Built by `FileEditorState`, not inline here, so the whole
                // configuration — the trigger characters included — is
                // reachable from a test. Everything this view contributes is
                // the palette.
                configuration: editorState.editorConfiguration(for: uri, palette: appPalette),
                state: editorState.sourceEditorStateBinding(for: uri),
                // `SourceEditor` holds both of these `weak`; `FileEditorState.Slot`
                // is what keeps them alive for the life of the cached editor.
                // `coordinators:` and `highlightProviders:` are deliberately left
                // at their defaults — they belong to later tasks, and passing
                // `[]`/`nil` explicitly here would change nothing.
                completionDelegate: editorState.completionDelegate(for: uri),
                jumpToDefinitionDelegate: editorState.jumpToDefinitionDelegate(for: uri)
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

        let visibleHost = activeURI.flatMap { hostsByURI[$0] }
        for host in hostsByURI.values {
            host.isHidden = host !== visibleHost
        }

        // The container hides itself when it is showing nothing.
        //
        // It is mounted unconditionally and pinned to the whole pane, and a
        // plain `NSView` returns *itself* from `hitTest(_:)` for any point
        // inside its bounds that no subview claims — AppKit exempts neither
        // transparency nor emptiness. Hiding only the hosts therefore left a
        // dead, invisible sheet on top of whatever else the pane draws: a
        // QuickLook preview underneath rendered fine but could not be
        // scrolled, and a movie's transport controls did not respond, because
        // the empty container took every click and scroll. `isHidden` on the
        // container is the same documented exclusion the hosts rely on, and
        // unlike a `hitTest` override it keeps the view honest about its own
        // visibility — nothing else has to infer "showing nothing" from the
        // absence of a claim.
        isHidden = visibleHost == nil

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

    /// Puts the caret in the editor that just became visible — and takes it
    /// out of the one that just stopped being visible.
    ///
    /// Focus is only *taken* when it already belonged to this stack (or to
    /// nothing). Before one-editor-per-document there was a single editor that
    /// simply kept first responder across a switch; restoring that is the
    /// point. Taking focus *unconditionally* would be a worse regression than
    /// the one being fixed: the file tree changes the selection on every arrow
    /// key, so grabbing first responder on selection change would make the
    /// tree impossible to walk with the keyboard after the first press.
    ///
    /// Focus is always *given up* when nothing is shown. AppKit does not
    /// resign a first responder merely because an ancestor became hidden, so
    /// without this a selection cleared while the caret was in the editor —
    /// programmatically, since clicking or arrowing the tree takes first
    /// responder first — left keystrokes going into a text view the user
    /// cannot see, and the autosave writing them to a file that is not on
    /// screen. That is the failure finding 3 was about, on the unload path.
    private func moveFocusToShownEditor() {
        guard let window else { return }
        let focusIsOurs = (window.firstResponder as? NSView)?.isDescendant(of: self) ?? false

        guard let shownURI, let host = hostsByURI[shownURI] else {
            if focusIsOurs { window.makeFirstResponder(nil) }
            return
        }

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
