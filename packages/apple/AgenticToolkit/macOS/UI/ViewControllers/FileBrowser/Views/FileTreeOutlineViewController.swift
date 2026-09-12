import AppKit
import Combine

import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitLanguage
import LanguageServerProtocol

/// The file tree: one collapsible section per root directory, and the files and
/// folders under it.
///
/// An `NSOutlineView` rather than a SwiftUI `List`. A list row on macOS keeps
/// its click handling to itself — a tap gesture attached to the row's content
/// never fires, and a directory's row, being a disclosure-group label, is not
/// something the list will select at all. Half the tree therefore answered a
/// click with nothing, which is the one thing a file browser must never do.
/// AppKit's outline selects on mouse-down for every row it draws, which is the
/// behaviour this needs and the platform already has (`native-controls`).
@MainActor
final class FileTreeOutlineViewController: NSViewController {

    /// The roots to draw, in display order.
    private let roots: FileBrowserRootsModel

    /// Which root the enclosing pane's `+`/`−` act on. Clicking anything in a
    /// tree — a header or a file — says which root the user means.
    private let directories: FileBrowserDirectories

    /// What the user has clicked.
    private let selection: FileBrowserSelection

    /// The folders that should be open and the file that should be selected —
    /// what the browser looked like last time.
    private let restoration: FileBrowserRestorationState

    /// The app-wide open-document registry — consulted for the dirty
    /// indicator on a node whose file has unsaved changes open in the editor.
    private let documentStore: TextDocumentStore

    /// Where a file the user picked should be shown. Plain selection cannot
    /// carry this — it says *what*, never *where* — so the three verbs travel
    /// as their own request: a plain click or "Open" sends `.current`, and the
    /// other two context-menu items send the destination they name.
    var onOpenRequest: ((URL, DocumentDestination) -> Void)?

    /// Keeps the `documentStore` subscription below alive; dropped in `deinit`.
    private var documentStoreObservation: TextDocumentStoreObservation?

    private let outline = ThemedOutlineView(role: .windowBackground)
    private let scrollView = ThemedScrollView()

    /// One placeholder row per empty root, kept rather than rebuilt so the
    /// outline sees the same object each time it asks (it identifies items by
    /// pointer, and a fresh one every call would collapse the row on reload).
    private var placeholders: [URL: Placeholder] = [:]

    /// A directory's `$children` subscription, with the object it was made for.
    ///
    /// The node is held weakly and compared by identity: a node id is a path,
    /// and the same path can come back as a *different* object — `merge` only
    /// re-uses the ones whose id survived, and `loadChildrenIfNeeded` replaces
    /// the list outright. A watcher left pointing at the old object never fires
    /// for the row the outline is actually drawing.
    private struct ChildWatcher {
        weak var node: FileTreeNode?
        let subscription: AnyCancellable
    }

    /// One subscription per expanded directory, so the row redraws when its
    /// contents land. Dropped on collapse, which is what keeps this from
    /// accumulating every directory ever opened.
    private var childWatchers: [String: ChildWatcher] = [:]

    private var cancellables = Set<AnyCancellable>()

    /// Set while the outline is being told about a selection that came *from*
    /// the model, so the resulting delegate callback does not write it back.
    private var isSyncingSelection = false

    /// The same guard for disclosure: an expansion this controller performs to
    /// restore what was stored must not be reported back as the user opening a
    /// folder.
    private var isSyncingExpansion = false

    /// The file still waiting to be selected, if the row it lives on has not
    /// been drawn yet. Cleared the moment it is found — a restore happens once,
    /// and after that the selection is the user's.
    private var pendingSelectionPath: String?

    /// One-shot, so the "a lone root opens showing its contents" default cannot
    /// re-open a root the user has deliberately collapsed.
    private var hasAppliedDefaultExpansion = false

    /// Path -> row index for the rows currently drawn, built lazily and
    /// dropped whenever rows can have moved (a reload, an expand, a collapse).
    ///
    /// `row(forPath:)` used to walk every row and compare a path string on
    /// each call, and this controller is a `TextDocumentStore` observer — so
    /// *every keystroke in any window* cost an O(rows) scan in *every* open
    /// file browser, whether or not the edited file was one of its own. The
    /// tree does not change while the user types, so the first lookup after a
    /// structural change pays for the scan and the rest are dictionary hits.
    private var rowIndexByPath: [String: Int]?

