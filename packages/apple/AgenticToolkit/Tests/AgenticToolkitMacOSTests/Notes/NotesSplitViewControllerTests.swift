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
}
