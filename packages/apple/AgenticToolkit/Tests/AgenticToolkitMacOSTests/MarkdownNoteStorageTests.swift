import Testing
import Foundation
import GRDB
import AgenticToolkitMarkdown
@testable import AgenticToolkitMacOS

@Suite("MarkdownNoteStorage")
struct MarkdownNoteStorageTests {

    private func storage() throws -> MarkdownNoteStorage {
        MarkdownNoteStorage(store: try MarkdownStore(path: ":memory:", customerID: "cust-1"))
    }

    private func note(title: String, content: String, isPinned: Bool = false) -> Note {
        Note(id: UUID(), title: title, content: content,
             createdDate: Date(), modifiedDate: Date(), isPinned: isPinned)
    }

    @Test("an inserted note comes back")
    func insertRoundTrips() throws {
        let storage = try storage()
        let note = note(title: "Groceries", content: "# Groceries\n\nMilk")
        try storage.insertNote(note)
        let loaded = try #require(try storage.fetchAllNotes().first)
        #expect(loaded.id == note.id)
        #expect(loaded.title == "Groceries")
        #expect(loaded.content == "# Groceries\n\nMilk")
    }

    @Test("a title matching the content's own carries no frontmatter")
    func derivedTitleIsNotStored() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Groceries", content: "# Groceries\n\nMilk"))
        let document = try #require(try storage.store.documents(marker: .note).first)
        #expect(document.frontmatter.isEmpty)
        #expect(document.content == "# Groceries\n\nMilk")
    }

    @Test("a renamed note stores its title in frontmatter and reads it back")
    func renamedTitleRoundTrips() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Shopping", content: "# Groceries\n\nMilk"))
        let document = try #require(try storage.store.documents(marker: .note).first)
        #expect(document.frontmatter["title"] == "Shopping")
        #expect(try storage.fetchAllNotes().first?.title == "Shopping")
    }

    @Test("renaming a note back to its derived title clears the key")
    func renamingBackClearsTheKey() throws {
        let storage = try storage()
        var note = note(title: "Shopping", content: "# Groceries\n\nMilk")
        try storage.insertNote(note)
        note.title = "Groceries"
        try storage.updateNote(note)
        let document = try #require(try storage.store.documents(marker: .note).first)
        #expect(document.frontmatter["title"] == nil)
        #expect(try storage.fetchAllNotes().first?.title == "Groceries")
    }

    @Test("a pin round-trips through frontmatter")
    func pinRoundTrips() throws {
        let storage = try storage()
        var note = note(title: "Groceries", content: "# Groceries\n\nMilk")
        try storage.insertNote(note)
        #expect(try storage.fetchAllNotes().first?.isPinned == false)
        note.isPinned = true
        try storage.updateNote(note)
        #expect(try storage.fetchAllNotes().first?.isPinned == true)
        note.isPinned = false
        try storage.updateNote(note)
        #expect(try storage.fetchAllNotes().first?.isPinned == false)
        #expect(try storage.store.documents(marker: .note).first?.frontmatter.isEmpty == true)
    }

    @Test("an untitled note gets the fallback title, not an empty one")
    func blankTitleFallsBack() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "", content: ""))
        #expect(try storage.fetchAllNotes().first?.title == MarkdownText.untitled)
    }

    @Test("editing content updates it and leaves the frontmatter alone")
    func updateChangesContent() throws {
        let storage = try storage()
        var note = note(title: "Shopping", content: "# Groceries\n\nMilk")
        try storage.insertNote(note)
        note.content = "# Groceries\n\nMilk\nBread"
        try storage.updateNote(note)
        let loaded = try #require(try storage.fetchAllNotes().first)
        #expect(loaded.content == "# Groceries\n\nMilk\nBread")
        #expect(loaded.title == "Shopping")
    }

    @Test("a deleted note is gone from the list")
    func deleteRemovesTheNote() throws {
        let storage = try storage()
        let note = note(title: "Groceries", content: "Milk")
        try storage.insertNote(note)
        try storage.deleteNote(id: note.id)
        #expect(try storage.fetchAllNotes().isEmpty)
    }

    @Test("notes come back pinned-first, newest-first — the app's own sort")
    func listingOrderMatchesDefaultSort() throws {
        let storage = try storage()
        let older = Note(id: UUID(), title: "Older", content: "a",
                         createdDate: Date(timeIntervalSince1970: 1),
                         modifiedDate: Date(timeIntervalSince1970: 1), isPinned: false)
        let newer = Note(id: UUID(), title: "Newer", content: "b",
                         createdDate: Date(timeIntervalSince1970: 2),
                         modifiedDate: Date(timeIntervalSince1970: 2), isPinned: false)
        var pinned = Note(id: UUID(), title: "Pinned", content: "c",
                          createdDate: Date(timeIntervalSince1970: 0),
                          modifiedDate: Date(timeIntervalSince1970: 0), isPinned: false)
        for note in [older, newer, pinned] { try storage.insertNote(note) }
        pinned.isPinned = true
        try storage.updateNote(pinned)
        #expect(try storage.fetchAllNotes().map(\.title) == ["Pinned", "Newer", "Older"])
    }

    @Test("updating a note that is not there says so")
    func updateOfMissingNoteThrows() throws {
        let storage = try storage()
        #expect(throws: (any Error).self) {
            try storage.updateNote(note(title: "Ghost", content: ""))
        }
    }

    @Test("every note write queues a REST intent")
    func writesReachTheOutbox() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Groceries", content: "Milk"))
        let queued = try storage.store.pendingRemoteOps(limit: 10)
        #expect(queued.count == 1)
        #expect(queued[0].intent == .create)
        #expect(queued[0].payload["note"] == .bool(true))
    }

    @Test("a document with a non-UUID id is skipped rather than crashing the list")
    func serverIdsAreSkipped() throws {
        let storage = try storage()
        _ = try storage.store.createDocument(content: "from the server", markers: [.note])
        try storage.store.database.write { conn in
            // `notes.markdown_id` is `ON UPDATE RESTRICT` against `markdown.id`
            // (MarkdownSchema.swift) — updating the parent's own key while a
            // child row still points at the old value trips that RESTRICT
            // immediately, even mid-transaction. Deferring, exactly as
            // `MarkdownProjection.truncate` does for the same reason, lets
            // both statements land before the constraint is checked at commit.
            try conn.execute(sql: "PRAGMA defer_foreign_keys = ON")
            try conn.execute(sql: "UPDATE markdown SET id = 'srv_1'")
            try conn.execute(sql: "UPDATE notes SET markdown_id = 'srv_1'")
        }
        #expect(try storage.fetchAllNotes().isEmpty)
    }
}