    init(
        roots: FileBrowserRootsModel,
        directories: FileBrowserDirectories,
        selection: FileBrowserSelection,
        restoration: FileBrowserRestorationState,
        documentStore: TextDocumentStore
    ) {
        self.roots = roots
        self.directories = directories
        self.selection = selection
        self.restoration = restoration
        self.documentStore = documentStore
        self.pendingSelectionPath = restoration.selectedPath
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - View

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 14
        outline.style = .inset
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(rowDoubleClicked(_:))
        outline.autoresizesOutlineColumn = false
        outline.accessibilityID("file-browser.tree")

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outline.menu = contextMenu

        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        roots.$managers
            .receive(on: RunLoop.main)
            .sink { [weak self] managers in self?.observe(managers) }
            .store(in: &cancellables)

        // A root's header says which one the footer will act on, so it redraws
        // when that changes — including when a click on a *file* moved it.
        //
        // `removeDuplicates` is load-bearing, not an optimisation. Clicking a
        // file assigns the root it already lives under, and `@Published`
        // republishes an unchanged value, so without this every click in the
        // tree rebuilt the tree it had just been made in.
        selection.$selectedRoot
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadPreservingSelection() }
            .store(in: &cancellables)

        // Every change of selection lands here — the user's clicks, a reload
        // that lost the row, a host restoring one — so this is the single place
        // that records it (`dry`).
        selection.$selectedNode
            .receive(on: RunLoop.main)
            .sink { [weak self] node in
                guard let self else { return }
                self.showSelection(node)
                // While a restore is still outstanding the tree is not yet
                // showing what was stored, and its empty selection is not news.
                if self.pendingSelectionPath == nil {
                    self.restoration.setSelectedPath(node?.url.path)
                }
            }
            .store(in: &cancellables)

