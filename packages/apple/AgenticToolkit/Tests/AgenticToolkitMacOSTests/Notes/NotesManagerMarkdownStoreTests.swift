import AppKit
import XCTest
import AgenticToolkitMarkdown
@testable import AgenticToolkitMacOS

/// `NotesManager.markdownStore` is the seam the folders pane reaches through
/// to get at a `MarkdownStore` — see `NoteTaxonomyProviding`. A future
/// refactor that quietly severs the chain (a new `NoteStorage` that does not
/// conform, or `NotesManager` losing the accessor) should fail a test, not
/// leave the folders pane silently and permanently empty.
@MainActor
final class NotesManagerMarkdownStoreTests: XCTestCase {

    /// Does not conform to `NoteTaxonomyProviding` — a host that is not
    /// backed by a `MarkdownStore`.
    private struct EmptyNoteStorage: NoteStorage {
        func fetchAllNotes() throws -> [Note] { [] }
        func insertNote(_ note: Note) throws {}
        func updateNote(_ note: Note) throws {}
        func deleteNote(id: UUID) throws {}
    }

    func testReturnsNilWhenStorageDoesNotConformToNoteTaxonomyProviding() {
        let manager = NotesManager(storage: EmptyNoteStorage())
        XCTAssertNil(manager.markdownStore)
    }

    func testReturnsTheStoreWhenStorageIsMarkdownBacked() throws {
        let store = try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
        let manager = NotesManager(storage: MarkdownNoteStorage(store: store))
        XCTAssertTrue(manager.markdownStore === store)
    }
}
