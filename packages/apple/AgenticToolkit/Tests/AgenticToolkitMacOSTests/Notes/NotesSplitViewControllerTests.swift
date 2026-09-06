import AppKit
import XCTest
import AgenticToolkitCore
import AgenticToolkitMarkdown
@testable import AgenticToolkitMacOS

/// The notes pane has to reopen at the width it was left at. AppKit restores an
/// autosaved divider position when the name is assigned, which makes two things
/// load-bearing and neither of them visible at the call site: the name must be
/// set *after* the split items exist, and the list must hold its width while the
/// pane lays out. These pin both, plus the four-pane layout Task 6 added:
/// folders, list, editor, help, in that order, and the folder filtering and
/// help-pane visibility that come with it.
@MainActor
final class NotesSplitViewControllerTests: XCTestCase {

    /// Notes are irrelevant to divider geometry, so storage is an empty stub
    /// rather than a database.
    private struct EmptyNoteStorage: NoteStorage {
        func fetchAllNotes() throws -> [Note] { [] }
        func insertNote(_ note: Note) throws {}
        func updateNote(_ note: Note) throws {}
        func deleteNote(id: UUID) throws {}
    }

    /// `notesFoldersVisible`/`notesHelpVisible` are `UserSetting`s backed by the
    /// real `UserDefaults`-backed store, shared process-wide — a test that left
    /// either flipped would leak into whichever test ran next. Pinning both to
    /// their documented defaults before (and after) every test keeps the pane's
    /// *own* default behavior, asserted below, from depending on run order.
    override func setUp() async throws {
        try await super.setUp()
        UserSettings.notesFoldersVisible.value = true
        UserSettings.notesHelpVisible.value = false
    }

    override func tearDown() async throws {
        UserSettings.notesFoldersVisible.value = true
        UserSettings.notesHelpVisible.value = false
        try await super.tearDown()
    }

