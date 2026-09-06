import AppKit
import XCTest
import AgenticToolkitCore
import AgenticToolkitMarkdown
@testable import AgenticToolkitMacOS

/// Pins the Notes window's titlebar toolbar (task 7): the exact item order,
/// that every button's accessibility identifier equals its toolbar identifier
/// string (task-7-grounding G7 — Task 11's Whippet UI suite reaches these
/// controls that way), that search is a real `NSSearchToolbarItem` (G6), and
/// that share/`⋯` enablement answers a real question instead of sitting
/// permanently `true` (G5) — checked here as `NSButton.isEnabled` on each
/// item's custom view, since AppKit never runs `NSToolbarItemValidation`
/// against a custom-view item (see `NotesWindowToolbar`'s doc comment).
@MainActor
final class NotesWindowToolbarTests: XCTestCase {

    private struct EmptyNoteStorage: NoteStorage {
        func fetchAllNotes() throws -> [Note] { [] }
        func insertNote(_ note: Note) throws {}
        func updateNote(_ note: Note) throws {}
        func deleteNote(id: UUID) throws {}
    }

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

    private func makeAutosaveName() -> String {
        let name = "notes-toolbar-tests-\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(name)")
        }
        return name
    }

    /// A real, in-memory `MarkdownStore` — not `nil` — because
    /// `NotesFolderListViewController.createFolder(under:)` has a
    /// `guard let store else { return }` as its very first line. A `nil`
    /// store makes the new-folder button a silent no-op, which is exactly
    /// what `testNewFolderButtonRequestsAFolderUnderTheSelection` below
    /// exercises.
    private func makeSplit() throws -> NotesSplitViewController {
        let store = try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
        let split = NotesSplitViewController(
            notesManager: NotesManager(storage: EmptyNoteStorage()),
            markdownStore: store,
            autosaveName: makeAutosaveName()
        )
        split.loadViewIfNeeded()
        return split
    }

    /// A note the list has actually selected, so `selectedNote()` answers
    /// non-nil the way it would with a real click. `selectedNote()` looks the
    /// id up in `notesManager.notes` (not the list's own copy), so the note
    /// has to come from a real, loaded manager rather than a hand-built one.
    private func makeSplitWithASelectedNote() async throws -> NotesSplitViewController {
        let store = try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
        _ = try store.createDocument(content: "a note", markers: [.note])
        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        let note = try XCTUnwrap(notesManager.notes.first)
        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        listVC.reload(notes: notesManager.notes, keepingSelectedID: note.id)
        return split
    }

    private func dummyToolbar() -> NSToolbar {
        NSToolbar(identifier: "notes-window-toolbar-tests")
    }

    private func item(
        _ toolbar: NotesWindowToolbar,
        for identifier: String
    ) throws -> NSToolbarItem {
        try XCTUnwrap(toolbar.toolbar(
            dummyToolbar(),
            itemForItemIdentifier: NSToolbarItem.Identifier(identifier),
            willBeInsertedIntoToolbar: true
        ))
    }

    /// Every button item's control lives at `item.view`, not on the item
    /// itself — see `NotesWindowToolbar`'s doc comment for why.
    private func button(_ toolbar: NotesWindowToolbar, for identifier: String) throws -> NSButton {
        try XCTUnwrap(try item(toolbar, for: identifier).view as? NSButton)
    }

    // MARK: - Item order (task-7 spec §3)

    func testDefaultAndAllowedItemIdentifiersMatchTheSpecOrder() throws {
        let toolbar = NotesWindowToolbar(splitViewController: try makeSplit())
        let expected: [NSToolbarItem.Identifier] = [
            NSToolbarItem.Identifier("notes.toolbar.toggle-folders"),
            NSToolbarItem.Identifier("notes.toolbar.new-folder"),
            NSToolbarItem.Identifier("notes.toolbar.compose"),
            NSToolbarItem.Identifier("notes.toolbar.share"),
            NSToolbarItem.Identifier("notes.toolbar.more"),
            .flexibleSpace,
            NSToolbarItem.Identifier("notes.toolbar.search"),
            NSToolbarItem.Identifier("notes.toolbar.help")
        ]

        XCTAssertEqual(toolbar.toolbarDefaultItemIdentifiers(dummyToolbar()), expected)
        XCTAssertEqual(toolbar.toolbarAllowedItemIdentifiers(dummyToolbar()), expected)
    }

    // MARK: - Accessibility identifiers (task-7-grounding G7)

    func testEveryButtonsAccessibilityIdentifierEqualsItsToolbarIdentifier() throws {
        let toolbar = NotesWindowToolbar(splitViewController: try makeSplit())
        let identifiers = [
            "notes.toolbar.toggle-folders",
            "notes.toolbar.new-folder",
            "notes.toolbar.compose",
            "notes.toolbar.share",
            "notes.toolbar.more",
            "notes.toolbar.help"
        ]

        for identifier in identifiers {
            let built = try button(toolbar, for: identifier)
            XCTAssertEqual(
                built.accessibilityIdentifier(), identifier,
                "\(identifier)'s accessibility identifier must equal its toolbar identifier")
        }
    }

    func testSearchFieldsAccessibilityIdentifierEqualsItsToolbarIdentifier() throws {
        let toolbar = NotesWindowToolbar(splitViewController: try makeSplit())
        let searchItem = try XCTUnwrap(item(toolbar, for: "notes.toolbar.search") as? NSSearchToolbarItem)

        XCTAssertEqual(searchItem.searchField.accessibilityIdentifier(), "notes.toolbar.search")
    }

    // MARK: - Search (task-7-grounding G6)

    func testSearchItemIsARealSearchToolbarItem() throws {
        let toolbar = NotesWindowToolbar(splitViewController: try makeSplit())

        let built = try item(toolbar, for: "notes.toolbar.search")

        XCTAssertTrue(
            built is NSSearchToolbarItem,
            "search must be a real NSSearchToolbarItem, not an NSToolbarItem wrapping a plain field")
    }

    /// Text typed in the search field must reach the list pane's own filter —
    /// the search field forwards through `NSSearchFieldDelegate`, not through
    /// a target/action a validation cycle would otherwise drive.
    func testSearchFieldTextForwardsToTheSplitViewController() throws {
        let split = try makeSplit()
        let toolbar = NotesWindowToolbar(splitViewController: split)
        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        let notes = [Note.new(content: "apple pie"), Note.new(content: "banana bread")]
        listVC.reload(notes: notes, keepingSelectedID: nil)
        XCTAssertEqual(listVC.numberOfRows(in: NSTableView()), 2)

        let searchItem = try XCTUnwrap(item(toolbar, for: "notes.toolbar.search") as? NSSearchToolbarItem)
        searchItem.searchField.stringValue = "apple"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification, object: searchItem.searchField)

        XCTAssertEqual(listVC.numberOfRows(in: NSTableView()), 1)
    }

    // MARK: - Enablement (task-7-grounding G5)

    func testShareAndMoreAreDisabledWithNoNoteSelected() throws {
        let toolbar = NotesWindowToolbar(splitViewController: try makeSplit())

        XCTAssertFalse(try button(toolbar, for: "notes.toolbar.share").isEnabled)
        XCTAssertFalse(try button(toolbar, for: "notes.toolbar.more").isEnabled)
    }

    func testShareAndMoreAreEnabledWithANoteSelected() async throws {
        let split = try await makeSplitWithASelectedNote()
        let toolbar = NotesWindowToolbar(splitViewController: split)

        XCTAssertTrue(try button(toolbar, for: "notes.toolbar.share").isEnabled)
        XCTAssertTrue(try button(toolbar, for: "notes.toolbar.more").isEnabled)
    }

    /// Selecting, then clearing, the selection must re-disable share/more —
    /// proving the toolbar re-checks itself rather than only ever enabling.
    func testShareAndMoreAreDisabledAgainAfterTheSelectionClears() async throws {
        let split = try await makeSplitWithASelectedNote()
        let toolbar = NotesWindowToolbar(splitViewController: split)
        let share = try button(toolbar, for: "notes.toolbar.share")
        XCTAssertTrue(share.isEnabled)

        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        listVC.reload(notes: [], keepingSelectedID: nil)

        XCTAssertFalse(share.isEnabled)
    }

    func testOtherButtonsAreAlwaysEnabled() throws {
        let toolbar = NotesWindowToolbar(splitViewController: try makeSplit())

        let always = [
            "notes.toolbar.toggle-folders", "notes.toolbar.new-folder", "notes.toolbar.compose", "notes.toolbar.help"
        ]
        for identifier in always {
            XCTAssertTrue(try button(toolbar, for: identifier).isEnabled, "\(identifier) should never be disabled")
        }
    }

    // MARK: - Help item appearance (task-7-grounding G3)

    func testHelpButtonTooltipTracksVisibility() throws {
        let split = try makeSplit()
        let toolbar = NotesWindowToolbar(splitViewController: split)
        let help = try button(toolbar, for: "notes.toolbar.help")

        XCTAssertEqual(help.toolTip, "Show Help")

        split.toggleHelp()

        XCTAssertEqual(help.toolTip, "Hide Help")
    }

    // MARK: - Action wiring

    func testToggleFoldersButtonTogglesTheFoldersPane() throws {
        let split = try makeSplit()
        let toolbar = NotesWindowToolbar(splitViewController: split)
        let built = try button(toolbar, for: "notes.toolbar.toggle-folders")
        let before = split.splitViewItems[0].isCollapsed

        built.performClick(nil)

        XCTAssertNotEqual(split.splitViewItems[0].isCollapsed, before)
    }

    func testHelpButtonTogglesTheHelpPane() throws {
        let split = try makeSplit()
        let toolbar = NotesWindowToolbar(splitViewController: split)
        let built = try button(toolbar, for: "notes.toolbar.help")

        XCTAssertFalse(split.isHelpVisible)
        built.performClick(nil)

        XCTAssertTrue(split.isHelpVisible)
    }

    func testNewFolderButtonRequestsAFolderUnderTheSelection() throws {
        let split = try makeSplit()
        let toolbar = NotesWindowToolbar(splitViewController: split)
        let folderVC = try XCTUnwrap(split.splitViewItems[0].viewController as? NotesFolderListViewController)
        let before = folderVC.outline.numberOfRows
        let built = try button(toolbar, for: "notes.toolbar.new-folder")

        built.performClick(nil)

        XCTAssertGreaterThan(folderVC.outline.numberOfRows, before)
    }

    // MARK: - The ⋯ menu (Task 8, spec §3)

    /// `notesListDidRequestNewNote()` used elsewhere fires an unstructured
    /// `Task`; several of these actions do too (task-8-grounding G4), so
    /// assertions against `NotesManager` state have to poll rather than
    /// assume one runloop turn is enough.
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

    func testMoreMenuTitlesAreInTheSpecOrder() async throws {
        let split = try await makeSplitWithASelectedNote()
        let toolbar = NotesWindowToolbar(splitViewController: split)

        let menu = toolbar.buildMoreMenu()

        XCTAssertEqual(menu.items.count, 7)
        XCTAssertEqual(menu.items[0].title, "Pin Note")
        XCTAssertEqual(menu.items[1].title, "Find in Note")
        XCTAssertEqual(menu.items[2].title, "Move to")
        XCTAssertEqual(menu.items[3].title, "Duplicate Note")
        XCTAssertEqual(menu.items[4].title, "Share…")
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, "Delete Note")
    }

    /// task-8-grounding G7: words, not a pin icon, and recomputed at open
    /// time rather than fixed at construction.
    func testPinItemTitleTracksTheSelectedNotesPinnedState() async throws {
        let split = try await makeSplitWithASelectedNote()
        let toolbar = NotesWindowToolbar(splitViewController: split)
        XCTAssertEqual(toolbar.buildMoreMenu().items[0].title, "Pin Note")

        split.togglePinOnSelectedNote()
        let pinned = try await pollUntil { split.selectedNote()?.isPinned == true }
        XCTAssertTrue(pinned)

        XCTAssertEqual(toolbar.buildMoreMenu().items[0].title, "Unpin Note")
    }

    func testEveryMoreMenuItemIsDisabledWithNoSelection() throws {
        let toolbar = NotesWindowToolbar(splitViewController: try makeSplit())

        let menu = toolbar.buildMoreMenu()

        for item in menu.items where !item.isSeparatorItem {
            XCTAssertFalse(item.isEnabled, "\(item.title) should be disabled with no note selected")
        }
    }

    func testEveryMoreMenuItemIsEnabledWithASelection() async throws {
        let split = try await makeSplitWithASelectedNote()
        let toolbar = NotesWindowToolbar(splitViewController: split)

        let menu = toolbar.buildMoreMenu()

        for item in menu.items where !item.isSeparatorItem {
            XCTAssertTrue(item.isEnabled, "\(item.title) should be enabled with a note selected")
        }
    }

    /// task-8-grounding G5: the folder tree plus "None", with a checkmark on
    /// every folder the selected note already belongs to.
    func testMoveToSubmenuListsNoneAndTheFolderTreeWithCurrentMembershipChecked() async throws {
        let store = try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
        let recipes = try store.createCategory(name: "Recipes")
        let doc = try store.createDocument(content: "a recipe", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: doc.id)
        let notesManager = NotesManager(storage: MarkdownNoteStorage(store: store))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: store, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        let note = try XCTUnwrap(notesManager.notes.first)
        listVC.reload(notes: notesManager.notes, keepingSelectedID: note.id)
        let toolbar = NotesWindowToolbar(splitViewController: split)

        let moveTo = try XCTUnwrap(toolbar.buildMoreMenu().items[2].submenu)

        XCTAssertEqual(moveTo.items[0].title, "None")
        XCTAssertEqual(moveTo.items[0].state, .off)
        let recipesItem = try XCTUnwrap(moveTo.items.first { $0.title == "Recipes" })
        XCTAssertEqual(recipesItem.state, .on)
    }

    /// task-8-grounding G5: "with no store the Move to submenu is disabled,
    /// not crashing." A note *is* selected here — this isolates the missing
    /// store as the reason, distinct from `testEveryMoreMenuItemIsDisabled
    /// WithNoSelection` above.
    private struct OneNoteStorage: NoteStorage {
        let note: Note
        func fetchAllNotes() throws -> [Note] { [note] }
        func insertNote(_ note: Note) throws {}
        func updateNote(_ note: Note) throws {}
        func deleteNote(id: UUID) throws {}
    }

    func testMoveToIsDisabledWithNoMarkdownStore() async throws {
        let note = Note.new(content: "hello")
        let notesManager = NotesManager(storage: OneNoteStorage(note: note))
        await notesManager.loadNotes()
        let split = NotesSplitViewController(
            notesManager: notesManager, markdownStore: nil, autosaveName: makeAutosaveName())
        split.loadViewIfNeeded()
        let listVC = try XCTUnwrap(split.splitViewItems[1].viewController as? NotesListViewController)
        listVC.reload(notes: notesManager.notes, keepingSelectedID: note.id)
        let toolbar = NotesWindowToolbar(splitViewController: split)

        let moveToItem = toolbar.buildMoreMenu().items[2]

        XCTAssertFalse(moveToItem.isEnabled)
    }
}