        // A document opening, changing dirty state, or closing redraws only
        // the one row it affects — never `reloadData()`, which would collapse
        // every disclosed folder and drop the current selection just because
        // the user kept typing.
        documentStoreObservation = documentStore.addObserver { [weak self] event in
            self?.handleDocumentEvent(event)
        }
    }

    /// Repaints the dirty marker on the row for `uri`'s file, if the tree
    /// currently has one drawn — a document event for a file that is not on
    /// screen (a collapsed folder, a root removed since) has nothing to
    /// redraw.
    ///
    /// A `.changed` event arrives on every keystroke, in every open file
    /// browser, for documents that may belong to another window's pane
    /// entirely — so this has to be cheap and it has to be harmless. The
    /// lookup is a dictionary hit (see `rowIndexByPath`), and the repaint
    /// mutates the already-built row view in place instead of reloading the
    /// row: `reloadItem(_:)` on a view-based outline updates the existing
    /// view's `objectValue` and is not documented to rebuild the view, and
    /// `FileTreeNodeRowView` reads nothing from `objectValue` — so a reload
    /// would very likely have shown nothing at all, while still costing the
    /// selection drop that every other reload in this file guards against.
    private func handleDocumentEvent(_ event: TextDocumentEvent) {
        let uri: DocumentUri
        switch event {
        case .opened(let eventURI, _, _, _): uri = eventURI
        case .changed(let eventURI, _, _): uri = eventURI
        case .dirtyStateChanged(let eventURI, _): uri = eventURI
        case .closed(let eventURI): uri = eventURI
        }
        guard let url = URL(string: uri) else { return }
        let row = self.row(forPath: url.path)
        guard row >= 0 else { return }

        let isDirty = documentStore.document(for: uri)?.isDirty ?? false
        if let rowView = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileTreeNodeRowView {
            rowView.setDirty(isDirty)
            return
        }

        // The row is drawn but its view has been recycled away — rare, and a
        // reload is then the only way back. Guarded the way every other reload
        // in this file is: reloading rows drops the outline's selection, and
        // an unguarded drop reads as the user deselecting the file they are
        // reading, which mid-keystroke would blank the editor under them.
        guard let item = outline.item(atRow: row) else { return }
        isSyncingSelection = true
        outline.reloadItem(item)
        isSyncingSelection = false
    }

    // MARK: - Model observation

    /// One subscription per manager, replaced wholesale whenever the root list
    /// changes: a manager that is no longer shown has nothing to redraw.
    private var managerWatchers: [AnyCancellable] = []

    private func observe(_ managers: [FileTreeManager]) {
        managerWatchers = managers.flatMap { manager -> [AnyCancellable] in
            [
                manager.$rootNode
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.reloadPreservingSelection() },
                manager.$isSyncing
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.reloadPreservingSelection() }
            ]
        }
        reloadPreservingSelection()
    }

    /// Watches one directory's contents so the rows appear when the read that
    /// `loadChildrenIfNeeded()` started finishes.
    private func watchChildren(of node: FileTreeNode) {
        guard childWatchers[node.id]?.node !== node else { return }
        let subscription = node.$children
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let wasExpanded = self.outline.isItemExpanded(node)
                let selected = self.outline.item(atRow: self.outline.selectedRow)
                // Same reason as `reloadPreservingSelection`: reloading rows
                // drops the outline's selection, and an unguarded drop reads
                // as the user deselecting the file they are reading.
                self.isSyncingSelection = true
                self.outline.reloadItem(node, reloadChildren: true)
                if wasExpanded { self.outline.expandItem(node) }
                self.invalidateRowIndex()
                self.reselect(selected)
                self.isSyncingSelection = false
                // The rows that just arrived may be the ones a stored path was
                // waiting for — this is where a deep restore takes its next
                // step down the tree.
                self.restoreDisclosure()
            }
        childWatchers[node.id] = ChildWatcher(node: node, subscription: subscription)
    }

    /// `reloadData` throws away the selection, and a git-status refresh runs it
    /// every few seconds — so the row the user is reading is put back.
    ///
    /// The whole reload runs under `isSyncingSelection`. The outline empties
    /// its selection *during* the reload and says so, and that report reaching
    /// `outlineViewSelectionDidChange` is what used to clear `selectedNode`
    /// and blank the viewer a moment after a click — a reload is the tree
    /// redrawing itself, never the user letting go of a file.
    private func reloadPreservingSelection() {
        let selected = outline.item(atRow: outline.selectedRow)
        isSyncingSelection = true
        outline.reloadData()
        // A single root shows its contents straight away: a tree that opens
        // onto one collapsed header makes the user click to see anything.
        //
        // Only for a browser with nothing stored, and only once: a default is
        // what fills in for an answer, never what overrules one.
        if !hasAppliedDefaultExpansion {
            hasAppliedDefaultExpansion = true
            if restoration.expandedPaths.isEmpty,
               roots.managers.count == 1,
               let only = roots.managers.first {
                outline.expandItem(only)
            }
        }
        invalidateRowIndex()
        reselect(selected)
        isSyncingSelection = false
        restoreDisclosure()
    }

    /// Re-opens the folders that were open, and re-selects the file that was
    /// selected, as far as the rows currently drawn allow.
    ///
    /// One pass is deliberately not enough. Expanding a folder only *starts*
    /// the read of its contents (`outlineViewItemWillExpand` →
    /// `loadChildrenIfNeeded`), so a path four levels deep is restored one
    /// level per pass, each pass run by the reload that the arriving children
    /// trigger. The loop terminates because a pass that expands nothing
    /// triggers no reload.
    private func restoreDisclosure() {
        isSyncingExpansion = true
        var row = 0
        while row < outline.numberOfRows {
            if let item = outline.item(atRow: row),
               let path = path(of: item),
               restoration.isExpanded(path),
               !outline.isItemExpanded(item) {
                outline.expandItem(item)
            }
            row += 1
        }
        isSyncingExpansion = false
        invalidateRowIndex()

        guard let wanted = pendingSelectionPath else { return }
        for row in 0..<outline.numberOfRows {
            guard let node = outline.item(atRow: row) as? FileTreeNode, node.url.path == wanted else { continue }
            pendingSelectionPath = nil
            selection.selectedNode = node
            return
        }

        // Not drawn. If the folder that would hold it *is* drawn, is open, and
        // has finished reading its contents, then the file is not there any
        // more — deleted or renamed since the last launch — and the request is
        // dropped. It has to be: while it stands, the selection sink treats
        // every choice the user makes as "the restore is still running" and
        // persists none of them, for the life of the pane.
        let parent = (wanted as NSString).deletingLastPathComponent
        guard let parentRow = outline.item(atRow: self.row(forPath: parent)) else { return }
        if outline.isItemExpanded(parentRow), hasReadChildren(parentRow) {
            pendingSelectionPath = nil
        }
    }

    /// Whether `item`'s contents have arrived, as opposed to merely being on
    /// their way. An empty `children` array is `FileTreeNode`'s "expandable,
    /// not read yet" — `childrenLoaded` is set when the read *starts*, so it
    /// cannot answer this.
    private func hasReadChildren(_ item: Any) -> Bool {
        switch item {
        case let manager as FileTreeManager:
            guard let root = manager.rootNode else { return false }
            return hasReadChildren(root)
        case let node as FileTreeNode:
            return !(node.children?.isEmpty ?? false)
        default:
            return false
        }
    }

    /// How a row is named in stored state: its path on disk, the one identity
    /// it keeps across launches. Placeholder rows have none — they are not
    /// somewhere the user can be.
    private func path(of item: Any) -> String? {
        switch item {
        case let manager as FileTreeManager: return manager.repoRootURL.path
        case let node as FileTreeNode: return node.url.path
        default: return nil
        }
    }

    /// Puts the outline back on `item` after a reload, if it is still drawn.
    /// A file that has been deleted or filtered away is a selection the model
    /// should lose too, so that case clears it rather than leaving the viewer
    /// showing a file the tree no longer lists (`fail-fast`).
    private func reselect(_ item: Any?) {
        guard let item else { return }
        var row = outline.row(forItem: item)
        // `row(forItem:)` matches on pointer identity, and the same file can
        // come back as a different node object whenever a directory is re-read.
        // Falling back to the path is what tells "this file is gone" apart from
        // "this file is now a different object" — without it, ordinary refresh
        // churn cleared the selection and persisted that as the user's answer.
        if row < 0, let path = path(of: item) {
            row = self.row(forPath: path)
        }
        if row >= 0 {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if item is FileTreeNode {
            selection.selectedNode = nil
        }
    }

    /// The row currently drawing `path`, or `-1`.
    ///
    /// Answered from `rowIndexByPath`, rebuilt on demand. The cached answer is
    /// verified against the row it names before it is returned: every way the
    /// rows can move invalidates the map, but a stale hit would silently
    /// redraw or reselect the *wrong* file, so this rescans rather than trust
    /// a mismatch (`fail-fast` without the crash).
    private func row(forPath path: String) -> Int {
        if let cached = rowIndexByPath?[path] {
            if cached < outline.numberOfRows,
               let item = outline.item(atRow: cached),
               self.path(of: item) == path {
                return cached
            }
            rowIndexByPath = nil
        } else if rowIndexByPath != nil {
            return -1
        }

        var index: [String: Int] = [:]
        for row in 0..<outline.numberOfRows {
            guard let item = outline.item(atRow: row), let rowPath = self.path(of: item) else { continue }
            // First wins: a path can only be drawn once, and if it somehow is
            // not, the topmost row is the one the user is looking at.
            if index[rowPath] == nil { index[rowPath] = row }
        }
        rowIndexByPath = index
        return index[path] ?? -1
    }

    /// Called wherever rows may have been inserted, removed or moved.
    private func invalidateRowIndex() {
        rowIndexByPath = nil
    }

    /// Puts the outline on `node`, for a selection that was set from outside —
    /// a host restoring what was open, or a removed root clearing it.
    private func showSelection(_ node: FileTreeNode?) {
        guard let node else {
            if outline.item(atRow: outline.selectedRow) is FileTreeNode {
                isSyncingSelection = true
                outline.deselectAll(nil)
                isSyncingSelection = false
            }
            return
        }
        guard outline.item(atRow: outline.selectedRow) as? FileTreeNode != node else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        isSyncingSelection = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        isSyncingSelection = false
    }

    /// The URL of whatever is currently selected, or `nil` when nothing is.
    private var selectedURL: URL? {
        (outline.item(atRow: outline.selectedRow) as? FileTreeNode)?.url
    }

    // MARK: - Following the editor's focus

    /// Moves the highlight to a file an editor is showing, expanding whatever
    /// it takes to get there.
    ///
    /// Guarded by `isSyncingSelection` — the same flag that already stops the
    /// outline echoing a model-driven selection back into the model. This is a
    /// second source for the same loop, and it closes the same way.
    func reveal(_ url: URL) {
        guard selectedURL != url else { return }
        expandAncestors(of: url)
        let row = self.row(forPath: url.path)
        guard row >= 0 else {
            // Not drawn yet — the parent's children are still loading. Leave a
            // standing request, which `restoreDisclosure()` already honours.
            pendingSelectionPath = url.path
            return
        }
        isSyncingSelection = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        isSyncingSelection = false
    }

    /// Clears the highlight — the editor pane the tree is following has
    /// nothing open.
    func revealNothing() {
        isSyncingSelection = true
        outline.deselectAll(nil)
        isSyncingSelection = false
    }

    /// Walks the path from the root down, expanding each ancestor in turn.
    /// Each expansion can add rows, so the row lookup is redone at every step.
    private func expandAncestors(of url: URL) {
        isSyncingExpansion = true
        defer {
            isSyncingExpansion = false
            invalidateRowIndex()
        }
        var ancestors: [String] = []
        var directory = url.deletingLastPathComponent()
        while directory.pathComponents.count > 1 {
            ancestors.append(directory.path)
            directory = directory.deletingLastPathComponent()
        }
        for path in ancestors.reversed() {
            let row = self.row(forPath: path)
            guard row >= 0, let item = outline.item(atRow: row), !outline.isItemExpanded(item) else { continue }
            outline.expandItem(item)
            invalidateRowIndex()
        }
    }

    // MARK: - Testing

    /// The URL currently selected, or `nil`. `@testable`-visible only —
    /// `selectedURL` stays private everywhere else.
    var selectedURLForTesting: URL? { selectedURL }

    /// Fires only for a selection change the outline reported on its own —
    /// never for one `reveal(_:)`/`revealNothing()` made on the model's
    /// behalf. `dropFirst()` swallows the value `@Published` replays to a new
    /// subscriber, which is not a change at all.
    var selectionPublisherForTesting: AnyPublisher<FileTreeNode?, Never> {
        selection.$selectedNode.dropFirst().eraseToAnyPublisher()
    }

    /// Collapses every row, the way a browser nobody has touched yet looks —
    /// used to pin that `reveal(_:)` can open collapsed ancestors back up.
    func collapseAllForTesting() {
        isSyncingExpansion = true
        outline.collapseItem(nil, collapseChildren: true)
        invalidateRowIndex()
        isSyncingExpansion = false
    }

    // MARK: - Activation

    @objc private func rowDoubleClicked(_ sender: Any?) {
        let item = outline.item(atRow: outline.selectedRow)
        if let manager = item as? FileTreeManager {
            toggle(manager)
            return
        }
        guard let node = item as? FileTreeNode else { return }
        // A directory has nothing to open, so a double-click means what it
        // means everywhere else: show me what is inside, or stop showing me.
        // Anything else — a file, or a childless package — is `openIfFile`'s
        // own case, the same one a plain click already reaches: shown in the
        // Document pane, never handed off to whatever app claims the
        // extension.
        if node.children != nil {
            toggle(node)
        } else {
            openIfFile(node)
        }
    }

    private func toggle(_ item: Any) {
        if outline.isItemExpanded(item) {
            outline.collapseItem(item)
        } else {
            outline.expandItem(item)
        }
    }

    // MARK: - Context menu

    /// The three verbs a file can be opened with, as items belonging to no menu
    /// yet, or `nil` for anything that is not an openable file — which is what
    /// leaves directories, repo roots and a path nothing lives at without a menu.
    ///
    /// The items are free rather than pre-installed because `menuNeedsUpdate`
    /// has to fill the menu AppKit already owns: an item that still belongs to
    /// another menu makes `addItem` throw, and AppKit swallows that as a menu
    /// that simply never opens.
    func openMenuItems(for url: URL) -> [NSMenuItem]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }

        return [
            ("Open", DocumentDestination.current),
            ("Open in a New Tab", DocumentDestination.newTab),
            ("Open to the Side", DocumentDestination.toTheSide)
        ].map { title, destination in
            let item = NSMenuItem(title: title, action: #selector(openFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = OpenRequest(url: url, destination: destination)
            return item
        }
    }

    /// The same three verbs as a standalone menu, for anywhere that needs a menu
    /// object rather than items to install.
    func makeContextMenu(for url: URL) -> NSMenu? {
        guard let items = openMenuItems(for: url) else { return nil }
        let menu = NSMenu()
        for item in items { menu.addItem(item) }
        return menu
    }

    /// Carries a menu item's `(url, destination)` pair through
    /// `representedObject`, which only holds `AnyObject`.
    private final class OpenRequest: NSObject {
        let url: URL
        let destination: DocumentDestination
        init(url: URL, destination: DocumentDestination) {
            self.url = url
            self.destination = destination
        }
    }

    @objc private func openFromMenu(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? OpenRequest else { return }
        onOpenRequest?(request.url, request.destination)
    }

    // MARK: - Items

    /// The "nothing here" row under an empty root. A class so the outline has
    /// an object to identify the row by.
    fileprivate final class Placeholder {
        var text: String
        init(_ text: String) { self.text = text }
    }

    private func placeholder(for manager: FileTreeManager) -> Placeholder {
        let text = manager.isSyncing ? "Scanning…" : "Empty"
        if let existing = placeholders[manager.repoRootURL] {
            existing.text = text
            return existing
        }
        let made = Placeholder(text)
        placeholders[manager.repoRootURL] = made
        return made
    }

    fileprivate func children(of item: Any?) -> [Any] {
        switch item {
        case nil:
            return roots.managers
        case let manager as FileTreeManager:
            let children = manager.rootNode?.children ?? []
            return children.isEmpty ? [placeholder(for: manager)] : children
        case let node as FileTreeNode:
            return node.children ?? []
        default:
            return []
        }
    }
}

