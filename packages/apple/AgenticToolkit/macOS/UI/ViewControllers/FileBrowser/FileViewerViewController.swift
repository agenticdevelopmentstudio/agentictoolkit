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

    public init(
        selection: FileBrowserSelection,
        documentStore: TextDocumentStore,
        saveScheduler: TextDocumentSaveScheduler
    ) {
        self.selection = selection
        self.documentStore = documentStore
        self.saveScheduler = saveScheduler
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
                saveScheduler: saveScheduler
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

    var body: some View {
        FileEditorView(
            selectedNode: selection.selectedNode,
            documentStore: documentStore,
            saveScheduler: saveScheduler
        )
    }
}
