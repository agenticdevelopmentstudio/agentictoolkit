import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitMarkdown

public final class NotesSplitViewController: ThemedSplitViewController {

    // MARK: - Dependencies

    private let notesManager: NotesManager

    /// The taxonomy store for the folders pane, when the host's storage has
    /// one — see `NotesManager.markdownStore`.
    public let markdownStore: MarkdownStore?

    /// Divider-position key, distinct per pane when a host can open more than
    /// one notes pane at a time.
    private let splitAutosaveName: String

    // MARK: - Child VCs

    private let folderVC: NotesFolderListViewController
    private let listVC: NotesListViewController
    private let editorVC = NoteEditorViewController()

    /// The split items for the folders and help panes, kept so `toggleFolders()`,
    /// `toggleHelp()` and `isHelpVisible` do not have to reach for a magic index
    /// into `splitViewItems` every time.
    private var folderItem: NSSplitViewItem?
    private var helpItem: NSSplitViewItem?

    /// Keeps the help pane's palette current — `MarkdownViewerController` takes
    /// its palette at `init` and does not observe the theme itself (see
    /// task-6-grounding G2), and this pane is persistent rather than a
    /// transient popover, so something has to drive it for the life of the
    /// window.
    private var helpThemeObserver: ThemePaletteObserver?

    // MARK: - Folder filtering (task-6-grounding G8/G9)

    /// Which folder's notes the list is currently showing. Empty is "All
    /// Notes", which matches `NoteFolder.isAllNotes` and filters nothing.
    private var selectedFolderID = ""

    /// The document ids that belong to `selectedFolderID`, resolved once per
    /// selection rather than per row, and invalidated on every reload since a
    /// mutation elsewhere (a note moved into or out of the folder) can change
    /// it. `nil` means "All Notes" — nothing to filter against.
    private var folderMembership: Set<UUID>?

    // MARK: - Toolbar state (Task 7)

    /// Fired whenever the selected note or the help pane's visibility changes
    /// — the two things `NotesWindowToolbar` reflects in its buttons.
    ///
    /// Custom-view toolbar items are the only way to give a button an
    /// accessibility identifier (task-7-grounding G7): `NSToolbarItem` itself
    /// has no accessibility conformance, and AppKit documents that
    /// `NSToolbarItemValidation` "will not send this message for items that
    /// have custom views." So the toolbar cannot lean on the automatic
    /// validation cycle G5 preferred and instead asks to be told when to
    /// re-check itself — the same manual pattern
    /// `ComposableSettings.SettingsWindow.updateToolbarState()` already uses
    /// for its own custom-view items, for the identical reason.
    public var onToolbarRelevantStateChange: (() -> Void)?

    // MARK: - Initialization