// MARK: - Context menu delegate

extension FileTreeOutlineViewController: NSMenuDelegate {
    /// Rebuilds the menu for the row under the cursor — `clickedRow`, never
    /// `selectedRow` — so right-clicking a file that is not the current
    /// selection acts on the one the user is actually pointing at.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard outline.clickedRow >= 0,
              let node = outline.item(atRow: outline.clickedRow) as? FileTreeNode,
              let items = openMenuItems(for: node.url) else { return }
        for item in items { menu.addItem(item) }
    }
}

// MARK: - Outline

extension FileTreeOutlineViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let children = children(of: item)
        // AppKit asks for the count and for each child in separate calls, and a
        // directory being re-read can shrink the list in between. That is a
        // stale question, not a programmer error, so it is answered with a
        // throwaway row instead of a crash — the reload that the change is
        // about to trigger redraws it.
        guard children.indices.contains(index) else { return Placeholder("") }
        return children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is FileTreeManager { return true }
        // `[]` is a directory nobody has opened yet and `nil` is a leaf — the
        // distinction `FileTreeNode` draws so a triangle can appear before the
        // directory has been read.
        return (item as? FileTreeNode)?.children != nil
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
        watchChildren(of: node)
        node.loadChildrenIfNeeded()
    }

    /// A folder opening or closing is the whole of what "disclosed" means, so
    /// it is recorded here rather than at each of the several places that can
    /// cause one — a click, a double-click, an arrow key, a restore.
    func outlineViewItemDidExpand(_ notification: Notification) {
        // Rows moved, whoever caused it — the cached path->row map is stale.
        invalidateRowIndex()
        guard !isSyncingExpansion,
              let item = notification.userInfo?["NSObject"],
              let path = path(of: item) else { return }
        restoration.setExpanded(true, path: path)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        invalidateRowIndex()
        guard let item = notification.userInfo?["NSObject"],
              let path = path(of: item) else { return }
        // A closed folder draws no rows, so nothing needs redrawing when its
        // contents change. `outlineViewItemWillExpand` re-subscribes if it is
        // opened again.
        if let node = item as? FileTreeNode { childWatchers[node.id] = nil }
        guard !isSyncingExpansion else { return }
        restoration.setExpanded(false, path: path)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        ThemedTableRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !(item is Placeholder)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        let palette = view.resolvedThemeScope.palette
        switch item {
        case let manager as FileTreeManager:
            let isTarget = selection.selectedRoot == manager.repoRootURL
            let label = ThemedLabel(
                string: manager.repoRootURL.lastPathComponent,
                role: isTarget ? .primaryText : .secondaryText,
                textRole: .caption
            )
            label.toolTip = manager.repoRootURL.path
            return FileTreeRowView(content: label, palette: palette)
        case let placeholder as Placeholder:
            return FileTreeRowView(
                content: ThemedLabel(string: placeholder.text, role: .tertiaryText, textRole: .caption),
                palette: palette
            )
        case let node as FileTreeNode:
            let isDirty = documentStore.document(for: node.url.documentUri)?.isDirty ?? false
            return FileTreeNodeRowView(node: node, palette: palette, isDirty: isDirty)
        default:
            return nil
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        let item = outline.item(atRow: outline.selectedRow)

        if let manager = item as? FileTreeManager {
            selection.selectedRoot = manager.repoRootURL
            return
        }

        let node = item as? FileTreeNode
        selection.selectedNode = node
        // Clicking a file is also how you say which directory you mean, so the
        // footer's target follows the tree rather than needing its own click.
        if let url = node?.url, let root = directories.root(containing: url) {
            selection.selectedRoot = root
        }
        openIfFile(node)
    }

    /// A plain click says *what*; showing it is `.current`, the same
    /// destination "Open" on the context menu sends. `children == nil` is the
    /// same test `isItemExpandable` and `rowDoubleClicked` already use for
    /// "this row has nothing to disclose" — a real file, or a childless
    /// package — so all three agree on what counts as openable.
    func openIfFile(_ node: FileTreeNode?) {
        guard let node, node.children == nil else { return }
        onOpenRequest?(node.url, .current)
    }
}

