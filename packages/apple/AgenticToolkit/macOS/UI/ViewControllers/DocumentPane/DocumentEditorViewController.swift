import AppKit
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
        selection.selectedNode = url.map { FileTreeNode(url: $0, isDirectory: false) }
        breadcrumb.fileURL = url
        if persist {
            store.setPaneStateValue(url?.path, forKey: Self.fileURLKey)
        }
        onTitleChange?()
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
        let lineNumbers = WindowConfigToggle(
            title: "Show line numbers",
            isOn: options.showLineNumbers,
            onChange: { [weak self] value in self?.options.setShowLineNumbers(value) }
        )
        let overview = WindowConfigToggle(
            title: "Show overview",
            isOn: options.showOverview,
            onChange: { [weak self] value in self?.options.setShowOverview(value) }
        )
        let invisibles = WindowConfigToggle(
            title: "Show invisibles",
            isOn: options.showInvisibles,
            onChange: { [weak self] value in self?.options.setShowInvisibles(value) }
        )

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetOptions))
        reset.bezelStyle = .rounded
        reset.isEnabled = options.isOverridden
        reset.accessibilityID("document.options.reset")
        reset.setAccessibilityLabel("Reset Editor Options to Defaults")

        return [lineNumbers, overview, invisibles, reset]
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
