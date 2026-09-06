import AppKit
import os
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitMarkdown

/// Told what the folders pane's user actions mean, so the host can react.
///
/// `notesFolderListDidSelect` is the only method this pane's own state
/// depends on nothing else for. The other three fire *after* this
/// controller has already performed the mutation on `store` and reloaded
/// itself — they exist so a host with its own cached state (a filtered note
/// list, say) knows to refresh it, not so the host can perform the mutation
/// itself. See `NotesFolderListViewController`'s doc comment for why the
/// mutation lives here rather than in the delegate.
@MainActor public protocol NotesFolderListViewControllerDelegate: AnyObject {
    func notesFolderListDidSelect(_ folder: NoteFolder)
    func notesFolderListDidRequestNewFolder(under parent: NoteFolder?)
    func notesFolderListDidRequestDelete(_ folder: NoteFolder)
    func notesFolderListDidRequestRename(_ folder: NoteFolder, to name: String)
}

/// The folders pane: an `NSOutlineView` over the category graph, with a
/// synthetic "All Notes" root above it.
///
/// This controller owns its store mutations — `createCategory`,
/// `addCategoryEdge`, `renameCategory`, `deleteCategory` — rather than
/// asking its delegate to perform them. `init(store:)` exists specifically
/// so this controller can reach a live `MarkdownStore` on its own (see
/// `NoteTaxonomyProviding`); routing every edit back through a delegate that
/// would need that same store reference would just duplicate the plumbing.
/// The delegate's "DidRequest" methods are notifications of what already
/// happened, named to match `NotesListViewControllerDelegate`'s
/// "DidRequest" convention elsewhere in this feature even though the two
/// controllers split the work differently: that one's delegate performs the
/// mutation because only the host holds the manager that knows how; this
/// one's store is reachable straight from the controller, so it does not
/// need to hand the work anywhere else.
@MainActor public final class NotesFolderListViewController: NSViewController {

    // MARK: - Public API

    public weak var delegate: NotesFolderListViewControllerDelegate?

    private let store: MarkdownStore?

    public init(store: MarkdownStore?) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var selectedFolderID: String? {
        (outline.item(atRow: outline.selectedRow) as? NoteFolder)?.id
    }

    /// Rebuilds the tree from `store` and redraws. Safe to call at any time,
    /// including from within a mutation method below — each of those calls
    /// this once it has written to the store.
    ///
    /// A `nil` store (a host whose `NoteStorage` is not `MarkdownStore`-backed
    /// — see `NoteTaxonomyProviding`) still shows "All Notes", just with
    /// nothing under it and a count of zero, rather than an empty pane with
    /// no explanation.
    public func reload() {
        let previouslySelected = selectedFolderID
        guard let store else {
            topLevelItems = [Self.allNotesFolder(total: 0)]
            outline.reloadData()
            return
        }
        do {
            let categories = try store.categories()
            let edges = try store.categoryEdges()
            let counts = try store.categoryNoteCounts()
            let total = try store.documents(marker: .note).count
            let roots = NoteFolder.tree(from: categories, counts: counts, edges: edges, total: total)
            topLevelItems = [Self.allNotesFolder(total: total)] + roots
        } catch {
            logger.error("Failed to reload folders: \(error.localizedDescription, privacy: .public)")
            return
        }
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        if let previouslySelected {
            selectFolder(id: previouslySelected)
        }
    }