    /// Divider positions live in `UserDefaults` under a global key, so each test
    /// gets a name of its own and takes it away again.
    private func makeAutosaveName() -> String {
        let name = "notes-split-tests-\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(name)")
        }
        return name
    }

    private func makeSplit(autosaveName: String, markdownStore: MarkdownStore? = nil) -> NotesSplitViewController {
        NotesSplitViewController(
            notesManager: NotesManager(storage: EmptyNoteStorage()),
            markdownStore: markdownStore,
            autosaveName: autosaveName
        )
    }

    /// A four-entry frame array, one per split item in `folder, list, editor,
    /// help` order, with only the list's width chosen by the caller — the
    /// other three are held at the layout's own defaults so the total still
    /// adds up to `totalWidth`.
    private func seedDividerPosition(listWidth: CGFloat, totalWidth: CGFloat, name: String) {
        let folderWidth: CGFloat = 200
        let helpWidth: CGFloat = 300
        let thickness: CGFloat = 1
        let editorWidth = totalWidth - folderWidth - listWidth - helpWidth - thickness * 3
        let folderX: CGFloat = 0
        let listX = folderX + folderWidth + thickness
        let editorX = listX + listWidth + thickness
        let helpX = editorX + editorWidth + thickness
        UserDefaults.standard.set(
            [
                "\(folderX).000000, 0.000000, \(folderWidth).000000, 532.000000, NO, NO",
                "\(listX).000000, 0.000000, \(listWidth).000000, 532.000000, NO, NO",
                "\(editorX).000000, 0.000000, \(editorWidth).000000, 532.000000, NO, NO",
                "\(helpX).000000, 0.000000, \(helpWidth).000000, 532.000000, NO, NO"
            ],
            forKey: "NSSplitView Subview Frames \(name)"
        )
    }

    /// Digs the row count out of the list pane's table view without needing a
    /// public accessor for it. `splitView.subviews[1]` is not `listVC.view`
    /// itself — `NSSplitViewController` wraps each arranged item in a private
    /// `_NSSplitViewItemViewWrapper`, so `listVC.view` is one level further
    /// in, and the scroll view wrapping the table is one level past that.
    private func listRowCount(_ split: NotesSplitViewController) -> Int? {
        let wrapper = split.splitView.subviews[1]
        guard let listView = wrapper.subviews.first,
              let scrollView = listView.subviews.first as? NSScrollView,
              let table = scrollView.documentView as? NSTableView else { return nil }
        return table.numberOfRows
    }

    private func store() throws -> MarkdownStore {
        try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
    }

    /// `notesListDidRequestNewNote()` answers a delegate callback, not an
    /// `async` request, so it fires an unstructured `Task` and returns before
    /// the note exists. Polls instead of assuming one runloop turn is enough.
    private func pollUntil(
        attempts: Int = 200,
        intervalNanoseconds: UInt64 = 10_000_000,
        _ condition: () -> Bool
    ) async throws -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        return condition()
    }

    // MARK: - Layout

    func testLoadingInstallsTheListBesideTheEditor() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        XCTAssertEqual(split.splitViewItems.count, 4)
        XCTAssertTrue(split.splitView.isVertical, "the panes sit side by side, not stacked")
    }

    /// The layout Task 6 added: folders, list, editor, help, in that order.
    func testTheFourPanesAreInTheStatedOrder() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        XCTAssertEqual(split.splitViewItems.count, 4)
        XCTAssertTrue(split.splitViewItems[0].viewController is NotesFolderListViewController)
        XCTAssertTrue(split.splitViewItems[1].viewController is NotesListViewController)
        XCTAssertTrue(split.splitViewItems[2].viewController is NoteEditorViewController)
        XCTAssertTrue(split.splitViewItems[3].viewController is MarkdownViewerController)
    }

    /// AppKit keys divider positions globally, so two notes panes alive at once
    /// under one name overwrite each other's.
    func testTheAutosaveNameIsTheCallersToChoose() {
        let first = makeSplit(autosaveName: "notes-a")
        let second = makeSplit(autosaveName: "notes-b")
        first.loadViewIfNeeded()
        second.loadViewIfNeeded()

        XCTAssertEqual(first.splitView.autosaveName, "notes-a")
        XCTAssertNotEqual(first.splitView.autosaveName, second.splitView.autosaveName)
    }

    /// The list keeps the width it was given and the editor takes the slack.
    /// With equal priorities both panes share every resize, and a restored width
    /// is scaled away as the pane grows into place.
    func testTheListHoldsItsWidthAgainstTheEditor() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        XCTAssertGreaterThan(
            split.splitViewItems[1].holdingPriority.rawValue,
            split.splitViewItems[2].holdingPriority.rawValue
        )
    }

    /// The regression: a name assigned to a split view with no items yet
    /// restores nothing, and AppKit never tries again — the pane reopened at
    /// whatever the constraints produced, not at the width it was left at.
    func testASavedDividerPositionIsRestoredWhenThePaneOpens() {
        let name = makeAutosaveName()
        seedDividerPosition(listWidth: 220, totalWidth: 969, name: name)

        let split = makeSplit(autosaveName: name)
        split.loadViewIfNeeded()

        XCTAssertEqual(split.splitView.subviews[1].frame.width, 220, accuracy: 1)
    }

    /// Nothing saved is the one case where a hard-coded width is right; applying
    /// it unconditionally is what used to overwrite the restored position.
    func testAPaneNobodyHasSizedOpensAtTheDefaultWidth() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        XCTAssertEqual(split.splitView.subviews[1].frame.width, 240, accuracy: 1)
    }

    /// task-6-grounding G1: the seeded array has to have one entry per split
    /// item or AppKit's restore and the split view's actual subview count
    /// disagree — exactly the invariant that broke when folders and help were
    /// added to a seed still sized for two panes.
    func testTheSeededDividerArrayHasOneEntryPerSplitItem() {
        let name = makeAutosaveName()
        let split = makeSplit(autosaveName: name)

        split.loadViewIfNeeded()

        let seeded = UserDefaults.standard.array(forKey: "NSSplitView Subview Frames \(name)") as? [String]
        XCTAssertEqual(seeded?.count, split.splitViewItems.count)
    }

    // MARK: - Folders pane visibility

    func testToggleFoldersFlipsTheFolderItemsCollapsedState() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        let before = split.splitViewItems[0].isCollapsed

        split.toggleFolders()

        XCTAssertNotEqual(split.splitViewItems[0].isCollapsed, before)
    }

    // MARK: - Help pane visibility

    func testHelpPaneStartsCollapsed() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        XCTAssertFalse(split.isHelpVisible)
        XCTAssertTrue(split.splitViewItems[3].isCollapsed)
    }

    func testToggleHelpFlipsIsCollapsed() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        split.toggleHelp()
        XCTAssertTrue(split.isHelpVisible)

        split.toggleHelp()
        XCTAssertFalse(split.isHelpVisible)
    }

    // MARK: - Folder filtering (task-6-grounding G8/G9)

    func testSelectingAFolderNarrowsTheList() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let inFolder = try store.createDocument(content: "a recipe", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: inFolder.id)
        _ = try store.createDocument(content: "unfiled", markers: [.note])

        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        split.reload()
        XCTAssertEqual(listRowCount(split), 2, "unfiltered — All Notes is selected by default")

        let folderVC = try XCTUnwrap(split.splitViewItems[0].viewController as? NotesFolderListViewController)
        let row = try XCTUnwrap((0..<folderVC.outline.numberOfRows).first {
            (folderVC.outline.item(atRow: $0) as? NoteFolder)?.id == recipes.id
        })
        folderVC.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        XCTAssertEqual(listRowCount(split), 1)
    }

    func testSelectingAllNotesRestoresTheFullList() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let inFolder = try store.createDocument(content: "a recipe", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: inFolder.id)
        _ = try store.createDocument(content: "unfiled", markers: [.note])

        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        split.reload()

        let folderVC = try XCTUnwrap(split.splitViewItems[0].viewController as? NotesFolderListViewController)
        let recipesRow = try XCTUnwrap((0..<folderVC.outline.numberOfRows).first {
            (folderVC.outline.item(atRow: $0) as? NoteFolder)?.id == recipes.id
        })
        folderVC.outline.selectRowIndexes(IndexSet(integer: recipesRow), byExtendingSelection: false)
        XCTAssertEqual(listRowCount(split), 1)

        folderVC.outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        XCTAssertEqual(listRowCount(split), 2)
    }

    /// task-8-grounding G10 (Ruling 39) — supersedes the earlier
    /// task-7-grounding G8, Test 1 pin. Apple Notes, the reference for this
    /// whole rework, creates a new note *inside* the selected folder rather
    /// than leaving it unfiled and hidden from the very list the user is
    /// looking at. `notesListDidRequestNewNote()` now files the note under
    /// `selectedFolderID` (when one is selected) before reloading, so the
    /// filtered list settles at 2 — the pre-existing "a recipe" plus the new
    /// note — and the new note is a member of the Recipes folder.
    ///
    /// The manager-count assertion at 3 still distinguishes this from the
    /// historical regression, where `notesListDidRequestNewNote()` reloaded
    /// from *all* notes and dropped the folder filter entirely — that bug
    /// would also have settled the filtered list at the unfiltered total, not
    /// specifically at 2.
    func testANewNoteCreatedInAFilteredFolderJoinsThatFolder() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let inFolder = try store.createDocument(content: "a recipe", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: inFolder.id)
        _ = try store.createDocument(content: "unfiled", markers: [.note])

        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        split.reload()

        let folderVC = try XCTUnwrap(split.splitViewItems[0].viewController as? NotesFolderListViewController)
        let row = try XCTUnwrap((0..<folderVC.outline.numberOfRows).first {
            (folderVC.outline.item(atRow: $0) as? NoteFolder)?.id == recipes.id
        })
        folderVC.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        XCTAssertEqual(listRowCount(split), 1)

        split.notesListDidRequestNewNote()

        let settled = try await pollUntil { listRowCount(split) == 2 }
        XCTAssertTrue(settled, "expected the new note to join the selected folder and appear in the filtered list")
        XCTAssertEqual(notesManager.notes.count, 3, "expected the new note to actually be created")

        let newNote = try XCTUnwrap(notesManager.notes.first { $0.content.isEmpty })
        let categories = try store.categories(forDocument: newNote.id.uuidString.lowercased())
        XCTAssertTrue(
            categories.contains { $0.id == recipes.id },
            "the new note must be a member of the folder it was created in")
    }

    // MARK: - The ⋯ menu's actions (Task 8)

    /// Selects the store's first (and only) note by loading it into the
    /// list pane, the same shortcut `NotesWindowToolbarTests.
    /// makeSplitWithASelectedNote()` uses — `selectedNote()` reads the id
    /// back off `listVC.selectedNoteID`, so a note has to actually be
    /// "selected" through the list pane rather than just existing in the
    /// manager. Returns the manager too: it is `private` on the controller,
    /// so a test that needs to observe the mutation itself (not just
    /// `selectedNote()`, which only sees whichever note the list still has
    /// selected) has to hold its own reference.
    private func makeSplitWithASelectedNote(
        store: MarkdownStore
    ) async throws -> (split: NotesSplitViewController, note: Note, notesManager: NotesManager) {
        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        let note = try XCTUnwrap(notesManager.notes.first)
        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        listVC.reload(notes: notesManager.notes, keepingSelectedID: note.id)
        return (split, note, notesManager)
    }

    func testTogglePinOnSelectedNoteFlipsThePinnedFlag() async throws {
        let store = try store()
        _ = try store.createDocument(content: "hello", markers: [.note])
        let (split, note, _) = try await makeSplitWithASelectedNote(store: store)
        XCTAssertFalse(note.isPinned)

        split.togglePinOnSelectedNote()

        let pinned = try await pollUntil { split.selectedNote()?.isPinned == true }
        XCTAssertTrue(pinned)
    }

    func testTogglePinOnSelectedNoteDoesNothingWithNoSelection() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        split.togglePinOnSelectedNote() // must not crash
    }

    func testDuplicateSelectedNoteCreatesANoteWithIdenticalContent() async throws {
        let store = try store()
        _ = try store.createDocument(content: "hello world", markers: [.note])
        let (split, note, notesManager) = try await makeSplitWithASelectedNote(store: store)

        split.duplicateSelectedNote()

        let settled = try await pollUntil { notesManager.notes.count == 2 }
        XCTAssertTrue(settled)
        XCTAssertTrue(notesManager.notes.allSatisfy { $0.content == "hello world" })
        let duplicate = try XCTUnwrap(notesManager.notes.first { $0.id != note.id })
        XCTAssertNotEqual(duplicate.id, note.id, "the duplicate must be a distinct note")
    }

    /// Apple Notes keeps a duplicate in whatever folder the original was
    /// in — not spelled out in the brief's one-line "creates a new note with
    /// the same content," but leaving the duplicate unfiled reproduces
    /// exactly the surprise task-8-grounding G10 (Ruling 39) just closed for
    /// brand-new notes: a note the user is looking at (because it is in the
    /// filtered folder) that vanishes the moment it is duplicated.
    func testDuplicateSelectedNotePreservesFolderMembership() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let doc = try store.createDocument(content: "hello", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: doc.id)
        let (split, note, notesManager) = try await makeSplitWithASelectedNote(store: store)

        split.duplicateSelectedNote()

        let settled = try await pollUntil { notesManager.notes.count == 2 }
        XCTAssertTrue(settled)
        let duplicate = try XCTUnwrap(notesManager.notes.first { $0.id != note.id })
        let categories = try store.categories(forDocument: duplicate.id.uuidString.lowercased())
        XCTAssertTrue(categories.contains { $0.id == recipes.id })
    }

    func testMoveSelectedNoteAssignsTheGivenFolder() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let doc = try store.createDocument(content: "hello", markers: [.note])
        let (split, _, _) = try await makeSplitWithASelectedNote(store: store)

        split.moveSelectedNote(toFolder: recipes.id)

        let settled = try await pollUntil {
            (try? store.categories(forDocument: doc.id).contains { $0.id == recipes.id }) == true
        }
        XCTAssertTrue(settled)
    }

    /// task-8-grounding G5: picking an already-checked folder unassigns it —
    /// "Move to" reassigns rather than enforcing single membership, and this
    /// is the toggle-off half of that.
    func testMoveSelectedNoteTogglesOffAnAlreadyAssignedFolder() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let doc = try store.createDocument(content: "hello", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: doc.id)
        let (split, _, _) = try await makeSplitWithASelectedNote(store: store)

        split.moveSelectedNote(toFolder: recipes.id)

        let settled = try await pollUntil {
            (try? store.categories(forDocument: doc.id).isEmpty) == true
        }
        XCTAssertTrue(settled)
    }

    /// task-8-grounding G5: "'None' unassigns every current category."
    func testMoveSelectedNoteToNoneUnassignsEveryFolder() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let chores = try store.createCategory(name: "Chores")
        let doc = try store.createDocument(content: "hello", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: doc.id)
        try store.assignCategory(chores.id, toDocument: doc.id)
        let (split, _, _) = try await makeSplitWithASelectedNote(store: store)

        split.moveSelectedNote(toFolder: "")

        let settled = try await pollUntil {
            (try? store.categories(forDocument: doc.id).isEmpty) == true
        }
        XCTAssertTrue(settled)
    }

    /// The underlying mutation, called directly the same way
    /// `NotesFolderListViewControllerTests` calls `deleteFolder(_:)` directly
    /// rather than driving `presentDeleteConfirmation(for:)`'s sheet — an
    /// `NSAlert` sheet cannot be answered from a headless XCTest run.
    /// `deleteSelectedNote()` itself is covered below for its no-window guard.
    func testPerformDeleteRemovesTheNote() async throws {
        let store = try store()
        _ = try store.createDocument(content: "hello", markers: [.note])
        let (split, note, notesManager) = try await makeSplitWithASelectedNote(store: store)

        split.performDelete(note)

        let settled = try await pollUntil { notesManager.notes.isEmpty }
        XCTAssertTrue(settled)
    }

    /// task-8-grounding G3/G9's recovered guard: `guard let window =
    /// view.window else { return }`, checked *before* the alert — a delete
    /// requested with no window silently does nothing rather than trapping.
    func testDeleteSelectedNoteWithNoWindowDoesNothing() async throws {
        let store = try store()
        _ = try store.createDocument(content: "hello", markers: [.note])
        let (split, _, notesManager) = try await makeSplitWithASelectedNote(store: store)

        split.deleteSelectedNote()

        XCTAssertEqual(notesManager.notes.count, 1, "no window means no sheet, and no deletion")
    }

    func testShareSelectedNoteDoesNothingWithNoSelection() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        split.shareSelectedNote(from: split.view) // must not crash
    }

    /// `focusEditor()`'s own test (ADT's `MarkdownTextPaneInputTests`) already
    /// pins that it reaches a real `NSTextView`; this pins that
    /// `findInNote()` actually calls it, which needs a real window because
    /// `NSView.window?.makeFirstResponder(_:)` is a no-op off screen.
    func testFindInNoteMakesTheEditorsTextViewFirstResponder() async throws {
        let store = try store()
        _ = try store.createDocument(content: "hello", markers: [.note])
        let (split, _, _) = try await makeSplitWithASelectedNote(store: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = split
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()

        split.findInNote()

        XCTAssertTrue(window.firstResponder is NSTextView)
    }

    // MARK: - Help pane persistence (task-7-grounding G8, Test 2)

    /// `UserSettings.notesHelpVisible` is written by `toggleHelp()` and re-read
    /// in `viewDidLoad` after the autosave frame restore. A fresh controller
    /// with a new autosave name is a faithful stand-in for a relaunch — reusing
    /// the first name would let the restored frame array, not the setting,
    /// explain a pass.
    func testHelpPanesExpandedStateSurvivesARelaunch() {
        let split = makeSplit(autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        XCTAssertFalse(split.isHelpVisible)

        split.toggleHelp()

        let relaunched = makeSplit(autosaveName: makeAutosaveName())
        relaunched.loadViewIfNeeded()

        XCTAssertTrue(relaunched.isHelpVisible)
    }

    // MARK: - Fix round 1 (task-8 fix brief): folder counts staying fresh

    /// Fix 1: `duplicateSelectedNote()` used to leave the folder pane's counts
    /// stale — asserting the exact filtered count (not just "more than
    /// before") is what pins the bug rather than passing against it.
    func testDuplicateSelectedNoteRefreshesTheFilteredList() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let doc = try store.createDocument(content: "a recipe", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: doc.id)

        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        split.reload()

        let folderVC = try XCTUnwrap(split.splitViewItems[0].viewController as? NotesFolderListViewController)
        let row = try XCTUnwrap((0..<folderVC.outline.numberOfRows).first {
            (folderVC.outline.item(atRow: $0) as? NoteFolder)?.id == recipes.id
        })
        folderVC.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        XCTAssertEqual(listRowCount(split), 1)

        // `selectedNote()` reads off `listVC.selectedNoteID`, so the note being
        // duplicated has to actually be selected through the list pane.
        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        let original = try XCTUnwrap(notesManager.notes.first)
        listVC.reload(notes: notesManager.notes, keepingSelectedID: original.id)

        split.duplicateSelectedNote()

        let settled = try await pollUntil { listRowCount(split) == 2 }
        XCTAssertTrue(settled, "expected the folder pane's filtered list to settle at exactly 2")
        let duplicate = try XCTUnwrap(notesManager.notes.first { $0.id != original.id })
        let categories = try store.categories(forDocument: duplicate.id.uuidString.lowercased())
        XCTAssertTrue(categories.contains { $0.id == recipes.id })
    }

    /// Fix 1: `moveSelectedNote(toFolder:)` used to leave the filtered list
    /// showing a note that had just left the selected folder.
    func testMoveSelectedNoteRefreshesTheFilteredList() async throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let doc = try store.createDocument(content: "a recipe", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: doc.id)

        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        split.reload()

        let folderVC = try XCTUnwrap(split.splitViewItems[0].viewController as? NotesFolderListViewController)
        let row = try XCTUnwrap((0..<folderVC.outline.numberOfRows).first {
            (folderVC.outline.item(atRow: $0) as? NoteFolder)?.id == recipes.id
        })
        folderVC.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        XCTAssertEqual(listRowCount(split), 1)

        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        let note = try XCTUnwrap(notesManager.notes.first { $0.id.uuidString.lowercased() == doc.id })
        listVC.reload(notes: notesManager.notes, keepingSelectedID: note.id)

        split.moveSelectedNote(toFolder: "")

        let settled = try await pollUntil { listRowCount(split) == 0 }
        XCTAssertTrue(settled, "expected the note that just left the folder to drop out of the filtered list")
    }

    /// Fix 3: a selection the user made during `performDelete(_:)`'s `await`
    /// must survive — the delete used to blank the selection and the editor
    /// unconditionally, discarding whatever the user had moved on to.
    func testPerformDeleteKeepsASelectionMadeDuringTheAwait() async throws {
        let store = try store()
        _ = try store.createDocument(content: "to be deleted", markers: [.note])
        let keptDoc = try store.createDocument(content: "kept", markers: [.note])

        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()

        let toDelete = try XCTUnwrap(notesManager.notes.first { $0.content == "to be deleted" })
        let kept = try XCTUnwrap(notesManager.notes.first { $0.id.uuidString.lowercased() == keptDoc.id })
        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        // The user's selection at the moment of delete is the note that stays,
        // not the one being deleted — the race Fix 3 covers.
        listVC.reload(notes: notesManager.notes, keepingSelectedID: kept.id)

        split.performDelete(toDelete)

        let settled = try await pollUntil { notesManager.notes.count == 1 }
        XCTAssertTrue(settled)
        XCTAssertEqual(listVC.selectedNoteID, kept.id, "the user's selection must survive the delete")
    }
}
