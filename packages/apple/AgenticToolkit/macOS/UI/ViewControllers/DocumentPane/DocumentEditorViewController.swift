import AppKit
import Combine
import SwiftUI

import AgenticDeveloperToolkitUI
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitLanguage

/// One editor inside one pane of one tab.
///
/// Holds its own selection rather than sharing the browser's: two editors side
/// by side show two different files, so "what is selected" cannot be one value
/// for the window. The tree's selection drives *which editor gets told*, not
/// what every editor shows.
@MainActor
public final class DocumentEditorViewController: NSViewController {

    /// Stored under the pane's own prefix, beside `EditorOptionsOverride`.
    public static let fileURLKey = "fileURL"

    public let options: EditorOptionsOverride

    private let store: PaneStateStore
    private let selection = FileBrowserSelection()
    private let documentStore: TextDocumentStore
    private let saveScheduler: TextDocumentSaveScheduler
    private let languageServices: ProjectLanguageServices?

    /// The project root the breadcrumb reads its crumbs relative to.
    private let rootURL: URL
    private let breadcrumb: BreadcrumbView

    /// Fires when the displayed file changes, so the tab bar can retitle.
    public var onTitleChange: (() -> Void)?

    /// The rows the options popover is showing, if one is open.
    ///
    /// Weak, and deliberately not an array: the options dialog owns its views and
    /// takes them with it when it closes, so these go nil on their own rather
    /// than keeping a dismissed dialog's checkboxes alive to be written to.
    private weak var lineNumbersRow: WindowOptionsToggle?
    private weak var overviewRow: WindowOptionsToggle?
    private weak var invisiblesRow: WindowOptionsToggle?
    private weak var resetRow: NSButton?

    /// Watches both scopes at once. `EditorOptionsOverride.publish()` fires for
    /// a pane-local edit, for `reset()`, and for a change to the app-wide
    /// setting — and it mutates its stored value *before* sending, so reading
    /// the resolved values from here gives the new ones.
    private var optionsObserver: AnyCancellable?

    /// Asked to show a file the editor itself resolved — a go-to-definition
    /// target in another file, or a file chosen from the breadcrumb's
    /// popover. Routed out rather than handled here, because the browser's
    /// selection is the one place that decides what is open.
    public var onOpenRequest: ((URL) -> Void)?

    public var fileURL: URL? {
        get { selection.selectedNode?.url }
        set { show(newValue, persist: true) }
    }

    public init(
        store: PaneStateStore,
        documentStore: TextDocumentStore,
        saveScheduler: TextDocumentSaveScheduler,
        languageServices: ProjectLanguageServices?,
        rootURL: URL
    ) {
        self.store = store
        self.options = EditorOptionsOverride(store: store)
        self.documentStore = documentStore
        self.saveScheduler = saveScheduler
        self.languageServices = languageServices
        self.rootURL = rootURL
        self.breadcrumb = BreadcrumbView(rootURL: rootURL)
        super.init(nibName: nil, bundle: nil)
        breadcrumb.onSelect = { [weak self] url in self?.onOpenRequest?(url) }
        optionsObserver = options.objectWillChange.sink { [weak self] _ in
            self?.refreshOptionRows()
        }
        restoreStoredDocument()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A stored path whose file has since gone restores as an empty editor:
    /// the pane and its tab survive, the document does not.
    private func restoreStoredDocument() {
        guard let path = store.paneStateValue(forKey: Self.fileURLKey) else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.setPaneStateValue(nil, forKey: Self.fileURLKey)
            return
        }
        show(url, persist: false)
    }