    public init(
        notesManager: NotesManager,
        markdownStore: MarkdownStore? = nil,
        autosaveName: String = "notes-split-4"
    ) {
        self.notesManager = notesManager
        self.markdownStore = markdownStore
        self.splitAutosaveName = autosaveName
        // The list watches the manager itself, so a note created anywhere else
        // — Quick Note, a scripting command, a second window — reaches this
        // pane without the mutating code having to know the pane exists. The
        // explicit `reload()` calls below stay: they also refresh the editor
        // and move the selection, which the notification deliberately does not.
        self.listVC = NotesListViewController(notesManager: notesManager)
        self.folderVC = NotesFolderListViewController(store: markdownStore)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        let folderItem = NSSplitViewItem(viewController: folderVC)
        folderItem.minimumThickness = 150
        folderItem.maximumThickness = 250
        folderItem.canCollapse = true
        folderItem.isCollapsed = !UserSettings.notesFoldersVisible.value
        self.folderItem = folderItem

        let listItem = NSSplitViewItem(viewController: listVC)
        listItem.minimumThickness = 180
        listItem.maximumThickness = 320
        // The list keeps the width it was given; the editor absorbs the rest.
        // Without this both panes share the pane's resizing, and a restored
        // width is scaled away as the split view grows into place.
        listItem.holdingPriority = .defaultLow + 1

        let editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.minimumThickness = Self.minimumEditorWidth

        // `view.resolvedThemeScope.palette` (task-6-grounding G3) rather than
        // `ThemeScope.app.palette`: this window may run its own theme scope,
        // and the seed should match it from the first frame rather than
        // waiting for the observer below to correct it.
        let helpVC = MarkdownViewerController(palette: view.resolvedThemeScope.palette)
        helpVC.content = MarkdownSyntaxReference.markdown
        let helpItem = NSSplitViewItem(viewController: helpVC)
        helpItem.minimumThickness = 260
        helpItem.maximumThickness = 360
        helpItem.canCollapse = true
        helpItem.isCollapsed = !UserSettings.notesHelpVisible.value
        self.helpItem = helpItem

        // The observer applies immediately on creation (task-6-grounding G2),
        // so the seed above is only ever visible for the instant before this
        // line runs.
        helpThemeObserver = ThemePaletteObserver(host: view) { [weak helpVC] palette in
            helpVC?.palette = palette
        }

        addSplitViewItem(folderItem)
        addSplitViewItem(listItem)
        addSplitViewItem(editorItem)
        addSplitViewItem(helpItem)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        seedDividerPositionIfUnset()
        // Set last, and only once the items exist: NSSplitView reads the
        // autosaved frames when the name is assigned, so a name given to an
        // empty split view restores nothing and never tries again.
        splitView.autosaveName = NSSplitView.AutosaveName(splitAutosaveName)

        // Re-assert collapsed state now that the autosave name has restored
        // frames: that restore is the legacy, item-unaware mechanism — it
        // writes subview frames directly, and a seeded non-zero width for a
        // pane that is supposed to open collapsed reads, to that mechanism,
        // as "this pane should be visible," silently flipping `isCollapsed`
        // back to `false`. `UserSettings` is the authoritative source for
        // visibility; the frame restore should only ever affect widths.
        folderItem.isCollapsed = !UserSettings.notesFoldersVisible.value
        helpItem.isCollapsed = !UserSettings.notesHelpVisible.value

        folderVC.delegate = self
        listVC.delegate = self
        editorVC.delegate = self

        NotificationCenter.default.addObserver(
            self, selector: #selector(storageDidFail),
            name: NotesManager.storageDidFailNotification, object: notesManager)
    }

    @objc private func storageDidFail() {
        presentStorageFailureIfPossible()
    }

    /// Shows whatever failure the manager is still holding, as a sheet on this
    /// pane's window, and does nothing if there is none or if there is no
    /// window yet.
    ///
    /// Claimed before it is shown: every host of this manager observes the same
    /// notification, and `clearStorageFailure()` is what stops three windows
    /// from stacking three sheets saying the same thing. A pane with no window
    /// — off screen, in a tab that is not selected, or not yet built — leaves
    /// the failure unclaimed, which is why `storageFailure` is read and only
    /// then cleared.
    ///
    /// Called from two places, and it has to be both. A notification alone
    /// misses every failure that happens before this pane has a window:
    /// `NotesCoordinator.start()` loads notes at launch, and Quick Note creates
    /// one from a window that has already closed by the time the write lands —
    /// in each case the notification is posted to a pane that cannot show it,
    /// and nothing ever asked again. So the pane also asks on the way in, when
    /// a window exists by definition. A failure therefore survives in the
    /// manager until some host can actually put it on screen.
    ///
    /// `beginSheetModal` and not `runModal`: this is the idiom the delete
    /// confirmation two files over already uses, and a modal run loop here
    /// would block the main thread inside a notification delivery.
    private func presentStorageFailureIfPossible() {
        guard let failure = notesManager.storageFailure, let window = view.window else { return }
        notesManager.clearStorageFailure()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failure.operation.title
        alert.informativeText = failure.operation.consequence + "\n\n" + failure.message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    override public func viewDidAppear() {
        super.viewDidAppear()
        // `viewWillAppear` is too early for this: `view.window` is already set
        // there, but the window is not yet on screen and `beginSheetModal`
        // against it is a sheet nobody sees.
        presentStorageFailureIfPossible()
    }

    override public func viewWillAppear() {
        super.viewWillAppear()
        reload()
        // The manager loads from storage asynchronously at launch, and a notes
        // *pane* is on screen before that finishes — it comes up with the
        // project window rather than because someone asked for it. Reloading
        // once from an empty manager and never hearing about the load is how a
        // pane sits blank beside a notes window listing the same notes. The
        // window already does this when it is shown; the pane is the third host
        // and the only one that appears unbidden.
        guard !notesManager.isLoaded else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.notesManager.loadNotes()
            self.reload()
        }
    }

    /// Width a notes pane opens at, the first time it is ever shown, in a pane
    /// as wide as `defaultPaneWidth`; proportionally less in a narrower one.
    private static let defaultFolderWidth: CGFloat = 200
    private static let defaultListWidth: CGFloat = 240
    private static let defaultHelpWidth: CGFloat = 300
    private static let defaultPaneWidth: CGFloat = 969

