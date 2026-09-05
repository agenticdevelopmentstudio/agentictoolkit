import Testing
import Foundation
import AgenticToolkitMarkdown
@testable import AgenticToolkitMacOS

@Suite("MarkdownNoteStorage")
struct MarkdownNoteStorageTests {

    private func storage() throws -> MarkdownNoteStorage {
        MarkdownNoteStorage(
            store: try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1"))
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

    @Test("a note created the way the app creates it carries no frontmatter, even once it has a heading")
    func appCreatedNoteNeverGetsFrontmatter() throws {
        let storage = try storage()
        let note = Note.new(title: "", content: "")
        #expect(note.title == Note.untitledTitle)
        try storage.insertNote(note)
        let afterInsert = try #require(try storage.store.documents(marker: .note).first)
        #expect(afterInsert.frontmatter.isEmpty)

        var updated = note
        updated.content = "# Groceries\n\nMilk"
        try storage.updateNote(updated)
        let afterEdit = try #require(try storage.store.documents(marker: .note).first)
        #expect(afterEdit.frontmatter.isEmpty)
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
        // Sync-shaped: a real pull inserts a brand-new row already carrying
        // the server's id. Nothing in the system ever renames a local
        // primary key in place, so the fixture shouldn't either.
        _ = try storage.store.createDocument(content: "from the server", markers: [.note], id: "srv_1")
        #expect(try storage.fetchAllNotes().isEmpty)
    }

    @Test("a foreign frontmatter key survives a read, alongside our own")
    func foreignFrontmatterSurvivesRead() throws {
        let storage = try storage()
        _ = try storage.store.createDocument(
            content: "---\ntitle: Custom\nauthor: mike\n---\n# Groceries\n\nMilk",
            markers: [.note])
        let note = try #require(try storage.fetchAllNotes().first)
        // The title still reads out of the frontmatter, because that is where
        // `MarkdownText.deriveTitle` — and therefore adh — reads it from.
        #expect(note.title == "Custom")
        // But the fence stays in the editor. Stripping `title:` here used to be
        // unconditional, which meant a key the user typed vanished from view
        // and reappeared in a diff they never made.
        #expect(note.content == "---\ntitle: Custom\nauthor: mike\n---\n# Groceries\n\nMilk")
    }

    @Test("fetching and re-saving a note with foreign frontmatter, unchanged, is byte-stable")
    func foreignFrontmatterRoundTripIsByteStable() throws {
        let storage = try storage()
        let original = "---\ntitle: Custom\npinned: true\nauthor: mike\n---\n# Groceries\n\nMilk"
        _ = try storage.store.createDocument(content: original, markers: [.note])
        let note = try #require(try storage.fetchAllNotes().first)
        try storage.updateNote(note)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == original)
    }

    // MARK: - A user-typed owned key must never be silently deleted

    @Test("a user-typed title-only fence survives an update whose own title would otherwise clear the key")
    func userTypedTitleFenceSurvivesSave() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Groceries", content: "# Groceries\n\nMilk"))
        var updated = try #require(try storage.fetchAllNotes().first)
        // The app's title still matches the derived title, so storedTitle(for:)
        // wants to clear the key — but the user just hand-typed this fence, so
        // it must survive untouched.
        updated.content = "---\ntitle: My Doc\n---\n# Groceries\n\nMilk"
        try storage.updateNote(updated)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\ntitle: My Doc\n---\n# Groceries\n\nMilk")
    }

