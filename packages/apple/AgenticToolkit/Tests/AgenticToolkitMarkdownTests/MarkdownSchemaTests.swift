import Testing
import Foundation
import GRDB
import AgenticToolkitDatabase
@testable import AgenticToolkitMarkdown

@Suite("MarkdownSchema")
struct MarkdownSchemaTests {

    private func migrated() throws -> BoundedDatabase {
        let database = try BoundedDatabase(path: ":memory:")
        try MarkdownSchema.migrate(database)
        return database
    }

    private func columns(_ table: String, in database: BoundedDatabase) throws -> [String] {
        try database.read { conn in
            try Row.fetchAll(conn, sql: "PRAGMA table_info(\"\(table)\")").map { $0["name"] }
        }.sorted()
    }

    /// The tail every mirrored table carries, listed once here as the spec
    /// lists it once — a per-table literal below would repeat it nine times
    /// and let a typo hide in the repetition.
    private let commonColumns = [
        "id", "customer_id", "ecosystem_id",
        "created_at", "updated_at", "deleted_at",
        "sync_version", "sync_stamped_at", "sync_txid"
    ]

    private func expect(_ table: String, adds extra: [String], in database: BoundedDatabase) throws {
        #expect(try columns(table, in: database) == (commonColumns + extra).sorted())
    }

    @Test("every mirrored table exists")
    func tablesExist() throws {
        let database = try migrated()
        try database.read { conn in
            for table in MarkdownSchema.tables {
                // A bare `#expect(try …)` inside a nested closure fails to
                // compile here — the `try` in the macro-expanded argument
                // list to `Testing.__checkValue` isn't recognized as handled
                // (reproduced in isolation; not specific to GRDB). Binding the
                // throwing call to a `let` first sidesteps it without
                // changing what's asserted.
                let exists = try conn.tableExists(table)
                #expect(exists, "missing table \(table)")
            }
        }
    }

    /// `tablesExist` above only proves the listed tables exist — it says
    /// nothing about a table the DDL creates that `MarkdownSchema.tables`
    /// forgot to list, which would be invisible to `MarkdownProjection`
    /// (whose `resources`/`syncResources` now derive from `tables` — round 1
    /// fix #3) and to `columnListsMatchTheRealSchema`
    /// (`MarkdownProjectionTests.swift`), which only walks the resources the
    /// projection already claims. This closes that direction: run
    /// `createTables(in:)` — the DDL itself, not `migrate`, so there is no
    /// bookkeeping/outbox table to exclude — into a scratch database and
    /// diff its actual table list against `tables`.
    @Test("createTables creates exactly the tables MarkdownSchema.tables lists — no more, no less")
    func tablesMatchTheDDLExactly() throws {
        let queue = try DatabaseQueue()
        try queue.write { conn in
            try MarkdownSchema.createTables(in: conn)
        }
        let actual = try queue.read { conn in
            try String.fetchAll(conn, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        #expect(Set(actual) == Set(MarkdownSchema.tables))
    }

    @Test("markdown carries adh's column set exactly")
    func markdownColumns() throws {
        try expect("markdown", adds: [
            "title", "content", "frontmatter", "content_hash", "size_bytes",
            "current_version", "latest_version_id", "is_deleted", "public_route",
            "visibility", "stage", "owner_kind", "owner_id"
        ], in: try migrated())
    }

    @Test("the three marker tables are structurally identical")
    func markerColumns() throws {
        let database = try migrated()
        for table in ["notes", "docs", "papers"] {
            try expect(table, adds: ["markdown_id"], in: database)
        }
    }

    @Test("taxonomy tables carry their column sets")
    func taxonomyColumns() throws {
        let database = try migrated()
        try expect("categories",
                   adds: ["name", "description", "color", "icon", "sort_order"], in: database)
        try expect("category_edges",
                   adds: ["parent_id", "child_id", "sort_order"], in: database)
        try expect("category_items",
                   adds: ["category_id", "target_kind", "target_id", "sort_order"], in: database)
        try expect("keywords",
                   adds: ["label", "color", "description"], in: database)
        try expect("keyword_items",
                   adds: ["keyword_id", "target_kind", "target_id", "sort_order"], in: database)
    }

    @Test("foreign keys are enforced, not merely declared")
    func foreignKeysAreOn() throws {
        let database = try migrated()
        #expect(throws: (any Error).self) {
            try database.write { conn in
                try conn.execute(
                    sql: """
                        INSERT INTO notes (id, markdown_id, created_at, updated_at)
                        VALUES ('n1', 'nonexistent', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                        """)
            }
        }
    }

    @Test("visibility and stage reject values the client cannot handle")
    func checkConstraintsBite() throws {
        let database = try migrated()
        for (column, bad) in [("visibility", "unlisted"), ("stage", "archived")] {
            #expect(throws: (any Error).self) {
                try database.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO markdown (id, title, content, \(column), created_at, updated_at)
                            VALUES ('m1', 't', 'c', ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                            """,
                        arguments: [bad])
                }
            }
        }
    }

    @Test("a category cannot be its own parent")
    func selfEdgeIsRefused() throws {
        let database = try migrated()
        try database.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO categories (id, name, created_at, updated_at)
                    VALUES ('c1', 'One', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                    """)
        }
        #expect(throws: (any Error).self) {
            try database.write { conn in
                try conn.execute(
                    sql: """
                        INSERT INTO category_edges (id, parent_id, child_id, created_at, updated_at)
                        VALUES ('e1', 'c1', 'c1', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                        """)
            }
        }
    }