    private func show(_ url: URL?, persist: Bool) {
        // Asked rather than asserted. Every caller here hands over a bare URL —
        // a restored path, a breadcrumb choice, a go-to-definition target, the
        // tree's own open request — and a directory is among the things they can
        // legitimately name: a package is a directory the tree shows as one
        // item, and so is a folder chosen from a breadcrumb's popover. Told it
        // was a file, `FileEditorView.openableNode` let it through and the
        // editor read a directory off disk.
        selection.selectedNode = url.map {
            FileTreeNode(url: $0, isDirectory: Self.isDirectory($0))
        }
        breadcrumb.fileURL = url
        if persist {
            store.setPaneStateValue(url?.path, forKey: Self.fileURLKey)
        }
        onTitleChange?()
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// Empties the editor without taking the pane with it — what the close box
    /// does on the last pane of the last tab.
    public func clearDocument() {
        show(nil, persist: true)
    }

    public override func loadView() {
        let hosting = NSHostingView(
            rootView: DocumentEditorPaneView(
                selection: selection,
                options: options,
                documentStore: documentStore,
                saveScheduler: saveScheduler,
                languageServices: languageServices,
                openFile: { [weak self] url in self?.onOpenRequest?(url) }
            ).themedRoot()
        )

        let stack = NSStackView(views: [breadcrumb, hosting])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        breadcrumb.translatesAutoresizingMaskIntoConstraints = false
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            breadcrumb.heightAnchor.constraint(equalToConstant: 24),
            breadcrumb.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            breadcrumb.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            hosting.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 424))
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
    }
}

// MARK: - Pane capabilities

extension DocumentEditorViewController: PaneTitleProviding {

    public var paneTitle: String { fileURL?.lastPathComponent ?? "Untitled" }

    public var onPaneTitleChange: (() -> Void)? {
        get { onTitleChange }
        set { onTitleChange = newValue }
    }
}

extension DocumentEditorViewController: PaneOptionsProviding {

    public func makePaneOptionRows() -> [NSView] {
        let lineNumbers = WindowOptionsToggle(
            title: "Show line numbers",
            isOn: options.showLineNumbers,
            onChange: { [weak self] value in self?.options.setShowLineNumbers(value) }
        ).checkboxAccessibilityID("document.options.line-numbers")
        let overview = WindowOptionsToggle(
            title: "Show overview",
            isOn: options.showOverview,
            onChange: { [weak self] value in self?.options.setShowOverview(value) }
        ).checkboxAccessibilityID("document.options.overview")
        let invisibles = WindowOptionsToggle(
            title: "Show invisibles",
            isOn: options.showInvisibles,
            onChange: { [weak self] value in self?.options.setShowInvisibles(value) }
        ).checkboxAccessibilityID("document.options.invisibles")

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetOptions))
        reset.bezelStyle = .rounded
        reset.isEnabled = options.isOverridden
        reset.accessibilityID("document.options.reset")
        reset.setAccessibilityLabel("Reset Editor Options to Defaults")

        lineNumbersRow = lineNumbers
        overviewRow = overview
        invisiblesRow = invisibles
        resetRow = reset

        return [lineNumbers, overview, invisibles, reset]
    }

    /// Puts the resolved values back into an open dialog's rows.
    ///
    /// Without this the dialog was a photograph: `Reset to Defaults` cleared
    /// the override, the three checkboxes went on showing the values it had
    /// cleared, and its own button stayed enabled — so the pane and the dialog
    /// disagreed until it was closed and reopened. The app-wide setting moving
    /// while the dialog is open is the same problem arriving from the other side.
    private func refreshOptionRows() {
        lineNumbersRow?.isOn = options.showLineNumbers
        overviewRow?.isOn = options.showOverview
        invisiblesRow?.isOn = options.showInvisibles
        resetRow?.isEnabled = options.isOverridden
    }

    @objc private func resetOptions() {
        options.reset()
    }
}

private struct DocumentEditorPaneView: View {

    @ObservedObject var selection: FileBrowserSelection
    @ObservedObject var options: EditorOptionsOverride
    let documentStore: TextDocumentStore
    let saveScheduler: TextDocumentSaveScheduler
    let languageServices: ProjectLanguageServices?
    let openFile: @MainActor (URL) -> Void

    var body: some View {
        FileEditorView(
            selectedNode: selection.selectedNode,
            documentStore: documentStore,
            saveScheduler: saveScheduler,
            languageServices: languageServices,
            options: options,
            openFile: openFile
        )
    }
}
