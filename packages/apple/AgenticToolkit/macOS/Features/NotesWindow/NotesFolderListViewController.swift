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
            if let row = row(forFolderID: created.id) {
                beginRenaming(row: row)
            }
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

    /// Commits an inline edit of a folder row's name field — the end of the
    /// `NSOutlineView` cell-editing path wired up in
    /// `outlineView(_:viewFor:item:)` below. Kept separate from that AppKit
    /// glue, and from `NoteFolderRowView` itself, so a test can call it
    /// directly without driving real text-field editing through AppKit, the
    /// same seam the mutation methods above already use for the menu/alert
    /// glue.
    ///
    /// Trims whitespace and ignores an empty result, exactly as the modal
    /// prompt this replaced did. Also ignores a name that is unchanged after
    /// trimming — editing ends whenever the field resigns first responder,
    /// including a click-away with no typing, and that should not churn the
    /// store or notify the delegate.
    func commitRename(of folder: NoteFolder, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != folder.name else { return }
        renameFolder(folder, to: name)
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

    /// Begins inline editing of a row's name field — the native
    /// `NSOutlineView` rename mechanism (Finder, Mail, Xcode, and Apple
    /// Notes itself all use it for sidebar items) that replaced the modal
    /// rename prompt. Making the field first responder rather than calling
    /// the legacy cell-based `editColumn(_:row:with:select:)` works
    /// uniformly here because every row is view-based
    /// (`outlineView(_:viewFor:item:)` below always returns a real
    /// `NoteFolderRowView`), so there is always a concrete `NSTextField` to
    /// hand focus to. `makeIfNecessary: true` is what makes this safe to
    /// call right after `reload()`/`selectFolder(id:)`, before AppKit has
    /// necessarily laid out the row on screen. A no-op for a row whose field
    /// is not editable — All Notes.
    private func beginRenaming(row: Int) {
        guard row >= 0,
              let rowView = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NoteFolderRowView,
              rowView.nameField.isEditable
        else { return }
        view.window?.makeFirstResponder(rowView.nameField)
        rowView.nameField.currentEditor()?.selectAll(nil)
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
        guard let folder = clickedFolder(), !folder.isAllNotes, let row = row(forFolderID: folder.id) else { return }
        beginRenaming(row: row)
    }

    @objc private func deleteMenuItemClicked() {
        guard let folder = clickedFolder(), !folder.isAllNotes else { return }
        presentDeleteConfirmation(for: folder)
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
        let row = NoteFolderRowView(folder: folder)
        row.onCommit = { [weak self] newName in
            self?.commitRename(of: folder, to: newName)
        }
        return row
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
            // No ellipsis: this no longer opens a dialog, it begins inline
            // editing on the row — same convention Finder's own "Rename"
            // context-menu item follows.
            menu.addItem(withTitle: "Rename", action: #selector(renameMenuItemClicked), keyEquivalent: "")
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
///
/// The name field is editable in place — this is the row's half of the
/// inline-rename mechanism the controller drives via `beginRenaming(row:)`.
/// `onCommit` fires once, with the field's raw (untrimmed) text, whenever
/// editing ends for any reason (Return, Tab, or the field simply losing
/// first responder); `commitRename(of:to:)` on the controller is what trims
/// and decides whether that counts as a real rename. All Notes is built with
/// an uneditable field — `isEditable` follows `folder.isAllNotes` at
/// construction, and `beginRenaming(row:)` checks it again before handing
/// the field first responder, so there is no path that opens editing on it.
private final class NoteFolderRowView: NSView, NSTextFieldDelegate {

    let nameField: NSTextField

    /// Called with the field's text once editing ends. `nil` until the
    /// controller wires it up in `outlineView(_:viewFor:item:)`.
    var onCommit: ((String) -> Void)?

    init(folder: NoteFolder) {
        let nameField = ThemedLabel(string: folder.name, role: .primaryText, textRole: .body)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameField.isEditable = !folder.isAllNotes
        nameField.isSelectable = !folder.isAllNotes
        self.nameField = nameField

        let countLabel = ThemedLabel(
            string: "\(folder.noteCount)", role: .secondaryText, textRole: .caption)
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [nameField, countLabel])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        nameField.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit?(nameField.stringValue)
    }
}
