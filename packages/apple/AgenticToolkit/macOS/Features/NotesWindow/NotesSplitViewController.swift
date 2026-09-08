import AppKit
import OSLog
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

    /// `PaneSelectionDescribing`'s change callback. Stored here rather than in
    /// the conformance below because Swift has no stored properties in
    /// extensions, and the protocol declares it `{ get set }`.
    public var onPaneSelectionChange: (() -> Void)?

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
    var onToolbarRelevantStateChange: (() -> Void)?

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
        // Must wait until after `super.init()`: capturing `self`, even
        // weakly, to reach `notesForCurrentFolder()` is "use of self before
        // all stored properties are set" before that point. This is what
        // keeps the list pane's own self-refresh (above) honouring the
        // current folder filter instead of falling back to the manager's
        // unfiltered notes (H1) — this controller is the single owner of the
        // filter, and the list pane never needs to learn folders exist.
        listVC.notesProvider = { [weak self] in self?.notesForCurrentFolder() ?? [] }
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

    // MARK: - The ⋯ menu's actions (Task 8)

    /// Pin/Unpin (task-8-grounding G7's title, not a pin icon) — the button
    /// removed in Task 4 is back where Apple Notes keeps it, in the overflow
    /// menu.
    public func togglePinOnSelectedNote() {
        guard let note = selectedNote() else { return }
        Task { @MainActor in
            await notesManager.togglePin(note: note)
            listVC.reload(notes: notesForCurrentFolder(), keepingSelectedID: note.id)
            onToolbarRelevantStateChange?()
        }
    }

    /// A new note with the selected note's content, unchanged — its title
    /// follows from that content, so the copy is named the same, which is
    /// correct and matches Apple Notes.
    ///
    /// Also carries over the original's folder memberships. The brief's own
    /// wording only asks for identical content, but leaving the duplicate
    /// unfiled would reproduce, for a duplicate, exactly the surprise
    /// task-8-grounding G10 (Ruling 39) just closed for brand-new notes: a
    /// note the user is looking at because it is in the filtered folder that
    /// vanishes the moment it is duplicated.
    public func duplicateSelectedNote() {
        guard let note = selectedNote() else { return }
        Task { @MainActor in
            guard let newID = await notesManager.createNote(content: note.content) else { return }
            if let markdownStore {
                let documentID = note.id.uuidString.lowercased()
                let newDocumentID = newID.uuidString.lowercased()
                let categories = (try? markdownStore.categories(forDocument: documentID)) ?? []
                for category in categories {
                    do {
                        try markdownStore.assignCategory(category.id, toDocument: newDocumentID)
                    } catch {
                        Self.logger.error(
                            """
                            Failed to file duplicate \(newDocumentID, privacy: .public) \
                            under category \(category.id, privacy: .public): \
                            \(error, privacy: .public)
                            """)
                    }
                }
            }
            // Unconditional, unlike the cache invalidation above: the copy
            // needs the list to show it even when it carried no categories.
            await reloadAfterFolderMembershipChange(keepingSelectedID: newID)
            let newNote = notesManager.notes.first(where: { $0.id == newID })
            editorVC.show(note: newNote)
        }
    }

    /// The underlying mutation, split out of `deleteSelectedNote()` so a test
    /// can drive it directly — the same shape
    /// `NotesFolderListViewController.deleteFolder(_:)` already uses, since
    /// an `NSAlert` sheet cannot be answered from a headless test run.
    func performDelete(_ note: Note) {
        Task { @MainActor in
            await notesManager.deleteNote(id: note.id)
            // Read before the reload below overwrites it: the user may have
            // changed the selection during the `await` above, and only
            // clearing the editor when they are still looking at the note
            // that just got deleted is what keeps a selection they moved on
            // to from being discarded out from under them.
            let stillSelectedID = listVC.selectedNoteID
            await reloadAfterFolderMembershipChange(keepingSelectedID: stillSelectedID)
            if stillSelectedID == note.id {
                editorVC.show(note: nil)
            }
            onToolbarRelevantStateChange?()
        }
    }

    /// Asks first, with the wording recovered from `NoteEditorViewController
    /// .deleteTapped` before Task 4 removed it and then corrected again by
    /// task-8-grounding G9 (Ruling 38) to match Task 5's folder-delete
    /// alert. A delete with no window silently does nothing rather than
    /// trapping — the same guard G3/G9 call out explicitly.
    public func deleteSelectedNote() {
        guard let note = selectedNote(), let window = view.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(note.title)”?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performDelete(note)
        }
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { finish(response) }
        }
    }

    /// "Move to" (task-8-grounding G5): a note may sit in several folders at
    /// once (spec §6.1), so this reassigns rather than enforcing single
    /// membership — picking a folder the note is not already in adds it;
    /// picking one it is already in removes it; `id.isEmpty` ("None")
    /// removes every current membership. With no store this is a no-op — the
    /// menu already disables the whole submenu in that case.
    public func moveSelectedNote(toFolder id: String) {
        guard let note = selectedNote(), let markdownStore else { return }
        let documentID = note.id.uuidString.lowercased()
        do {
            let current = try markdownStore.categories(forDocument: documentID)
            if id.isEmpty {
                for category in current {
                    try markdownStore.unassignCategory(category.id, fromDocument: documentID)
                }
            } else if current.contains(where: { $0.id == id }) {
                try markdownStore.unassignCategory(id, fromDocument: documentID)
            } else {
                try markdownStore.assignCategory(id, toDocument: documentID)
            }
        } catch {
            // Matches `createNote()`'s log shape (documentID, the folder id,
            // then the error) and routes through the manager's existing
            // storage-failure path rather than swallowing the error, so a
            // failed move reaches the user the same way a failed save does
            // (M2 in the review this fixes) instead of silently doing nothing.
            Self.logger.error(
                """
                Failed to move document \(documentID, privacy: .public) \
                to category \(id, privacy: .public): \
                \(error, privacy: .public)
                """)
            notesManager.reportStorageFailure(.save, error)
            return
        }
        Task { @MainActor in
            await reloadAfterFolderMembershipChange(keepingSelectedID: note.id)
        }
    }

    /// `NSSharingServicePicker(items: [note.content])` — markdown as-is, no
    /// format conversion, no "Export as" submenu (spec §7).
    public func shareSelectedNote(from view: NSView) {
        guard let note = selectedNote() else { return }
        let picker = NSSharingServicePicker(items: [note.content])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    /// Dispatches through the responder chain (task-8-grounding G2) rather
    /// than adding a `showFindInterface()` forwarder to
    /// `MarkdownEditorController`: `NSTextView` reads the requested action off
    /// the sender's `tag`, so a tagged, target-less `NSMenuItem` is enough to
    /// ask for it. `focusEditor()` (ADT's Task 4 fix round, Ruling 20) makes
    /// the pane's text view first responder first — `performTextFinderAction`
    /// dispatches to whichever view is first responder, not to a specific one.
    public func findInNote() {
        editorVC.editorController.focusEditor()
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
    }

    /// Everything that has to happen when a note's folder membership changes.
    /// The four steps are one piece of knowledge and they go stale
    /// independently: `folderMembership` is this controller's own cache and
    /// `notesForCurrentFolder()` filters against it; `NotesFolderListView
    /// Controller` observes no notifications, so its counts only move when
    /// something calls `reload()` on it.
    ///
    /// The flush is first and is not optional. `loadNotes()` replaces the
    /// in-memory notes wholesale from disk, and `NotesManager.updateNote`
    /// only *arms* a save — so a paragraph typed half a second before the
    /// user hits Delete on some other note is still sitting in the debounce
    /// when the reload overwrites it with the pre-edit copy from disk. Worse
    /// than losing it: the debounce then fires, re-reads `notes.first(where:)`
    /// — now the stale copy — and writes that back over the row it was
    /// supposed to update. Flushing turns the pending edit into a completed
    /// write before anything reads disk, so the reload picks it up.
    private func reloadAfterFolderMembershipChange(keepingSelectedID id: UUID?) async {
        folderMembership = nil
        await notesManager.flushPendingSaves()
        await notesManager.loadNotes()
        folderVC.reload()
        listVC.reload(notes: notesForCurrentFolder(), keepingSelectedID: id)
    }

    /// The single authoritative "make a note and show it" path: creates the
    /// note, files it under the selected folder, refreshes the folder counts
    /// and the list, and selects it in the editor. Distinct from
    /// `NotesManager.createNote(content:)`, which only writes the row — this
    /// is what every caller that also has a window means by "new note".
    /// Callers: the list's "+" button, Cmd-N (Task 9), Import (Task 10).
    public func createNote(content: String = "") {
        Task { @MainActor in
            // No id means the insert failed and the note was discarded; the
            // sheet is already on its way, and selecting nothing is right.
            guard let newID = await notesManager.createNote(content: content) else { return }
            // task-8-grounding G10 (Ruling 39): a new note lands in whatever
            // folder is selected, the way Apple Notes does — leaving it
            // unfiled put it in the editor while the filtered list beside it
            // excluded it, so the user typed into a note they could not see.
            // `selectedFolderID` is empty for "All Notes", which is exactly
            // the "leave it unfiled" case and needs no special handling.
            //
            // Read *before* the await, the way `performDelete(_:)` reads its
            // selection: `selectedFolderID` is mutable and the sidebar is
            // live, so a folder clicked while the insert is in flight would
            // otherwise decide where the note lands — filing it under a
            // folder the user was not in when they asked for it, or, if they
            // landed on "All Notes", skipping the filing entirely and leaving
            // the note unfiled while the editor shows it.
            let folderID = selectedFolderID
            if let markdownStore, !folderID.isEmpty {
                let newDocumentID = newID.uuidString.lowercased()
                do {
                    try markdownStore.assignCategory(folderID, toDocument: newDocumentID)
                } catch {
                    Self.logger.error(
                        """
                        Failed to file new document \(newDocumentID, privacy: .public) \
                        under category \(folderID, privacy: .public): \
                        \(error, privacy: .public)
                        """)
                }
            }
            // Reloads unconditionally, even for "All Notes" where nothing
            // above changed any membership: `reloadAfterFolderMembershipChange`
            // is the one piece of knowledge shared with `duplicateSelectedNote()`,
            // `moveSelectedNote(toFolder:)` and `performDelete(_:)`, and this is
            // the fourth of the four call sites that need it.
            await reloadAfterFolderMembershipChange(keepingSelectedID: newID)
            let newNote = notesManager.notes.first(where: { $0.id == newID })
            editorVC.show(note: newNote)
        }
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
        if selectedFolderID == folder.id {
            selectedFolderID = ""
            // `folderVC.reload()` already ran (inside `deleteFolder(_:)`,
            // before this delegate callback) and, finding no row left for the
            // id just deleted, fell back to `outline.deselectAll`. Selecting
            // "All Notes" explicitly — non-notifying, so there is no delegate
            // bounce back into this method — is what keeps the sidebar
            // showing a highlighted row that matches what the list falls
            // back to (L2 in the review this fixes).
            folderVC.selectFolder(id: "")
        }
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
        // The single funnel for every change of *which* note is selected, so
        // the footer is told from one place rather than from each caller that
        // can move the selection (`dry`). It is not the only place the footer
        // is told: `Note.title` is derived from the content, so editing the
        // selected note's first line changes the answer without moving the
        // selection — `noteEditorDidChangeContent` reports that one.
        onPaneSelectionChange?()
    }

    public func notesListDidRequestNewNote() {
        createNote()
    }
}

