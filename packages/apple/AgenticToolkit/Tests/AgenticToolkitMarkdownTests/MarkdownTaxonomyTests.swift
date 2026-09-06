import Testing
import Foundation
import GRDB
@testable import AgenticToolkitMarkdown

@Suite("MarkdownTaxonomy")
struct MarkdownTaxonomyTests {

    private func store() throws -> MarkdownStore {
        try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
    }

    @Test("a category round-trips")
    func categoryRoundTrips() throws {
        let store = try store()
        let created = try store.createCategory(name: "Recipes", icon: "book")
        let loaded = try #require(try store.categories().first)
        #expect(loaded == created)
        #expect(loaded.name == "Recipes")
        #expect(loaded.icon == "book")
    }

    @Test("a category write stages a sync mutation, unlike a document write")
    func categoriesArePushable() throws {
        let store = try store()
        _ = try store.createCategory(name: "Recipes")
        let ops = try store.database.read { conn in
            try Row.fetchAll(conn, sql: "SELECT resource, type FROM _sync_outbox")
        }
        #expect(ops.count == 1)
        #expect(ops[0]["resource"] as String == "content.categories")
        #expect(ops[0]["type"] as String == "upsert")
    }

    @Test("a diamond is allowed — two parents is not a cycle")
    func diamondIsAllowed() throws {
        let store = try store()
        let top = try store.createCategory(name: "Top")
        let left = try store.createCategory(name: "Left")
        let right = try store.createCategory(name: "Right")
        let bottom = try store.createCategory(name: "Bottom")
        try store.addCategoryEdge(parent: top.id, child: left.id)
        try store.addCategoryEdge(parent: top.id, child: right.id)
        try store.addCategoryEdge(parent: left.id, child: bottom.id)
        try store.addCategoryEdge(parent: right.id, child: bottom.id)   // second parent, no cycle
        #expect(try store.database.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM category_edges")
        } == 4)
    }

    @Test("a three-node cycle is refused")
    func cycleIsRefused() throws {
        let store = try store()
        let nodeA = try store.createCategory(name: "A")
        let nodeB = try store.createCategory(name: "B")
        let nodeC = try store.createCategory(name: "C")
        try store.addCategoryEdge(parent: nodeA.id, child: nodeB.id)
        try store.addCategoryEdge(parent: nodeB.id, child: nodeC.id)
        #expect(throws: MarkdownStoreError.categoryCycle(parent: nodeC.id, child: nodeA.id)) {
            try store.addCategoryEdge(parent: nodeC.id, child: nodeA.id)
        }
    }

    @Test("a self-edge is refused by the schema, before the walk runs")
    func selfEdgeIsRefused() throws {
        let store = try store()
        let nodeA = try store.createCategory(name: "A")
        #expect(throws: (any Error).self) {
            try store.addCategoryEdge(parent: nodeA.id, child: nodeA.id)
        }
    }

    @Test("adding the same edge twice does not stage a phantom mutation")
    func duplicateEdgeDoesNotStagePhantomMutation() throws {
        let store = try store()
        let top = try store.createCategory(name: "Top")
        let sub = try store.createCategory(name: "Sub")
        try store.addCategoryEdge(parent: top.id, child: sub.id)
        try store.addCategoryEdge(parent: top.id, child: sub.id)
        let edgeRows = try store.database.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM category_edges")
        }
        let edgeOps = try store.database.read { conn in
            try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM _sync_outbox WHERE resource = 'content.category_edges'")
        }
        // The category creates above also stage two upserts; only the edge's
        // own resource is counted here, so this isolates the edge mutator.
        #expect(edgeRows == 1)
        #expect(edgeOps == 1)
    }

    @Test("assigning a category files the document under it")
    func categoryAssignment() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [.note])
        let category = try store.createCategory(name: "Recipes")
        try store.assignCategory(category.id, toDocument: document.id)
        #expect(try store.categories(forDocument: document.id) == [category])
    }

    @Test("assigning the same category twice is idempotent")
    func categoryAssignmentIsIdempotent() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        let category = try store.createCategory(name: "Recipes")
        try store.assignCategory(category.id, toDocument: document.id)
        try store.assignCategory(category.id, toDocument: document.id)
        #expect(try store.categories(forDocument: document.id).count == 1)
    }

    @Test("assigning the same category twice does not stage a phantom mutation")
    func duplicateCategoryAssignmentDoesNotStagePhantomMutation() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        let category = try store.createCategory(name: "Recipes")
        try store.assignCategory(category.id, toDocument: document.id)
        try store.assignCategory(category.id, toDocument: document.id)
        let itemRows = try store.database.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM category_items")
        }
        let itemOps = try store.database.read { conn in
            try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM _sync_outbox WHERE resource = 'content.category_items'")
        }
        #expect(itemRows == 1)
        #expect(itemOps == 1)
    }

    @Test("a category item records the polymorphic target kind adh uses")
    func targetKindIsTheResourceName() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        let category = try store.createCategory(name: "Recipes")
        try store.assignCategory(category.id, toDocument: document.id)
        #expect(try store.database.read { conn in
            try String.fetchOne(conn, sql: "SELECT target_kind FROM category_items")
        } == "content.markdown")
    }

    @Test("categoryEdges returns every live parent/child pair")
    func categoryEdgesReturnsLiveEdges() throws {
        let store = try store()
        let top = try store.createCategory(name: "Top")
        let left = try store.createCategory(name: "Left")
        let right = try store.createCategory(name: "Right")
        try store.addCategoryEdge(parent: top.id, child: left.id)
        try store.addCategoryEdge(parent: top.id, child: right.id)
        let edges = try store.categoryEdges()
        #expect(edges.count == 2)
        #expect(edges.contains { $0.parent == top.id && $0.child == left.id })
        #expect(edges.contains { $0.parent == top.id && $0.child == right.id })
    }

    @Test("categoryEdges omits an edge removed by removeCategoryEdge")
    func categoryEdgesOmitsRemovedEdges() throws {
        let store = try store()
        let top = try store.createCategory(name: "Top")
        let sub = try store.createCategory(name: "Sub")
        try store.addCategoryEdge(parent: top.id, child: sub.id)
        try store.removeCategoryEdge(parent: top.id, child: sub.id)
        #expect(try store.categoryEdges().isEmpty)
    }

    @Test("categoryNoteCounts counts only notes, not docs or papers")
    func categoryNoteCountsCountsOnlyNotes() throws {
        let store = try store()
        let category = try store.createCategory(name: "Recipes")
        let note = try store.createDocument(content: "a note", markers: [.note])
        let doc = try store.createDocument(content: "a doc", markers: [.doc])
        try store.assignCategory(category.id, toDocument: note.id)
        try store.assignCategory(category.id, toDocument: doc.id)
        let counts = try store.categoryNoteCounts()
        #expect(counts[category.id] == 1)
    }

    @Test("categoryNoteCounts is direct, not transitive — a parent does not inherit a child's notes")
    func categoryNoteCountsIsDirectNotTransitive() throws {
        let store = try store()
        let parent = try store.createCategory(name: "Parent")
        let child = try store.createCategory(name: "Child")
        try store.addCategoryEdge(parent: parent.id, child: child.id)
        let note = try store.createDocument(content: "a note", markers: [.note])
        try store.assignCategory(child.id, toDocument: note.id)
        let counts = try store.categoryNoteCounts()
        #expect(counts[child.id] == 1)
        #expect(counts[parent.id] == nil)
    }

    @Test("documentIDs(forCategory:) returns the notes filed directly under it")
    func documentIDsForCategoryReturnsDirectMembers() throws {
        let store = try store()
        let category = try store.createCategory(name: "Recipes")
        let note = try store.createDocument(content: "a note", markers: [.note])
        let otherNote = try store.createDocument(content: "another note", markers: [.note])
        try store.assignCategory(category.id, toDocument: note.id)
        #expect(try store.documentIDs(forCategory: category.id) == [note.id])
        #expect(try store.documentIDs(forCategory: category.id).contains(otherNote.id) == false)
    }

    @Test("documentIDs(forCategory:) excludes a doc filed under the same category")
    func documentIDsForCategoryExcludesNonNotes() throws {
        let store = try store()
        let category = try store.createCategory(name: "Recipes")
        let doc = try store.createDocument(content: "a doc", markers: [.doc])
        try store.assignCategory(category.id, toDocument: doc.id)
        #expect(try store.documentIDs(forCategory: category.id).isEmpty)
    }

    @Test("keywords round-trip and attach to a document")
    func keywordAssignment() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        let keyword = try store.createKeyword(label: "swift")
        try store.assignKeyword(keyword.id, toDocument: document.id)
        #expect(try store.keywords() == [keyword])
        #expect(try store.keywords(forDocument: document.id) == [keyword])
    }

    @Test("one author cannot have the same keyword twice")
    func keywordLabelsAreUniquePerAuthor() throws {
        let store = try store()
        _ = try store.createKeyword(label: "swift")
        #expect(throws: (any Error).self) {
            _ = try store.createKeyword(label: "swift")
        }
    }

    @Test("assigning a category to a document that is not there is refused")
    func assignCategoryRefusesAMissingDocument() throws {
        let store = try store()
        let category = try store.createCategory(name: "Recipes")
        #expect(throws: MarkdownStoreError.notFound("ghost")) {
            try store.assignCategory(category.id, toDocument: "ghost")
        }
        let itemRows = try store.database.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM category_items")
        }
        #expect(itemRows == 0)
    }

    @Test("assigning a category that does not exist is refused")
    func assignCategoryRefusesAMissingCategory() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        #expect(throws: MarkdownStoreError.notFound("ghost")) {
            try store.assignCategory("ghost", toDocument: document.id)
        }
    }

    @Test("assigning a category to a deleted document is refused")
    func assignCategoryRefusesADeletedDocument() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        let category = try store.createCategory(name: "Recipes")
        try store.deleteDocument(id: document.id)
        #expect(throws: MarkdownStoreError.notFound(document.id)) {
            try store.assignCategory(category.id, toDocument: document.id)
        }
    }

    @Test("assigning a keyword to a document that is not there is refused")
    func assignKeywordRefusesAMissingDocument() throws {
        let store = try store()
        let keyword = try store.createKeyword(label: "swift")
        #expect(throws: MarkdownStoreError.notFound("ghost")) {
            try store.assignKeyword(keyword.id, toDocument: "ghost")
        }
        let itemRows = try store.database.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM keyword_items")
        }
        #expect(itemRows == 0)
    }

    @Test("assigning a keyword that does not exist is refused")
    func assignKeywordRefusesAMissingKeyword() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        #expect(throws: MarkdownStoreError.notFound("ghost")) {
            try store.assignKeyword("ghost", toDocument: document.id)
        }
    }

    @Test("assigning the same keyword twice does not stage a phantom mutation")
    func duplicateKeywordAssignmentDoesNotStagePhantomMutation() throws {
        let store = try store()
        let document = try store.createDocument(content: "hello", markers: [])
        let keyword = try store.createKeyword(label: "swift")
        try store.assignKeyword(keyword.id, toDocument: document.id)
        try store.assignKeyword(keyword.id, toDocument: document.id)
        let itemRows = try store.database.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM keyword_items")
        }
        let itemOps = try store.database.read { conn in
            try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM _sync_outbox WHERE resource = 'content.keyword_items'")
        }
        #expect(itemRows == 1)
        #expect(itemOps == 1)
    }

    // MARK: - Category rename, delete, unassign, edge removal

    @Test("renaming a category changes its name and stages the change")
    func renamingACategoryChangesItsNameAndStagesTheChange() throws {
        let harness = try store()
        let category = try harness.createCategory(name: "Groceries")
        try harness.renameCategory(category.id, to: "Shopping")
        #expect(try harness.categories().map(\.name) == ["Shopping"])
        // The rename coalesces into the create's still-pending op (same
        // resource + row id), so this is one row, not two — but its payload
        // must carry the rename, which is the mutation actually being tested.
        let payload = try harness.database.read { conn in
            try String.fetchOne(
                conn, sql: "SELECT payload FROM _sync_outbox WHERE resource = 'content.categories'")
        }
        #expect(payload?.contains("Shopping") == true)
    }

    @Test("deleting a category hides it from the list")
    func deletingACategoryHidesItFromTheList() throws {
        let harness = try store()
        let category = try harness.createCategory(name: "Groceries")
        try harness.deleteCategory(category.id)
        #expect(try harness.categories().isEmpty)
    }

    @Test("deleting a category leaves its documents alone")
    func deletingACategoryLeavesItsDocumentsAlone() throws {
        let harness = try store()
        let document = try harness.createDocument(content: "# Milk", markers: [.note])
        let category = try harness.createCategory(name: "Groceries")
        try harness.assignCategory(category.id, toDocument: document.id)
        try harness.deleteCategory(category.id)
        #expect(try harness.document(id: document.id) != nil)
        #expect(try harness.categories(forDocument: document.id).isEmpty)
    }

    @Test("deleting a parent category removes its edges")
    func deletingAParentCategoryRemovesItsEdges() throws {
        let harness = try store()
        let parent = try harness.createCategory(name: "Work")
        let child = try harness.createCategory(name: "Invoices")
        try harness.addCategoryEdge(parent: parent.id, child: child.id)
        try harness.deleteCategory(parent.id)
        // The child survives as a root; only the edge went.
        #expect(try harness.categories().map(\.name) == ["Invoices"])
        // The edge's tombstone coalesces into its own still-pending create op
        // (same resource + row id) rather than adding a second row — but the
        // merged payload must carry the tombstone `deleteCategory` staged.
        let payload = try harness.database.read { conn in
            try String.fetchOne(
                conn, sql: "SELECT payload FROM _sync_outbox WHERE resource = 'content.category_edges'")
        }
        #expect(payload?.contains("deleted_at") == true)
    }

    @Test("unassigning a category leaves the document and the category")
    func unassigningACategoryLeavesTheDocumentAndTheCategory() throws {
        let harness = try store()
        let document = try harness.createDocument(content: "# Milk", markers: [.note])
        let category = try harness.createCategory(name: "Groceries")
        try harness.assignCategory(category.id, toDocument: document.id)
        try harness.unassignCategory(category.id, fromDocument: document.id)
        #expect(try harness.categories(forDocument: document.id).isEmpty)
        #expect(try harness.categories().count == 1)
        // The unassignment coalesces into the assignment's still-pending
        // create op (same resource + row id) rather than adding a second
        // row — but the merged payload must carry the tombstone
        // `unassignCategory` staged.
        let payload = try harness.database.read { conn in
            try String.fetchOne(
                conn, sql: "SELECT payload FROM _sync_outbox WHERE resource = 'content.category_items'")
        }
        #expect(payload?.contains("deleted_at") == true)
    }

    @Test("unassigning a category that was never assigned is a no-op")
    func unassigningANeverAssignedCategoryIsANoOp() throws {
        let harness = try store()
        let document = try harness.createDocument(content: "hello", markers: [])
        let category = try harness.createCategory(name: "Groceries")
        try harness.unassignCategory(category.id, fromDocument: document.id)
        let itemOps = try harness.database.read { conn in
            try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM _sync_outbox WHERE resource = 'content.category_items'")
        }
        #expect(itemOps == 0)
    }

    @Test("removing a category edge leaves both categories")
    func removingACategoryEdgeLeavesBothCategories() throws {
        let harness = try store()
        let parent = try harness.createCategory(name: "Work")
        let child = try harness.createCategory(name: "Invoices")
        try harness.addCategoryEdge(parent: parent.id, child: child.id)
        try harness.removeCategoryEdge(parent: parent.id, child: child.id)
        #expect(try harness.categories().count == 2)
    }

    @Test("removing an edge that was never added is a no-op")
    func removingANeverAddedEdgeIsANoOp() throws {
        let harness = try store()
        let parent = try harness.createCategory(name: "Work")
        let child = try harness.createCategory(name: "Invoices")
        try harness.removeCategoryEdge(parent: parent.id, child: child.id)
        let edgeOps = try harness.database.read { conn in
            try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM _sync_outbox WHERE resource = 'content.category_edges'")
        }
        #expect(edgeOps == 0)
    }

    @Test("renaming a missing category throws not found")
    func renamingAMissingCategoryThrowsNotFound() throws {
        let harness = try store()
        #expect(throws: MarkdownStoreError.notFound("no-such-id")) {
            try harness.renameCategory("no-such-id", to: "Whatever")
        }
    }

    @Test("deleting a missing category throws not found")
    func deletingAMissingCategoryThrowsNotFound() throws {
        let harness = try store()
        #expect(throws: MarkdownStoreError.notFound("no-such-id")) {
            try harness.deleteCategory("no-such-id")
        }
    }

    // MARK: - Keyword uniqueness

    /// adh's `UNIQUE (customer_id, ecosystem_id, label)` is unconditional, so
    /// a live label is taken. The bare `INSERT` this replaces threw a raw
    /// `SQLITE_CONSTRAINT`, which the call site could not tell from a disk
    /// error.
    @Test("a second keyword with a live label throws a typed duplicate error")
    func duplicateKeywordThrows() throws {
        let store = try store()
        _ = try store.createKeyword(label: "swift")
        #expect(throws: MarkdownStoreError.duplicateKeyword(label: "swift")) {
            try store.createKeyword(label: "swift")
        }
        #expect(try store.keywords().count == 1)
    }

    /// The tombstone half, ruled explicitly: reviving, because adh's constraint
    /// is not partial — a soft-deleted row keeps occupying its label there, so
    /// a second row would be a local state the server rejects on push, and
    /// refusing would leave the user unable ever to re-add a keyword they once
    /// deleted. The original id comes back with it, so whatever the keyword was
    /// attached to is still attached.
    @Test("recreating a tombstoned label revives the original row, id and all")
    func tombstonedKeywordIsRevived() throws {
        let store = try store()
        let original = try store.createKeyword(label: "swift", color: "red")
        try store.database.write { conn in
            try conn.execute(
                sql: "UPDATE keywords SET deleted_at = '2026-01-01T00:00:00.000Z' WHERE id = ?",
                arguments: [original.id])
        }
        #expect(try store.keywords().isEmpty)

        let revived = try store.createKeyword(label: "swift", color: "blue")
        #expect(revived.id == original.id)
        #expect(revived.color == "blue")
        #expect(try store.keywords() == [revived])
        // And the revive is pushed: the server has to be told the tombstone is
        // gone, or its next pull puts it back.
        let payload = try store.database.read { conn in
            try String.fetchOne(
                conn, sql: "SELECT payload FROM _sync_outbox WHERE row_id = ?",
                arguments: [revived.id])
        }
        #expect(payload?.contains("deleted_at") == true)
    }
}