    @Test("a marker can be re-added after its predecessor is tombstoned")
    func markerUniquenessIsPartial() throws {
        let database = try migrated()
        try database.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO markdown (id, title, content, created_at, updated_at)
                    VALUES ('m1', 't', 'c', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
                    INSERT INTO notes (id, markdown_id, created_at, updated_at, deleted_at)
                    VALUES ('n1', 'm1', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z');
                    INSERT INTO notes (id, markdown_id, created_at, updated_at)
                    VALUES ('n2', 'm1', '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z');
                    """)
        }
        // …but only one live marker at a time.
        #expect(throws: (any Error).self) {
            try database.write { conn in
                try conn.execute(
                    sql: """
                        INSERT INTO notes (id, markdown_id, created_at, updated_at)
                        VALUES ('n3', 'm1', '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z')
                        """)
            }
        }
    }

    @Test("the adh_source expression index makes a document's kind unique per author")
    func adhSourceIndexIsUnique() throws {
        let database = try migrated()
        try database.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO markdown (id, title, content, frontmatter, created_at, updated_at)
                    VALUES ('m1', 't', 'c', '{"adh_source":"handbook"}',
                            '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                    """)
        }
        #expect(throws: (any Error).self) {
            try database.write { conn in
                try conn.execute(
                    sql: """
                        INSERT INTO markdown (id, title, content, frontmatter, created_at, updated_at)
                        VALUES ('m2', 't', 'c', '{"adh_source":"handbook"}',
                                '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                        """)
            }
        }
    }

    @Test("migrating twice is a no-op")
    func migrationIsIdempotent() throws {
        let database = try BoundedDatabase(path: ":memory:")
        try MarkdownSchema.migrate(database)
        try MarkdownSchema.migrate(database)
        try database.read { conn in
            let exists = try conn.tableExists("markdown")
            #expect(exists)
        }
    }
}

@Suite("MarkdownTimestamp")
struct MarkdownTimestampTests {

    @Test("formats as ISO-8601 UTC with an explicit Z")
    func formatsWithZ() {
        let text = MarkdownTimestamp.string(Date(timeIntervalSince1970: 0))
        #expect(text == "1970-01-01T00:00:00.000Z")
    }

    @Test("round-trips to the millisecond")
    func roundTrips() {
        let date = Date(timeIntervalSince1970: 1_800_000_000.123)
        let parsed = MarkdownTimestamp.date(MarkdownTimestamp.string(date))
        #expect(parsed != nil)
        #expect(abs((parsed ?? .distantPast).timeIntervalSince(date)) < 0.002)
    }

    @Test("parses a server timestamp without fractional seconds")
    func parsesWithoutFraction() {
        #expect(MarkdownTimestamp.date("2026-01-01T00:00:00Z") != nil)
    }

    @Test("refuses text that is not a timestamp")
    func refusesGarbage() {
        #expect(MarkdownTimestamp.date("yesterday") == nil)
        #expect(MarkdownTimestamp.date("") == nil)
        // A date with no time is not an instant, and inventing midnight for it
        // would be the same guess this parser exists to avoid.
        #expect(MarkdownTimestamp.date("2026-04-13") == nil)
    }

    /// adh's columns are Postgres `timestamp` and its OpenAPI declares them as
    /// unformatted strings, so a pulled row can legitimately carry any of
    /// these — a space where ISO-8601 wants `T`, a two-digit offset where it
    /// wants four, a fraction of any length, or no offset at all.
    /// `ISO8601DateFormatter` rejects every one, and a value it rejects is
    /// stored verbatim and then sorts before every normalised stamp.
    @Test("every Postgres spelling adh can send normalises to the same instant")
    func postgresFormsNormalise() throws {
        let equivalents = [
            "2026-04-13 16:18:07.798+00",
            "2026-04-13T16:18:07.798+00:00",
            "2026-04-13 16:18:07.798000",
            "2026-04-13 16:18:07.798Z",
            "2026-04-13 16:18:07.798"
        ]
        for text in equivalents {
            let date = try #require(MarkdownTimestamp.date(text), "\(text) did not parse")
            #expect(MarkdownTimestamp.string(date) == "2026-04-13T16:18:07.798Z", "\(text)")
        }
    }

    /// A missing offset is read as UTC, but a present one is honoured — the
    /// repair must not flatten a real zone into `Z`.
    @Test("a non-zero offset is honoured, not assumed to be UTC")
    func offsetIsHonoured() throws {
        let date = try #require(MarkdownTimestamp.date("2026-04-13 12:18:07.798-04"))
        #expect(MarkdownTimestamp.string(date) == "2026-04-13T16:18:07.798Z")
    }
}