// MARK: - NoteEditorViewControllerDelegate

extension NotesSplitViewController: NoteEditorViewControllerDelegate {

    public func noteEditorDidChangeContent(_ content: String, for noteID: UUID) {
        guard let note = notesManager.notes.first(where: { $0.id == noteID }) else { return }
        Task { @MainActor in
            await notesManager.updateNote(note, content: content)
            listVC.reload(notes: notesForCurrentFolder(), keepingSelectedID: noteID)
            // A note's title is its first line, so this edit may have renamed
            // it. The selection never moved, so the list's delegate funnel
            // above never fires — but `paneSelectionDescription` now answers
            // differently, which is exactly when `PaneSelectionDescribing`
            // says to report. Only for the note the footer is naming; an edit
            // to some other note changes nothing the footer shows.
            if selectedNote()?.id == noteID {
                onPaneSelectionChange?()
            }
        }
    }
}

// MARK: - Loggable

extension NotesSplitViewController: Loggable {
    public static nonisolated let logger = makeLogger()
}

// MARK: - PaneSelectionDescribing

extension NotesSplitViewController: PaneSelectionDescribing {
    /// The selected note's title — the same derivation the list shows, read
    /// back off the note rather than derived a second time here.
    public var paneSelectionDescription: String? {
        selectedNote()?.title
    }
}
