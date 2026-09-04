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

    /// Cross-checks `MarkdownProjection.knownColumns(for:)` — the
    /// hand-maintained column lists `specificColumns` builds from — against
    /// what the real schema actually created, via `PRAGMA table_info`. The
    /// resource *set* cannot drift from `MarkdownSchema.tables` any more
    /// (`claimsTheNine` pins that structurally), but each resource's column
    /// *list* is still prose a schema edit can silently outrun; this is what
    /// would catch a column added to one table's DDL and forgotten here.
    @Test("known columns for every resource match the real schema")
    func columnListsMatchTheRealSchema() throws {
        let store = try store()
        try store.database.read { conn in
            for resource in MarkdownProjection().resources.sorted() {
                let table = String(resource.dropFirst("content.".count))
                let rows = try Row.fetchAll(conn, sql: "PRAGMA table_info(\(table))")
                let actual = Set(rows.map { $0["name"] as String })
                let known = MarkdownProjection.knownColumns(for: resource)
                #expect(actual == known, "\(resource): schema has \(actual), projection knows \(known)")
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

    /// The failure mode fix #1 closes: a full-row pull (not a local patch)
    /// that restores a previously server-deleted document. adh's wire format
    /// omits a key whose new value is null, so the restore payload carries
    /// `is_deleted` implicitly (never mentioned — defaults to 0 via
    /// `excluded.is_deleted`) but never mentions `deleted_at` either, since
    /// its new value is null. Before the force-bind fix, `deleted_at` stayed
    /// at its stale tombstoned value forever: `document(id:)` (gates on
    /// `is_deleted` alone) would show the row again, but `liveRow`/`liveRows`
    /// (`WHERE deleted_at IS NULL`) would hide it forever.
    @Test("a server delete followed by a server restore clears both tombstones on a document")
    func restoreAfterDeleteClearsTombstoneForDocument() async throws {
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
        #expect(try store.syncStore.liveRow(resource: "content.markdown", id: "m1") == nil)

        // The restore payload never mentions `deleted_at` or `is_deleted` —
        // exactly what adh's omit-null-keys wire format would send.
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "3",
                       data: ["title": .string("t"), "content": .string("restored"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-03T00:00:00Z")])
        ], advancingTo: nil)

        let restored = try #require(try store.document(id: "m1"))
        #expect(restored.content == "restored")
        #expect(restored.isDeleted == false)
        #expect(try store.syncStore.liveRow(resource: "content.markdown", id: "m1") != nil)
    }

    /// The taxonomy flavor of the same fix: none of the five taxonomy tables
    /// have an `is_deleted` fallback, so before the force-bind fix a restore
    /// was not merely inconsistent but unrecoverable — the row would stay
    /// invisible to `liveRow`/`liveRows` forever.
    @Test("a server delete followed by a server restore clears the tombstone on a taxonomy row")
    func restoreAfterDeleteClearsTombstoneForTaxonomyRow() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(resource: "content.categories", id: "c1", op: .upsert, syncVersion: "1",
                       data: ["name": .string("Recipes"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-01T00:00:00Z")])
        ], advancingTo: nil)
        #expect(try store.syncStore.liveRow(resource: "content.categories", id: "c1") != nil)

        try await store.syncStore.apply([
            SyncChange(resource: "content.categories", id: "c1", op: .delete, syncVersion: "2", data: nil)
        ], advancingTo: nil)
        #expect(try store.syncStore.liveRow(resource: "content.categories", id: "c1") == nil)

        // Restore payload never mentions `deleted_at`.
        try await store.syncStore.apply([
            SyncChange(resource: "content.categories", id: "c1", op: .upsert, syncVersion: "3",
                       data: ["name": .string("Recipes (restored)"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-03T00:00:00Z")])
        ], advancingTo: nil)

        let row = try #require(try store.syncStore.liveRow(resource: "content.categories", id: "c1"))
        #expect(row["name"] == .string("Recipes (restored)"))
    }

    /// Pins the behaviour deviation 3 (Task 12's original decision) exists
    /// to protect, now that fix #1 forces `deleted_at`/`is_deleted` into
    /// every upsert's `SET` clause: a local `stage(_:)` mutation whose
    /// payload omits `customer_id` (as every taxonomy write does — the
    /// column was already set moments earlier by the raw `INSERT` in the
    /// same transaction) must not null it out. The force-bind fix only
    /// widens the always-assigned set by `deleted_at`/`is_deleted`; it must
    /// not have widened it to `customer_id` too.
    @Test("a local stage mutation omitting customer_id does not null it out")
    func localStageDoesNotClobberCustomerID() throws {
        let store = try store()
        let category = try store.createCategory(name: "Recipes")
        try store.database.read { conn in
            let customerID = try String.fetchOne(
                conn, sql: "SELECT customer_id FROM categories WHERE id = ?",
                arguments: [category.id])
            #expect(customerID == "cust-1")
        }
    }

    @Test("liveRows reads a typed row back in the mirror's own shape")
    func liveRowsRoundTrip() throws {
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

    /// `defer_foreign_keys` is connection-scoped and resets itself to `OFF`
    /// when the transaction that set it ends (see `truncate`'s doc comment).
    /// This pins that it really does not leak onto the pooled connection
    /// `resetForResync` used, by distinguishing "immediate" from "deferred"
    /// checking the only way that's actually observable: insert a child row
    /// referencing a not-yet-existing parent, then insert the parent,
    /// *within one transaction*. Under immediate (correct, non-leaked)
    /// checking the child insert throws on its own statement, before the
    /// parent insert ever runs. Under leaked deferred checking, both inserts
    /// would succeed and the transaction would commit clean, since the
    /// dangling reference is resolved by the time of commit.
    @Test("defer_foreign_keys does not leak past resetForResync onto later writes")
    func deferForeignKeysDoesNotLeakPastResetForResync() async throws {
        let store = try store()
        try await store.syncStore.resetForResync()
        #expect(throws: (any Error).self) {
            try store.database.write { conn in
                try conn.execute(
                    sql: """
                        INSERT INTO notes (id, markdown_id, created_at, updated_at)
                        VALUES ('n1', 'not-yet-created', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                        """)
                try conn.execute(
                    sql: """
                        INSERT INTO markdown (id, title, content, created_at, updated_at)
                        VALUES ('not-yet-created', 't', 'c', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                        """)
            }
        }
    }

    @Test("sync_txid round-trips through a pulled upsert")
    func syncTxidRoundTrips() async throws {
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

    @Test("an unparseable timestamp is stored verbatim rather than dropped")
    func unparseableTimestampFallsBackToVerbatim() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "1",
                       data: ["title": .string("t"), "content": .string("c"),
                              "created_at": .string("not-a-date"),
                              "updated_at": .string("2026-01-01T00:00:00Z")])
        ], advancingTo: nil)
        try store.database.read { conn in
            let createdAt = try String.fetchOne(
                conn, sql: "SELECT created_at FROM markdown WHERE id = 'm1'")
            #expect(createdAt == "not-a-date")
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

    /// `.` (0x2E) sorts before `Z` (0x5A) in ASCII, so an un-normalised
    /// non-fractional stamp sorts *after* a fractional one from the same
    /// second under plain string ordering — the exact inversion this task
    /// exists to kill. `timestampNormalisedOnIngest` only pins the stored
    /// string; this pins the ordering consequence that string alone doesn't
    /// prove: m1's `updated_at` is chronologically earlier (no fraction) and
    /// m2's is chronologically later (explicit `.500` fraction) within the
    /// same second — `ORDER BY updated_at` must return them in that
    /// chronological order, which only holds once both are normalised to the
    /// same fractional shape.
    @Test("normalised timestamps sort in true chronological order, not raw string order")
    func timestampNormalisationFixesChronologicalOrdering() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "1",
                       data: ["title": .string("earlier"), "content": .string("c"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-01T00:00:00Z")])
        ], advancingTo: nil)
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m2", op: .upsert, syncVersion: "1",
                       data: ["title": .string("later"), "content": .string("c"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-01T00:00:00.500Z")])
        ], advancingTo: nil)
        try store.database.read { conn in
            let ids = try String.fetchAll(
                conn, sql: "SELECT id FROM markdown ORDER BY updated_at ASC")
            #expect(ids == ["m1", "m2"])
        }
    }

    /// `deleted_at` is a `timestampColumns` member like `created_at`/
    /// `updated_at`, but neither of the other normalisation tests exercises
    /// it directly — `pulledDeleteTombstones` sets it via `markDeleted`
    /// (which stamps `Date()` itself, already fractional), not via a value
    /// arriving in an upsert payload. This exercises the column directly:
    /// a pulled upsert can carry a non-fractional `deleted_at` (adh sending
    /// a tombstoned row's full state), and it must come out normalised the
    /// same way `created_at`/`updated_at` do.
    @Test("a non-fractional deleted_at in an upsert payload is normalised on ingest")
    func deletedAtColumnIsNormalisedOnIngest() async throws {
        let store = try store()
        try await store.syncStore.apply([
            SyncChange(resource: "content.markdown", id: "m1", op: .upsert, syncVersion: "1",
                       data: ["title": .string("t"), "content": .string("c"),
                              "created_at": .string("2026-01-01T00:00:00Z"),
                              "updated_at": .string("2026-01-01T00:00:00Z"),
                              "deleted_at": .string("2026-01-01T00:00:00Z")])
        ], advancingTo: nil)
        try store.database.read { conn in
            let deletedAt = try String.fetchOne(
                conn, sql: "SELECT deleted_at FROM markdown WHERE id = 'm1'")
            #expect(deletedAt == "2026-01-01T00:00:00.000Z")
        }
    }
}
