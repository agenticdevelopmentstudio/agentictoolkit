import AppKit
import SwiftUI

import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitLanguage

/// AppKit host for the file *display* half of the browser: whatever the tree has
/// selected, shown with syntax highlighting.
///
/// Split out from `FileBrowserSplitViewController` so a host that already has
/// its own tree — a sidebar, a search result list — can show files by driving a
/// `FileBrowserSelection` and nothing else (`srp`).
@MainActor
public final class FileViewerViewController: NSViewController {

    /// The selection this viewer follows.
    public let selection: FileBrowserSelection

    /// The app-wide open-document registry and debounced autosave scheduler —
    /// shared, never built here (see `FileEditorView.init`).
    private let documentStore: TextDocumentStore
    private let saveScheduler: TextDocumentSaveScheduler

    /// This project's language servers, or `nil` for a viewer with none — a
    /// test, or a file browser that is not a project window. Optional in type,
    /// required in position: a default value would let a new call site lose
    /// completion without ever saying so.
    private let languageServices: ProjectLanguageServices?

    public init(
        selection: FileBrowserSelection,
        documentStore: TextDocumentStore,
        saveScheduler: TextDocumentSaveScheduler,
        languageServices: ProjectLanguageServices?
    ) {
        self.selection = selection
        self.documentStore = documentStore
        self.saveScheduler = saveScheduler
        self.languageServices = languageServices
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let hosting = NSHostingView(
            rootView: FileViewerPaneView(
                selection: selection,
                documentStore: documentStore,
                saveScheduler: saveScheduler,
                languageServices: languageServices
            ).themedRoot()
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        view = hosting
    }
}

/// Re-renders the editor whenever the shared selection changes.
private struct FileViewerPaneView: View {

    @ObservedObject var selection: FileBrowserSelection
    let documentStore: TextDocumentStore
    let saveScheduler: TextDocumentSaveScheduler
    let languageServices: ProjectLanguageServices?

    var body: some View {
        FileEditorView(
            selectedNode: selection.selectedNode,
            documentStore: documentStore,
            saveScheduler: saveScheduler,
            languageServices: languageServices,
            openFile: openFile
        )
    }

    /// How a cross-file go-to-definition target gets shown.
    ///
    /// It originates here because this is the one view that holds both the
    /// selection and the editor; everything below it — `FileEditorView`,
    /// `FileEditorState`, `LSPJumpToDefinitionDelegate` — takes it as an
    /// injected closure and knows nothing about a file browser.
    ///
    /// `selection` is captured, never `self`: this is a `struct` re-created on
    /// every render, and the closure outlives the value it was made in.
    ///
    /// **Deliberate limitation:** the file is opened, but the target *range*
    /// inside it is not selected. Doing that needs a way to hand a pending
    /// cursor position to an editor that does not exist yet, so it is out of
    /// scope for Task 3.3 rather than forgotten.
    private var openFile: @MainActor (URL) -> Void {
        let selection = self.selection
        return { url in
            selection.selectedNode = FileTreeNode(url: url, isDirectory: false)
        }
    }
}
