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

    private func note(content: String, isPinned: Bool = false) -> Note {
        Note(id: UUID(), content: content,
             createdDate: Date(), modifiedDate: Date(), isPinned: isPinned)
    }

    @Test("an inserted note comes back")
    func insertRoundTrips() throws {
        let storage = try storage()
        let note = note(content: "# Groceries\n\nMilk")
        try storage.insertNote(note)
        let loaded = try #require(try storage.fetchAllNotes().first)
        #expect(loaded.id == note.id)
        #expect(loaded.title == "Groceries")
        #expect(loaded.content == "# Groceries\n\nMilk")
    }

    @Test("a title matching the content's own carries no frontmatter")
    func derivedTitleIsNotStored() throws {
        let storage = try storage()
        try storage.insertNote(note(content: "# Groceries\n\nMilk"))
        let document = try #require(try storage.store.documents(marker: .note).first)
        #expect(document.frontmatter.isEmpty)
        #expect(document.content == "# Groceries\n\nMilk")
    }

    @Test("a note created the way the app creates it carries no frontmatter, even once it has a heading")
    func appCreatedNoteNeverGetsFrontmatter() throws {
        let storage = try storage()
        let note = Note.new(content: "")
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

    /// `updateNote` is documented as doing its read, merge and write in one
    /// transaction. Nothing else here would notice if it went back to
    /// `document(id:)` + edit + `updateDocument(_:)`, because every other test
    /// drives it from one thread.
    ///
    /// `ownerID` is the probe precisely because `updateNote`'s merge never
    /// reads or writes it: the whole row is written back either way, so
    /// whether another writer's `ownerID` survives is purely a question of
    /// whether the read and the write are indivisible. The other writer
    /// *appends*, inside one transaction, so every one of its marks must
    /// survive; an `updateNote` that read before a mark and wrote after it
    /// erases that mark permanently, with no error. Asserting on the final
    /// value alone would not do — a split `updateNote` still ends on the
    /// right value whenever the last write to commit happens to be the other
    /// writer's.
    ///
    /// Content is deliberately not the probe. A concurrent content change
    /// *is* clobbered by a stale `Note` snapshot — atomically — and that is
    /// the documented last-writer-wins model, not a defect.
    @Test("updateNote's read-merge-write is one transaction, not three")
    func updateNoteIsAtomicAgainstAnotherWriter() async throws {
        let storage = try storage()
        let seed = note(content: "body")
        try storage.insertNote(seed)
        let id = seed.id.uuidString.lowercased()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                // A merge that changes nothing, and so writes back exactly
                // what it read — the purest form of the revert.
                group.addTask { try? storage.updateNote(seed) }
                group.addTask {
                    try? storage.store.mutateDocument(id: id) { document, _ in
                        document.ownerID += "|\(index)"
                    }
                }
            }
        }

        let document = try #require(try storage.store.document(id: id))
        for index in 0..<30 {
            #expect(document.ownerID.contains("|\(index)"),
                    "updateNote erased concurrent mark \(index) — its read and write are not one transaction")
        }
    }

    @Test("a pin round-trips through frontmatter")
    func pinRoundTrips() throws {
        let storage = try storage()
        var note = note(content: "# Groceries\n\nMilk")
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
        try storage.insertNote(note(content: ""))
        #expect(try storage.fetchAllNotes().first?.title == MarkdownText.untitled)
    }

    @Test("editing content updates it and leaves the frontmatter alone")
    func updateChangesContent() throws {
        let storage = try storage()
        var note = note(content: "# Groceries\n\nMilk")
        try storage.insertNote(note)
        note.content = "# Groceries\n\nMilk\nBread"
        try storage.updateNote(note)
        let loaded = try #require(try storage.fetchAllNotes().first)
        #expect(loaded.content == "# Groceries\n\nMilk\nBread")
        #expect(loaded.title == "Groceries")
    }

    @Test("a deleted note is gone from the list")
    func deleteRemovesTheNote() throws {
        let storage = try storage()
        let note = note(content: "Milk")
        try storage.insertNote(note)
        try storage.deleteNote(id: note.id)
        #expect(try storage.fetchAllNotes().isEmpty)
    }

    @Test("notes come back pinned-first, newest-first — the app's own sort")
    func listingOrderMatchesDefaultSort() throws {
        let storage = try storage()
        // The content itself is the identifying string, so the derived
        // titles below come out exactly as they used to when the title was
        // its own field.
        let older = Note(id: UUID(), content: "Older",
                         createdDate: Date(timeIntervalSince1970: 1),
                         modifiedDate: Date(timeIntervalSince1970: 1), isPinned: false)
        let newer = Note(id: UUID(), content: "Newer",
                         createdDate: Date(timeIntervalSince1970: 2),
                         modifiedDate: Date(timeIntervalSince1970: 2), isPinned: false)
        var pinned = Note(id: UUID(), content: "Pinned",
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
            try storage.updateNote(note(content: ""))
        }
    }

    @Test("every note write queues a REST intent")
    func writesReachTheOutbox() throws {
        let storage = try storage()
        try storage.insertNote(note(content: "Milk"))
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
        try storage.insertNote(note(content: "# Groceries\n\nMilk"))
        var updated = try #require(try storage.fetchAllNotes().first)
        // This class never claims "title" at all any more — a hand-typed
        // title fence is just another foreign key, and surviving an update
        // is the ordinary case rather than a special one.
        updated.content = "---\ntitle: My Doc\n---\n# Groceries\n\nMilk"
        try storage.updateNote(updated)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\ntitle: My Doc\n---\n# Groceries\n\nMilk")
    }

    @Test("a user-typed title fence with a foreign key survives an update that would otherwise clear the title")
    func userTypedTitleFenceWithForeignKeySurvivesSave() throws {
        let storage = try storage()
        try storage.insertNote(note(content: "# Groceries\n\nMilk"))
        var updated = try #require(try storage.fetchAllNotes().first)
        updated.content = "---\ntitle: My Doc\nauthor: mike\n---\n# Groceries\n\nMilk"
        try storage.updateNote(updated)
        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\ntitle: My Doc\nauthor: mike\n---\n# Groceries\n\nMilk")
    }

    @Test("a user-typed pinned-only fence survives an update whose own state would otherwise clear the key")
    func userTypedPinnedFenceSurvivesSave() throws {
        let storage = try storage()
        try storage.insertNote(note(content: "# Groceries\n\nMilk"))
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
        try storage.insertNote(note(content: "# Groceries\n\nMilk"))
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
        try storage.insertNote(note(content: content))
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
        try storage.insertNote(note(content: content))
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
        try storage.insertNote(note(content: "# Groceries\n\nMilk"))

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
    ///
    /// Restated around `pinned` — the only key this class still owns now that
    /// the title field is gone. Distinct from `userTypedPinnedFenceSurvivesSave`,
    /// which never takes a claim on the key to begin with: here a claim is
    /// taken first, so this test is about *losing* a claim, not lacking one.
    /// The paste and the unpin land in a single write, which is exactly what
    /// happens in the app when a debounced content save is still pending and
    /// the user clicks unpin before it fires — `NotesManager.togglePin` writes
    /// immediately, against whatever content is already in memory.
    @Test("editing the text releases every claim on the frontmatter in it")
    func editingTheTextReleasesOwnership() throws {
        let storage = try storage()
        try storage.insertNote(note(content: "# Groceries\n\nMilk"))

        // Pin it — a claim on "pinned" is taken.
        var pinned = try #require(try storage.fetchAllNotes().first)
        pinned.isPinned = true
        try storage.updateNote(pinned)
        #expect(try storage.store.documents(marker: .note).first?.frontmatter["pinned"] == "true")

        // The user pastes over the whole document, keeping our key by hand,
        // and in the same stroke unpins it. The edit releases the claim, so
        // the unpin that would normally clear the key must not: the
        // hand-typed line has to survive exactly as typed.
        var edited = try #require(try storage.fetchAllNotes().first)
        edited.content = "---\npinned: true\n---\n# Groceries\n\nMilk\nBread"
        edited.isPinned = false
        try storage.updateNote(edited)

        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == "---\npinned: true\n---\n# Groceries\n\nMilk\nBread")
        #expect(try storage.store.ownedFrontmatterKeys(forDocument: stored.id).isEmpty)
    }

    /// Item 2, end to end: a note nobody ever named, reloaded and then edited,
    /// still carries no frontmatter. The app never writes a `title:` key at
    /// all now, so there is no derived-vs-stored comparison left to get
    /// wrong — this just confirms an edit to a blank, never-named note stays
    /// clean.
    @Test("a never-named note stays frontmatter-free across a reload and an edit")
    func neverNamedNoteStaysClean() throws {
        let storage = try storage()
        try storage.insertNote(Note.new(content: ""))
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

    // MARK: - The list title follows adh's typing rule

    /// A document written straight to the store, so its frontmatter is
    /// whatever the test says rather than whatever `insertNote` would emit.
    private func storedNote(_ storage: MarkdownNoteStorage, content: String) throws -> Note {
        _ = try storage.store.createDocument(content: content, markers: [.note])
        return try #require(try storage.fetchAllNotes().first)
    }

    /// `Frontmatter.parse` returns every YAML value as raw, untrimmed text;
    /// `MarkdownText.deriveTitle` goes through `Frontmatter.stringValue`,
    /// which takes a key only when YAML would type it as a string. Reading
    /// the parsed map directly — which the list used to do — showed `42` where
    /// adh falls through to the body, and the column adh recomputes on the next
    /// write then disagreed with the row on screen.
    @Test("a numeric frontmatter title falls through to the body, as adh's does")
    func numericFrontmatterTitleFallsThrough() throws {
        let storage = try storage()
        let content = "---\ntitle: 42\n---\n# Groceries\n\nMilk"
        let note = try storedNote(storage, content: content)
        #expect(note.title == "Groceries")
        #expect(note.title == MarkdownText.deriveTitle(content))
    }

    @Test("a flow-sequence frontmatter title falls through to the body, as adh's does")
    func flowSequenceFrontmatterTitleFallsThrough() throws {
        let storage = try storage()
        let content = "---\ntitle: [a, b]\n---\n# Groceries\n\nMilk"
        let note = try storedNote(storage, content: content)
        #expect(note.title == "Groceries")
        #expect(note.title == MarkdownText.deriveTitle(content))
    }

    @Test("an empty frontmatter title falls through to the body, as adh's does")
    func emptyFrontmatterTitleFallsThrough() throws {
        let storage = try storage()
        let content = "---\ntitle: \"\"\n---\n# Groceries\n\nMilk"
        let note = try storedNote(storage, content: content)
        #expect(note.title == "Groceries")
        #expect(note.title == MarkdownText.deriveTitle(content))
    }

    @Test("a whitespace-only frontmatter title falls through to the body, as adh's does")
    func whitespaceFrontmatterTitleFallsThrough() throws {
        let storage = try storage()
        let content = "---\ntitle: \"   \"\n---\n# Groceries\n\nMilk"
        let note = try storedNote(storage, content: content)
        #expect(note.title == "Groceries")
        #expect(note.title == MarkdownText.deriveTitle(content))
    }

    // MARK: - A claim may not change the user's bytes

    /// `Frontmatter.value` unquotes, so a user's `pinned: "true"` — a YAML
    /// *string*, which is not what this class emits — compared equal to the
    /// desired `"true"`, and the app rewrote the line as an unquoted boolean
    /// and claimed a key it had just taken from its author.
    @Test("a quoted pinned value the app would rewrite is neither rewritten nor claimed")
    func quotedPinnedValueIsLeftAlone() throws {
        let storage = try storage()
        let content = "---\npinned: \"true\"\n---\n# Groceries\n\nMilk"
        var note = try storedNote(storage, content: content)
        #expect(note.isPinned == false, "a pin we did not write is not ours to act on")

        note.isPinned = true
        try storage.updateNote(note)

        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == content)
        #expect(try storage.store.ownedFrontmatterKeys(forDocument: stored.id).isEmpty)
    }

    /// The other half of the same rule: a key that already reads *exactly* as
    /// what this class would write is claimed, because the claim costs the
    /// document no bytes.
    @Test("a byte-identical pinned value is claimed without modification")
    func byteIdenticalPinnedValueIsClaimed() throws {
        let storage = try storage()
        let content = "---\npinned: true\n---\n# Groceries\n\nMilk"
        var note = try storedNote(storage, content: content)

        note.isPinned = true
        try storage.updateNote(note)

        let stored = try #require(try storage.store.documents(marker: .note).first)
        #expect(stored.content == content)
        #expect(try storage.store.ownedFrontmatterKeys(forDocument: stored.id) == ["pinned"])
        #expect(try storage.fetchAllNotes().first?.isPinned == true)
    }

    // MARK: - Task 4: a note's title is its first line, not a field

    @Test @MainActor func savingANoteNeverWritesATitleKey() throws {
        let storage = try storage()
        let note = Note.new(content: "# Groceries\n\nMilk")
        try storage.insertNote(note)
        let stored = try #require(try storage.store.document(id: note.id.uuidString.lowercased()))
        #expect(Frontmatter.value("title", in: stored.content) == nil)
    }

    @Test @MainActor func aHandTypedTitleKeyIsHonouredAndLeftInTheEditor() throws {
        let storage = try storage()
        let note = Note.new(content: "---\ntitle: Named By Hand\n---\n\nBody")
        try storage.insertNote(note)
        let fetched = try #require(try storage.fetchAllNotes().first)
        #expect(fetched.title == "Named By Hand")
        #expect(fetched.content.contains("title: Named By Hand"))
    }

    @Test @MainActor func theTitleIsTheFirstLineOfTheBody() throws {
        let storage = try storage()
        try storage.insertNote(Note.new(content: "# Groceries\n\nMilk"))
        let fetched = try #require(try storage.fetchAllNotes().first)
        #expect(fetched.title == "Groceries")
    }

    @Test @MainActor func theExcerptSkipsTheTitleLine() throws {
        let storage = try storage()
        try storage.insertNote(Note.new(content: "# Groceries\n\nMilk and eggs"))
        let note = try #require(try storage.fetchAllNotes().first)
        #expect(!note.excerpt.hasPrefix("Groceries"))
        #expect(note.excerpt.contains("Milk and eggs"))
    }
}