    /// Below this the note itself is narrower than the list beside it.
    private static let minimumEditorWidth: CGFloat = 300

    /// Gives a pane nobody has ever dragged a saved position to be restored
    /// from, rather than a width set from a lifecycle callback.
    ///
    /// `setPosition` is not an option here: `NSSplitViewController` lays its
    /// items out with constraints and puts the divider straight back, wherever
    /// in the lifecycle the call is made. Restoring is the one path that
    /// survives, so the first run takes it too — one mechanism for the default
    /// and for every run after it.
    ///
    /// One frame string per split item (task-6-grounding G1): folders, list,
    /// editor, help, in that order, with each x-origin accumulated across the
    /// preceding widths and divider thicknesses. Help's width is seeded even
    /// though the pane opens collapsed, so the frame it is restored to is
    /// already correct the moment someone expands it for the first time.
    private func seedDividerPositionIfUnset() {
        guard !hasStoredDividerPosition else { return }
        let height = splitView.bounds.height
        let thickness = splitView.dividerThickness
        let editorWidth = Self.defaultPaneWidth
            - Self.defaultFolderWidth - Self.defaultListWidth - Self.defaultHelpWidth
            - (thickness * 3)

        let folderX: CGFloat = 0
        let listX = folderX + Self.defaultFolderWidth + thickness
        let editorX = listX + Self.defaultListWidth + thickness
        let helpX = editorX + editorWidth + thickness

        UserDefaults.standard.set(
            [
                "\(folderX), 0.0, \(Self.defaultFolderWidth), \(height), NO, NO",
                "\(listX), 0.0, \(Self.defaultListWidth), \(height), NO, NO",
                "\(editorX), 0.0, \(editorWidth), \(height), NO, NO",
                "\(helpX), 0.0, \(Self.defaultHelpWidth), \(height), NO, NO"
            ],
            forKey: Self.dividerPositionKey(splitAutosaveName)
        )
    }

    /// Where AppKit keeps an autosaved divider position. Its absence is what
    /// "nobody has ever sized this pane" looks like.
    private var hasStoredDividerPosition: Bool {
        UserDefaults.standard.object(forKey: Self.dividerPositionKey(splitAutosaveName)) != nil
    }

    static func dividerPositionKey(_ autosaveName: String) -> String {
        "NSSplitView Subview Frames \(autosaveName)"
    }

    // MARK: - Public API (Task 7's toolbar)

    /// Toggles the folders pane, animated, and persists the new state under
    /// its own `UserDefaults` key so the next Notes window opens the same way.
    public func toggleFolders() {
        guard let folderItem else { return }
        let collapsed = !folderItem.isCollapsed
        folderItem.animator().isCollapsed = collapsed
        UserSettings.notesFoldersVisible.value = !collapsed
    }

    /// Toggles the markdown syntax help pane. A plain `NSSplitViewItem`
    /// animated collapse, per task-6-grounding — not an `NSDrawer`, which has
    /// been deprecated since macOS 10.13.
    public func toggleHelp() {
        guard let helpItem else { return }
        let collapsed = !helpItem.isCollapsed
        helpItem.animator().isCollapsed = collapsed
        UserSettings.notesHelpVisible.value = !collapsed
        onToolbarRelevantStateChange?()
    }

    public var isHelpVisible: Bool {
        helpItem.map { !$0.isCollapsed } ?? false
    }

    /// Drives the list pane's search filter from the window toolbar (Task 7),
    /// now that the list no longer owns a search field of its own.
    public func setSearchQuery(_ query: String) {
        listVC.setSearchQuery(query)
    }

    public func selectedNote() -> Note? {
        guard let id = listVC.selectedNoteID else { return nil }
        return notesManager.notes.first { $0.id == id }
    }

    /// Forwards to the folders pane's own create flow (task-6-grounding G10):
    /// that pane owns its store mutations, so the split controller's part is
    /// only to know which folder is selected and to ask.
    public func createFolderUnderSelection() {
        folderVC.createFolder(under: folderVC.selectedFolder)
    }

    /// Forwards to the folders pane's existing confirmation sheet
    /// (task-6-grounding G10) rather than deleting outright, so a File-menu
    /// delete and a right-click delete behave identically. A no-op with
    /// nothing selected.
    public func deleteSelectedFolder() {
        guard let folder = folderVC.selectedFolder else { return }
        folderVC.presentDeleteConfirmation(for: folder)
    }