// MARK: - Rows

/// A row that holds one view, inset and vertically centred. Its own type so the
/// header and placeholder rows lay out the same way the file rows do (`dry`).
@MainActor
private class FileTreeRowView: NSView {

    init(content: NSView, palette: SemanticPalette) {
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// One file or directory: an icon, the name, the unsaved-changes dot, and the
/// git status character.
@MainActor
private final class FileTreeNodeRowView: FileTreeRowView {

    /// Always built, never conditionally added: a row view is constructed once
    /// and reused, so a marker that only exists when the file happened to be
    /// dirty at construction time could never appear later. `setDirty(_:)`
    /// shows and hides the one that is always there.
    private let dirtyMarker: NSImageView

    init(node: FileTreeNode, palette: SemanticPalette, isDirty: Bool = false) {
        let icon = NSImageView(image: NSImage(
            systemSymbolName: node.systemImageName,
            accessibilityDescription: node.isDirectory ? "Folder" : "File"
        ) ?? NSImage())
        icon.contentTintColor = Self.iconColor(for: node, palette: palette)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        // The status colors are git's own vocabulary, not app chrome, so they
        // stay the fixed red/green/orange every git client uses rather than
        // being remapped onto theme roles.
        let name = ThemedLabel(string: node.name, role: .primaryText, textRole: .body)
        name.lineBreakMode = .byTruncatingMiddle
        name.cell?.usesSingleLineMode = true
        if let status = node.gitStatus {
            name.textColor = status.nsColor
        }
        name.toolTip = node.url.path

        var views: [NSView] = [icon, name]

        // Unlike the git-status badge above (git's own fixed vocabulary), this
        // marker is app chrome — a document open in the editor with unsaved
        // changes — so it takes its color from the theme rather than a fixed
        // one, the same way everything else in this row that is not git's own
        // signal does.
        let dot = NSImageView(image: NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "Unsaved changes"
        )?.withSymbolConfiguration(.init(pointSize: 6, weight: .regular)) ?? NSImage())
        dot.contentTintColor = palette.nsColor(.warning)
        dot.setContentHuggingPriority(.required, for: .horizontal)
        dot.accessibilityID("whippet.filebrowser.dirty-indicator")
        dot.isHidden = !isDirty
        self.dirtyMarker = dot
        views.append(dot)

        if let status = node.gitStatus {
            let badge = ThemedLabel(string: status.displayCharacter, role: .primaryText, textRole: .code)
            badge.textColor = status.nsColor
            badge.setContentHuggingPriority(.required, for: .horizontal)
            views.append(contentsOf: [NSView(), badge])
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5

        super.init(content: stack, palette: palette)

        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            icon.widthAnchor.constraint(equalToConstant: 16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows or hides the unsaved-changes dot on a row that is already on
    /// screen. `NSStackView` drops a hidden arranged subview from its layout,
    /// so the row re-lays out as if the marker were not there.
    func setDirty(_ isDirty: Bool) {
        dirtyMarker.isHidden = !isDirty
    }

    /// The palette has no per-language "brand color" role, so these map onto the
    /// nearest status role the same way `SwiftUIPalette.color(named:)` does.
    private static func iconColor(for node: FileTreeNode, palette: SemanticPalette) -> NSColor {
        if node.isPackage { return palette.nsColor(.warning) }
        if node.isDirectory {
            return palette.nsColor(node.name == ".claude" ? .info : .accent)
        }
        switch node.url.pathExtension.lowercased() {
        case "swift", "json":
            return palette.nsColor(.warning)
        case "md", "markdown":
            return palette.nsColor(.accent)
        default:
            return palette.nsColor(.secondaryText)
        }
    }
}