    @Test("a user-typed title fence with a foreign key survives an update that would otherwise clear the title")
    func userTypedTitleFenceWithForeignKeySurvivesSave() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Groceries", content: "# Groceries\n\nMilk"))
        var updated = try #require(try storage.fetchAllNotes().first)
        updated.content = "---\ntitle: My Doc\nauthor: mike\n---\n# Groceries\n\nMilk"
        try storage.updateNote(updated)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\ntitle: My Doc\nauthor: mike\n---\n# Groceries\n\nMilk")
    }

    @Test("a user-typed pinned-only fence survives an update whose own state would otherwise clear the key")
    func userTypedPinnedFenceSurvivesSave() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Groceries", content: "# Groceries\n\nMilk"))
        var updated = try #require(try storage.fetchAllNotes().first)
        // The app's own pin state stays false, so it would normally clear a
        // "pinned" key — but the user just hand-typed this one.
        updated.content = "---\npinned: true\n---\n# Groceries\n\nMilk"
        try storage.updateNote(updated)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\npinned: true\n---\n# Groceries\n\nMilk")
    }

    @Test("a user-typed pinned fence with a foreign key survives an update that would otherwise clear it")
    func userTypedPinnedFenceWithForeignKeySurvivesSave() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Groceries", content: "# Groceries\n\nMilk"))
        var updated = try #require(try storage.fetchAllNotes().first)
        updated.content = "---\npinned: true\nauthor: mike\n---\n# Groceries\n\nMilk"
        try storage.updateNote(updated)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\npinned: true\nauthor: mike\n---\n# Groceries\n\nMilk")
    }

    @Test("a user-typed title-only fence survives a create whose own (blank) title would otherwise clear the key")
    func userTypedTitleFenceSurvivesCreate() throws {
        let storage = try storage()
        let content = "---\ntitle: My Doc\n---\n# Groceries\n\nMilk"
        try storage.insertNote(note(title: "", content: content))
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == content)
        let read = try #require(try storage.fetchAllNotes().first)
        #expect(read.title == "My Doc")
        // Unclaimed on the way in, so unstripped on the way out.
        #expect(read.content == content)
    }

    @Test("a user-typed title fence with a foreign key survives a create that would otherwise clear the title")
    func userTypedTitleFenceWithForeignKeySurvivesCreate() throws {
        let storage = try storage()
        let content = "---\ntitle: My Doc\nauthor: mike\n---\n# Groceries\n\nMilk"
        try storage.insertNote(note(title: "", content: content))
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == content)
        let read = try #require(try storage.fetchAllNotes().first)
        #expect(read.title == "My Doc")
        #expect(read.content == content)
    }

    // MARK: - Ownership is what tells our key from the user's

    /// The item-3 regression, through the path the app actually takes: the UI
    /// re-reads the list after every write, so an unpin operates on a note that
    /// came back out of storage, not on the one that went in. While provenance
    /// was guessed from the value, the round-tripped `pinned: true` looked
    /// user-typed on the way back in and the unpin refused to clear it — the
    /// note stayed pinned forever, and no amount of clicking changed it.
    @Test("a pin set through storage can be cleared again after a reload")
    func unpinSurvivesAReload() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Groceries", content: "# Groceries\n\nMilk"))

        var pinned = try #require(try storage.fetchAllNotes().first)
        pinned.isPinned = true
        try storage.updateNote(pinned)

        var unpinned = try #require(try storage.fetchAllNotes().first)
        #expect(unpinned.isPinned)
        unpinned.isPinned = false
        try storage.updateNote(unpinned)

        let reloaded = try #require(try storage.fetchAllNotes().first)
        #expect(reloaded.isPinned == false)
        #expect(reloaded.content == "# Groceries\n\nMilk")
        #expect(try storage.store.documents(marker: .note).first?.frontmatter.isEmpty == true)
    }

    /// `pinned` is Hugo's and Jekyll's key as much as it is ours. A document
    /// pasted in from one of them is not a note the user pinned in this app,
    /// and must not jump to the top of their list.
    @Test("a pinned: true nobody here wrote does not pin the note")
    func foreignPinDoesNotPin() throws {
        let storage = try storage()
        _ = try storage.store.createDocument(
            content: "---\npinned: true\nlayout: post\n---\n# Groceries\n\nMilk",
            markers: [.note])
        let note = try #require(try storage.fetchAllNotes().first)
        #expect(note.isPinned == false)
        // And it is still on screen, unchanged, because it is the user's line.
        #expect(note.content.contains("pinned: true"))
    }

    /// Editing the body hands the whole text back to the user, ownership
    /// included: the app cannot claim to have written a key inside content it
    /// did not produce. What survives the edit survives because the user kept
    /// it there.
    @Test("editing the text releases every claim on the frontmatter in it")
    func editingTheTextReleasesOwnership() throws {
        let storage = try storage()
        try storage.insertNote(note(title: "Shopping", content: "# Groceries\n\nMilk"))
        #expect(try storage.store.documents(marker: .note).first?.frontmatter["title"] == "Shopping")

        // The user pastes over the whole document, keeping our key by hand.
        var edited = try #require(try storage.fetchAllNotes().first)
        edited.content = "---\ntitle: Shopping\n---\n# Groceries\n\nMilk\nBread"
        try storage.updateNote(edited)

        // Now a rename must leave that line alone rather than rewrite it.
        var renamed = try #require(try storage.fetchAllNotes().first)
        #expect(renamed.content == "---\ntitle: Shopping\n---\n# Groceries\n\nMilk\nBread")
        renamed.title = "Errands"
        try storage.updateNote(renamed)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\ntitle: Shopping\n---\n# Groceries\n\nMilk\nBread")
    }

    /// Item 2, end to end: a note nobody ever named, reloaded and then edited,
    /// still carries no frontmatter. While `Note.untitledTitle` and
    /// `MarkdownText.untitled` were two different strings, the reloaded note's
    /// title ("Untitled", from the document) matched neither test in
    /// `storedTitle(for:)`, so the app wrote `title: Untitled` into a document
    /// whose title was already exactly that.
    @Test("a never-named note stays frontmatter-free across a reload and an edit")
    func neverNamedNoteStaysClean() throws {
        let storage = try storage()
        try storage.insertNote(Note.new(title: "", content: ""))
        var reloaded = try #require(try storage.fetchAllNotes().first)
        #expect(reloaded.title == Note.untitledTitle)
        reloaded.content = "Milk"
        try storage.updateNote(reloaded)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.frontmatter.isEmpty)
        #expect(stored.content == "Milk")
    }

    @Test("the app's untitled sentinel and the markdown layer's are the same string")
    func untitledSentinelIsShared() {
        #expect(Note.untitledTitle == MarkdownText.untitled)
    }

    @Test("the \"pinned\" literal used for the user-typed-key check agrees with MarkdownDocument.isPinned")
    func pinnedLiteralAgreesWithIsPinned() throws {
        let storage = try storage()
        var document = try storage.store.createDocument(content: "# Groceries\n\nMilk", markers: [.note])
        #expect(Frontmatter.value("pinned", in: document.content) == nil)
        #expect(document.isPinned == false)
        document.setPinned(true)
        #expect(Frontmatter.value("pinned", in: document.content) != nil)
        #expect(document.isPinned == true)
    }
}