    // MARK: - Reload

    public func reload() {
        listVC.reload(notes: notesForCurrentFolder(), keepingSelectedID: listVC.selectedNoteID)
        if let id = listVC.selectedNoteID,
           let note = notesManager.notes.first(where: { $0.id == id }) {
            editorVC.show(note: note)
        }
    }

    /// The manager's notes, filtered to `selectedFolderID`'s membership.
    ///
    /// Resolves (and caches) the membership set the first time it is needed
    /// after a folder selection or a reload invalidates it — task-6-grounding
    /// G8 prefers `documentIDs(forCategory:)` over a per-note sweep, since
    /// Task 5 added exactly that. Membership is direct, not transitive:
    /// selecting a parent folder does not pull in its children's notes. All
    /// Notes (`selectedFolderID.isEmpty`) filters nothing.
    private func notesForCurrentFolder() -> [Note] {
        guard !selectedFolderID.isEmpty else { return notesManager.notes }
        let membership = currentFolderMembership()
        return notesManager.notes.filter { membership.contains($0.id) }
    }

    private func currentFolderMembership() -> Set<UUID> {
        if let folderMembership { return folderMembership }
        let ids: Set<UUID>
        // `documentIDs(forCategory:)` answers in the markdown store's own id
        // space — lowercased UUID strings (see `MarkdownNoteStorage`, which
        // writes `note.id.uuidString.lowercased()` as the document id) — so
        // the result has to come back through `UUID(uuidString:)` before it
        // is comparable to `Note.id`.
        if let markdownStore, !selectedFolderID.isEmpty,
           let documentIDs = try? markdownStore.documentIDs(forCategory: selectedFolderID) {
            ids = Set(documentIDs.compactMap { UUID(uuidString: $0) })
        } else {
            ids = []
        }
        folderMembership = ids
        return ids
    }
}

// MARK: - NotesFolderListViewControllerDelegate

extension NotesSplitViewController: NotesFolderListViewControllerDelegate {

    public func notesFolderListDidSelect(_ folder: NoteFolder) {
        selectedFolderID = folder.id
        folderMembership = nil
        reload()
    }

    public func notesFolderListDidRequestNewFolder(under parent: NoteFolder?) {
        // A new folder starts empty and does not change any other folder's
        // membership, and `NotesFolderListViewController.selectFolder(id:)`
        // selects it in the outline without notifying this delegate — so the
        // list pane's current filter is unaffected. Nothing to do.
    }

    public func notesFolderListDidRequestDelete(_ folder: NoteFolder) {
        // A deleted folder can never be the current selection again — its
        // notes are still there, just no longer filtered to a folder that no
        // longer exists.
        if selectedFolderID == folder.id { selectedFolderID = "" }
        folderMembership = nil
        reload()
    }

    public func notesFolderListDidRequestRename(_ folder: NoteFolder, to name: String) {
        // Membership is unaffected by a rename; nothing to invalidate.
    }
}

// MARK: - NotesListViewControllerDelegate

extension NotesSplitViewController: NotesListViewControllerDelegate {

    public func notesListDidSelectNote(_ note: Note?) {
        editorVC.show(note: note)
        onToolbarRelevantStateChange?()
    }

    public func notesListDidRequestNewNote() {
        Task { @MainActor in
            // No id means the insert failed and the note was discarded; the
            // sheet is already on its way, and selecting nothing is right.
            guard let newID = await notesManager.createNote(content: "") else { return }
            let newNote = notesManager.notes.first(where: { $0.id == newID })
            // task-6-grounding G9: a new note created inside a filtered
            // (non-"All Notes") folder view has no category yet, so it is not
            // a member of the selected folder and correctly does not appear
            // here — filtering through the same funnel as `reload()` avoids
            // showing it and then losing it on the very next reload.
            listVC.reload(notes: notesForCurrentFolder(), keepingSelectedID: newID)
            editorVC.show(note: newNote)
        }
    }
}

// MARK: - NoteEditorViewControllerDelegate

extension NotesSplitViewController: NoteEditorViewControllerDelegate {

    public func noteEditorDidChangeContent(_ content: String, for noteID: UUID) {
        guard let note = notesManager.notes.first(where: { $0.id == noteID }) else { return }
        Task { @MainActor in
            await notesManager.updateNote(note, content: content)
            listVC.reload(notes: notesForCurrentFolder(), keepingSelectedID: noteID)
        }
    }
}
