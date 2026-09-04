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
}
