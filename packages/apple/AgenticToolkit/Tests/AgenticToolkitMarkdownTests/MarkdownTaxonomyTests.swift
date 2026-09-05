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
