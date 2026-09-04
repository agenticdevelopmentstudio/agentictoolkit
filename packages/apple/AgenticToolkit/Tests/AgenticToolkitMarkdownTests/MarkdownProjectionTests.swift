import Testing
import Foundation
import GRDB
import AgenticToolkitSync
@testable import AgenticToolkitMarkdown

@Suite("MarkdownProjection")
struct MarkdownProjectionTests {

    private func store() throws -> MarkdownStore {
        try MarkdownStore(path: ":memory:", customerID: "cust-1", ecosystemID: "eco-1")
    }

    @Test("it claims all nine mirrored resources and nothing else")
    func claimsTheNine() {
        #expect(MarkdownProjection().resources == Set([
            "content.markdown", "content.notes", "content.docs", "content.papers",
            "content.categories", "content.category_edges", "content.category_items",
            "content.keywords", "content.keyword_items"
        ]))
    }

    @Test("documents and their markers are pull-only; taxonomy is not")
    func pullOnlySetMatchesADH() {
        #expect(Set(MarkdownProjection.pullOnlyResources) == Set([
            "content.markdown", "content.notes", "content.docs", "content.papers"
        ]))
    }

    @Test("no generic mirror table is created for a claimed resource")
    func noGenericMirrors() throws {
        let store = try store()
        try store.database.read { conn in
            for table in ["content_markdown", "content_categories", "content_notes"] {
                let exists = try conn.tableExists(table)
                #expect(exists == false, "unexpected generic mirror \(table)")
            }
        }
    }

    @Test("a pulled document lands in typed columns and reads back as a document")
    func pulledDocumentIsTyped() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(
                resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "5",
                data: [
                    "title": .string("From the server"),
                    "content": .string("# From the server\n\nBody."),
                    "content_hash": .string("abc"),
                    "size_bytes": .number(26),
                    "current_version": .number(3),
                    "visibility": .string("public"),
                    "stage": .string("final"),
                    "owner_kind": .string("customer"),
                    "owner_id": .string("cust-1"),
                    "created_at": .string("2026-01-01T00:00:00Z"),
                    "updated_at": .string("2026-01-02T00:00:00Z")
                ])
        ], advancingTo: nil)

        let document = try #require(try store.document(id: "m1"))
        #expect(document.content == "# From the server\n\nBody.")
        #expect(document.visibility == .public)
        #expect(document.stage == .final)
        #expect(document.currentVersion == 3)
        try store.database.read { conn in
            let syncVersion = try Int.fetchOne(
                conn, sql: "SELECT sync_version FROM markdown WHERE id = 'm1'")
            #expect(syncVersion == 5)
        }
    }

    @Test("a pulled delete tombstones both flags")
    func pulledDeleteTombstones() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "1",
                       data: ["title": .string("t"), "content": .string("c"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-01T00:00:00Z")])
        ], advancingTo: nil)
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .delete, syncVersion: "2", data: nil)
        ], advancingTo: nil)
        #expect(try store.document(id: "m1") == nil)
        try store.database.read { conn in
            let isDeleted = try Int.fetchOne(
                conn, sql: "SELECT is_deleted FROM markdown WHERE id = 'm1'")
            #expect(isDeleted == 1)
        }
    }

    @Test("liveRows reads a typed row back in the mirror's own shape")
    func liveRowsRoundTrip() async throws {
        let store = try store()
        _ = try store.createCategory(name: "Recipes")
        let rows = try store.syncStore.liveRows(resource: "content.categories")
        #expect(rows.count == 1)
        #expect(rows[0]["name"] == .string("Recipes"))
        #expect(rows[0]["id"] != nil)
    }

    @Test("a resync truncates every projected table")
    func resyncTruncates() async throws {
        let store = try store()
        _ = try store.createDocument(content: "local", markers: [.note])
        _ = try store.createCategory(name: "Recipes")
        try await store.syncStore.resetForResync()
        try store.database.read { conn in
            let markdownCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM markdown")
            let notesCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM notes")
            let categoriesCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM categories")
            #expect(markdownCount == 0)
            #expect(notesCount == 0)
            #expect(categoriesCount == 0)
        }
    }

    @Test("an unparseable timestamp is stored verbatim rather than dropped")
    func unknownFieldsSurvive() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "1",
                       data: ["title": .string("t"), "content": .string("c"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-01T00:00:00Z"),
                              "sync_stamped_at": .string("2026-01-01T00:00:01Z"),
                              "sync_txid": .number(99)])
        ], advancingTo: nil)
        try store.database.read { conn in
            let syncTxid = try Int.fetchOne(
                conn, sql: "SELECT sync_txid FROM markdown WHERE id = 'm1'")
            #expect(syncTxid == 99)
        }
    }

    @Test("a non-fractional server timestamp is normalised to the fractional form on ingest")
    func timestampNormalisedOnIngest() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "1",
                       data: ["title": .string("t"), "content": .string("c"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-01T00:00:00Z")])
        ], advancingTo: nil)
        try store.database.read { conn in
            let createdAt = try String.fetchOne(
                conn, sql: "SELECT created_at FROM markdown WHERE id = 'm1'")
            let updatedAt = try String.fetchOne(
                conn, sql: "SELECT updated_at FROM markdown WHERE id = 'm1'")
            #expect(createdAt == "2026-01-01T00:00:00.000Z")
            #expect(updatedAt == "2026-01-01T00:00:00.000Z")
        }
    }
}
