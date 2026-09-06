import AppKit
import XCTest
import AgenticToolkitMarkdown
@testable import AgenticToolkitMacOS

@MainActor
final class NotesFolderListViewControllerTests: XCTestCase {

    private final class Spy: NotesFolderListViewControllerDelegate {
        var selected: [NoteFolder] = []
        var newFolderParents: [NoteFolder?] = []
        var deleted: [NoteFolder] = []
        var renamed: [(NoteFolder, String)] = []

        func notesFolderListDidSelect(_ folder: NoteFolder) { selected.append(folder) }
        func notesFolderListDidRequestNewFolder(under parent: NoteFolder?) { newFolderParents.append(parent) }
        func notesFolderListDidRequestDelete(_ folder: NoteFolder) { deleted.append(folder) }
        func notesFolderListDidRequestRename(_ folder: NoteFolder, to name: String) {
            renamed.append((folder, name))
        }
    }

    private func store() throws -> MarkdownStore {
        try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
    }

    // MARK: - No store

    func testInitWithNilStoreShowsOnlyAllNotesWithZeroCount() {
        let controller = NotesFolderListViewController(store: nil)
        _ = controller.view
        controller.reload()
        XCTAssertEqual(controller.outline.numberOfRows, 1)
        let item = controller.outline.item(atRow: 0) as? NoteFolder
        XCTAssertEqual(item?.isAllNotes, true)
        XCTAssertEqual(item?.noteCount, 0)
    }

    // MARK: - Reload / tree assembly

    func testReloadBuildsAllNotesPlusCategoryRoots() throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let work = try store.createCategory(name: "Work")
        let note = try store.createDocument(content: "hello", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: note.id)

        let controller = NotesFolderListViewController(store: store)
        _ = controller.view
        controller.reload()

        // All Notes + two roots, all expanded by default.
        XCTAssertEqual(controller.outline.numberOfRows, 3)
        let allNotes = controller.outline.item(atRow: 0) as? NoteFolder
        XCTAssertEqual(allNotes?.isAllNotes, true)
        XCTAssertEqual(allNotes?.noteCount, 1)

        let names = (0..<controller.outline.numberOfRows).compactMap {
            (controller.outline.item(atRow: $0) as? NoteFolder)?.name
        }
        XCTAssertTrue(names.contains("Recipes"))
        XCTAssertTrue(names.contains("Work"))
        _ = work
    }

    // MARK: - selectFolder(id:)

    func testSelectFolderSetsSelectedFolderIDWithoutNotifyingDelegate() throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()

        controller.selectFolder(id: recipes.id)

        XCTAssertEqual(controller.selectedFolderID, recipes.id)
        XCTAssertTrue(spy.selected.isEmpty)
    }

    // MARK: - Selecting a row notifies the delegate

    func testSelectingARowNotifiesDelegateWithTheFolder() throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()

        let row = (0..<controller.outline.numberOfRows).first {
            (controller.outline.item(atRow: $0) as? NoteFolder)?.id == recipes.id
        }
        let unwrappedRow = try XCTUnwrap(row)
        controller.outline.selectRowIndexes(IndexSet(integer: unwrappedRow), byExtendingSelection: false)

        XCTAssertEqual(spy.selected.last?.id, recipes.id)
    }

    func testSelectingAllNotesRowNotifiesDelegateWithAnAllNotesFolder() throws {
        let store = try store()
        _ = try store.createDocument(content: "hello", markers: [.note])
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()

        controller.outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        XCTAssertEqual(spy.selected.last?.isAllNotes, true)
        XCTAssertEqual(spy.selected.last?.noteCount, 1)
    }

    // MARK: - createFolder(under:)

    func testCreateFolderAtRootAddsACategoryAndNotifiesDelegate() throws {
        let store = try store()
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()

        controller.createFolder(under: nil)

        let categories = try store.categories()
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.name, "New Folder")
        XCTAssertEqual(spy.newFolderParents.count, 1)
        XCTAssertNil(spy.newFolderParents.first ?? nil)
        XCTAssertEqual(controller.selectedFolderID, categories.first?.id)
    }

    func testCreateFolderUnderAParentAddsAnEdge() throws {
        let store = try store()
        let parent = try store.createCategory(name: "Parent")
        let controller = NotesFolderListViewController(store: store)
        _ = controller.view
        controller.reload()
        let parentFolder = NoteFolder(id: parent.id, name: parent.name, noteCount: 0, children: [])

        controller.createFolder(under: parentFolder)

        let edges = try store.categoryEdges()
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges.first?.parent, parent.id)
    }

    func testCreateFolderUnderAllNotesCreatesARootFolder() throws {
        let store = try store()
        let controller = NotesFolderListViewController(store: store)
        _ = controller.view
        controller.reload()
        let allNotes = NoteFolder(id: "", name: "All Notes", noteCount: 0, children: [])

        controller.createFolder(under: allNotes)

        XCTAssertTrue(try store.categoryEdges().isEmpty)
    }

    // MARK: - renameFolder(_:to:)

    func testRenameFolderUpdatesTheStoreReloadsAndNotifiesDelegate() throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()
        let folder = NoteFolder(id: recipes.id, name: recipes.name, noteCount: 0, children: [])

        controller.renameFolder(folder, to: "Meals")

        let categories = try store.categories()
        XCTAssertEqual(categories.first?.name, "Meals")
        XCTAssertEqual(spy.renamed.count, 1)
        XCTAssertEqual(spy.renamed.first?.1, "Meals")
    }

    func testRenameFolderIgnoresAllNotes() throws {
        let store = try store()
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()
        let allNotes = NoteFolder(id: "", name: "All Notes", noteCount: 0, children: [])

        controller.renameFolder(allNotes, to: "Whatever")

        XCTAssertTrue(spy.renamed.isEmpty)
    }

    // MARK: - deleteFolder(_:)

    func testDeleteFolderRemovesFromStoreAndNotifiesDelegateWithoutDeletingNotes() throws {
        let store = try store()
        let recipes = try store.createCategory(name: "Recipes")
        let note = try store.createDocument(content: "hello", markers: [.note])
        try store.assignCategory(recipes.id, toDocument: note.id)
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()
        let folder = NoteFolder(id: recipes.id, name: recipes.name, noteCount: 1, children: [])

        controller.deleteFolder(folder)

        XCTAssertTrue(try store.categories().isEmpty)
        XCTAssertEqual(spy.deleted.count, 1)
        // The alert's whole point: the note document survives the folder's deletion.
        XCTAssertEqual(try store.documents(marker: .note).count, 1)
    }

    func testDeleteFolderIgnoresAllNotes() throws {
        let store = try store()
        let controller = NotesFolderListViewController(store: store)
        let spy = Spy()
        controller.delegate = spy
        _ = controller.view
        controller.reload()
        let allNotes = NoteFolder(id: "", name: "All Notes", noteCount: 0, children: [])

        controller.deleteFolder(allNotes)

        XCTAssertTrue(spy.deleted.isEmpty)
    }
}