    /// Selects the row for `id` if one is showing, without notifying the
    /// delegate — this is a host telling the pane what is already selected
    /// elsewhere, not a user click, and re-announcing it would just bounce
    /// the notification back to whoever called this.
    public func selectFolder(id: String) {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        guard let row = row(forFolderID: id) else {
            outline.deselectAll(nil)
            return
        }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    // MARK: - Mutations
    //
    // Internal rather than private so tests can drive them directly without
    // going through the `NSAlert`/`NSMenu` glue below, which a headless test
    // cannot click through.

    /// Creates a category named "New Folder" — matching Finder's own
    /// "untitled folder" convention of naming first and letting the user
    /// rename afterward, rather than prompting up front — and nests it under
    /// `parent` when one is given and is a real folder (not All Notes, which
    /// is not a category and cannot be a parent).
    func createFolder(under parent: NoteFolder?) {
        guard let store else { return }
        do {
            let created = try store.createCategory(name: "New Folder")
            if let parent, !parent.isAllNotes {
                try store.addCategoryEdge(parent: parent.id, child: created.id)
            }
            reload()
            selectFolder(id: created.id)
            delegate?.notesFolderListDidRequestNewFolder(under: parent)
        } catch {
            logger.error("Failed to create folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Renames a category. A no-op for All Notes, which is synthetic and not
    /// a category `renameCategory` could find.
    func renameFolder(_ folder: NoteFolder, to name: String) {
        guard let store, !folder.isAllNotes else { return }
        do {
            try store.renameCategory(folder.id, to: name)
            reload()
            delegate?.notesFolderListDidRequestRename(folder, to: name)
        } catch {
            logger.error("Failed to rename folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes a category. Never deletes a note: `deleteCategory` tombstones
    /// the category, its edges and its item assignments, and never touches
    /// `markdown` (Task 2, rule 4) — the confirmation alert below states that
    /// as a fact, not reassurance. A no-op for All Notes.
    func deleteFolder(_ folder: NoteFolder) {
        guard let store, !folder.isAllNotes else { return }
        do {
            try store.deleteCategory(folder.id)
            reload()
            delegate?.notesFolderListDidRequestDelete(folder)
        } catch {
            logger.error("Failed to delete folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Outline

    /// Not private: tests drive selection and read rows straight off this
    /// outline view, since simulating a user click has to go through the
    /// real `NSOutlineView` selection machinery to exercise
    /// `outlineViewSelectionDidChange` at all.
    let outline = ThemedOutlineView(role: .windowBackground)

    private var topLevelItems: [NoteFolder] = []
    private var isSyncingSelection = false

    private static func allNotesFolder(total: Int) -> NoteFolder {
        NoteFolder(id: "", name: "All Notes", noteCount: total, children: [])
    }

    private func children(of item: Any?) -> [NoteFolder] {
        switch item {
        case nil:
            return topLevelItems
        case let folder as NoteFolder:
            return folder.children
        default:
            return []
        }
    }

    private func row(forFolderID id: String) -> Int? {
        (0..<outline.numberOfRows).first {
            (outline.item(atRow: $0) as? NoteFolder)?.id == id
        }
    }

    private func clickedFolder() -> NoteFolder? {
        let row = outline.clickedRow
        guard row >= 0 else { return nil }
        return outline.item(atRow: row) as? NoteFolder
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
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
        outline.menu = contextMenu
        outline.accessibilityID("notes.folders.tree")
        contextMenu.delegate = self

        let scrollView = ThemedScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = outline

        view = scrollView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    // MARK: - Context menu

    private lazy var contextMenu = NSMenu()

    @objc private func newFolderMenuItemClicked() {
        let clicked = clickedFolder()
        createFolder(under: (clicked?.isAllNotes == true) ? nil : clicked)
    }

    @objc private func renameMenuItemClicked() {
        guard let folder = clickedFolder(), !folder.isAllNotes else { return }
        presentRenamePrompt(for: folder)
    }

    @objc private func deleteMenuItemClicked() {
        guard let folder = clickedFolder(), !folder.isAllNotes else { return }
        presentDeleteConfirmation(for: folder)
    }

    private func presentRenamePrompt(for folder: NoteFolder) {
        let alert = NSAlert()
        alert.messageText = "Rename Folder"
        alert.informativeText = "Enter a new name for “\(folder.name)”."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: folder.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = field

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            self?.renameFolder(folder, to: name)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            finish(alert.runModal())
        }
    }

    private func presentDeleteConfirmation(for folder: NoteFolder) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(folder.name)”?"
        alert.informativeText = "The notes in this folder are not deleted."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.deleteFolder(folder)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            finish(alert.runModal())
        }
    }
}

// MARK: - Outline data source & delegate

extension NotesFolderListViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !children(of: item).isEmpty
    }

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        ThemedTableRowView()
    }

    public func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let folder = item as? NoteFolder else { return nil }
        return NoteFolderRowView(folder: folder)
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        guard let folder = outline.item(atRow: outline.selectedRow) as? NoteFolder else { return }
        delegate?.notesFolderListDidSelect(folder)
    }
}

// MARK: - Context menu

extension NotesFolderListViewController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "New Folder", action: #selector(newFolderMenuItemClicked), keyEquivalent: "")
        if let folder = clickedFolder(), !folder.isAllNotes {
            menu.addItem(withTitle: "Rename…", action: #selector(renameMenuItemClicked), keyEquivalent: "")
            menu.addItem(withTitle: "Delete…", action: #selector(deleteMenuItemClicked), keyEquivalent: "")
        }
        for item in menu.items {
            item.target = self
        }
    }
}

extension NotesFolderListViewController: Loggable {
    public static nonisolated let logger = makeLogger()
}

// MARK: - Row

/// A folder row: a name on the leading edge, a note count on the trailing
/// edge. Built from `ThemedLabel`s per the brief — `FileTreeNodeRowView` is
/// private to `FileTreeOutlineViewController` and wired to git status and
/// filesystem icons that have nothing to do with a folder row.
private final class NoteFolderRowView: NSView {

    init(folder: NoteFolder) {
        super.init(frame: .zero)

        let nameLabel = ThemedLabel(string: folder.name, role: .primaryText, textRole: .body)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let countLabel = ThemedLabel(
            string: "\(folder.noteCount)", role: .secondaryText, textRole: .caption)
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [nameLabel, countLabel])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
