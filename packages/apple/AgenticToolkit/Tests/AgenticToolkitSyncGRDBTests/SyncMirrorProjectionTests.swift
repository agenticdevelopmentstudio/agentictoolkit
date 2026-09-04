import Testing
import Foundation
import GRDB
import AgenticToolkitDatabase
import AgenticToolkitSync
@testable import AgenticToolkitSyncGRDB

/// A projection over one resource, storing it in two real columns.
private final class TestProjection: SyncMirrorProjection, @unchecked Sendable {

    let resources: Set<String> = ["test.people"]

    func createTables(in conn: Database) throws {
        try conn.execute(sql: """
            CREATE TABLE IF NOT EXISTS people (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL DEFAULT '',
                sync_version INTEGER NOT NULL DEFAULT 0,
                deleted_at TEXT);
            """)
    }

    func upsert(resource: String, id: String, syncVersion: Int,
                data: [String: JSONValue], in conn: Database) throws {
        let name: String
        if case .string(let value) = data["name"] { name = value } else { name = "" }
        try conn.execute(
            sql: """
                INSERT INTO people (id, name, sync_version, deleted_at) VALUES (?, ?, ?, NULL)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name,
                    sync_version = excluded.sync_version, deleted_at = NULL
                """,
            arguments: [id, name, syncVersion])
    }

    func markDeleted(resource: String, id: String, syncVersion: Int?, in conn: Database) throws {
        try conn.execute(
            sql: """
                UPDATE people SET deleted_at = datetime('now'),
                    sync_version = COALESCE(?, sync_version) WHERE id = ?
                """,
            arguments: [syncVersion, id])
    }

    func setSyncVersion(_ version: Int, resource: String, id: String, in conn: Database) throws {
        try conn.execute(sql: "UPDATE people SET sync_version = ? WHERE id = ?", arguments: [version, id])
    }

    func syncVersion(resource: String, id: String, in conn: Database) throws -> Int? {
        try Int.fetchOne(conn, sql: "SELECT sync_version FROM people WHERE id = ?", arguments: [id])
    }

    func truncate(resources: [String], in conn: Database) throws {
        try conn.execute(sql: "DELETE FROM people")
    }

    func rows(resource: String, limit: Int, offset: Int, in conn: Database) throws -> [[String: JSONValue]] {
        try Row.fetchAll(
            conn,
            sql: "SELECT id, name FROM people WHERE deleted_at IS NULL ORDER BY id LIMIT ? OFFSET ?",
            arguments: [limit, offset]
        ).map { ["id": .string($0["id"]), "name": .string($0["name"])] }
    }

    func row(resource: String, id: String, in conn: Database) throws -> [String: JSONValue]? {
        try Row.fetchOne(
            conn,
            sql: "SELECT id, name FROM people WHERE id = ? AND deleted_at IS NULL",
            arguments: [id]
        ).map { ["id": .string($0["id"]), "name": .string($0["name"])] }
    }
}

@Suite("SyncMirrorProjection")
struct SyncMirrorProjectionTests {

    private func store(projected: Bool) throws -> GRDBSyncStore {
        let database = try BoundedDatabase(path: ":memory:")
        return GRDBSyncStore(
            database: database,
            projection: projected ? TestProjection() : nil)
    }

    private let resources = [
        SyncResource(resource: "test.people", schemaVersion: 1),
        SyncResource(resource: "test.other", schemaVersion: 1)
    ]

    @Test("a projected resource gets the projection's tables, not a generic mirror")
    func projectedResourceSkipsGenericMirror() async throws {
        let store = try store(projected: true)
        try await store.prepare(resources: resources)
        try store.database.read { (conn: Database) throws in
            #expect(try conn.tableExists("people"))
            #expect(try conn.tableExists("test_people") == false)
            #expect(try conn.tableExists("test_other"))     // unprojected: unchanged
        }
    }

    @Test("a pulled change lands in the projection's columns")
    func applyRoutesToProjection() async throws {
        let store = try store(projected: true)
        try await store.prepare(resources: resources)
        try await store.apply([
            SyncChange(resource: "test.people", id: "p1", op: .upsert,
                       syncVersion: "7", data: ["name": .string("Ada")])
        ], advancingTo: nil)
        #expect(try store.liveRow(resource: "test.people", id: "p1") == ["id": .string("p1"), "name": .string("Ada")])
        try store.database.read { (conn: Database) throws in
            #expect(try String.fetchOne(conn, sql: "SELECT name FROM people WHERE id = 'p1'") == "Ada")
            #expect(try Int.fetchOne(conn, sql: "SELECT sync_version FROM people WHERE id = 'p1'") == 7)
        }
    }

    @Test("a pulled delete tombstones the projected row")
    func applyDeleteRoutesToProjection() async throws {
        let store = try store(projected: true)
        try await store.prepare(resources: resources)
        try await store.apply([
            SyncChange(resource: "test.people", id: "p1", op: .upsert, syncVersion: "1", data: ["name": .string("Ada")])
        ], advancingTo: nil)
        try await store.apply([
            SyncChange(resource: "test.people", id: "p1", op: .delete, syncVersion: "2", data: nil)
        ], advancingTo: nil)
        #expect(try store.liveRow(resource: "test.people", id: "p1") == nil)
        #expect(try store.liveRows(resource: "test.people").isEmpty)
    }

    @Test("a local mutation reads its base version from the projection")
    func stageReadsProjectedVersion() async throws {
        let store = try store(projected: true)
        try await store.prepare(resources: resources)
        try await store.apply([
            SyncChange(resource: "test.people", id: "p1", op: .upsert, syncVersion: "9", data: ["name": .string("Ada")])
        ], advancingTo: nil)
        try await store.stage(LocalMutation(
            resource: "test.people", rowId: "p1", type: .upsert, data: ["name": .string("Grace")]))

        let ops = try await store.pendingOps(limit: 10)
        #expect(ops.count == 1)
        #expect(ops[0].baseVersion == "9")
        try store.database.read { (conn: Database) throws in
            #expect(try String.fetchOne(conn, sql: "SELECT name FROM people WHERE id = 'p1'") == "Grace")
        }
    }

    @Test("the synchronous overloads work inside a caller's own transaction")
    func synchronousOverloadsShareATransaction() throws {
        let database = try BoundedDatabase(path: ":memory:")
        let store = GRDBSyncStore(database: database, projection: TestProjection())
        try database.write { conn in
            try store.prepare(resources: resources, in: conn)
            try conn.execute(sql: "INSERT INTO people (id, name) VALUES ('p1', 'Ada')")
            try store.stage(LocalMutation(
                resource: "test.people", rowId: "p1", type: .upsert,
                data: ["name": .string("Ada")]), in: conn)
        }
        #expect(try store.liveRow(resource: "test.people", id: "p1")?["name"] == .string("Ada"))
    }

    @Test("resetting for resync empties the projected tables too")
    func resetTruncatesProjection() async throws {
        let store = try store(projected: true)
        try await store.prepare(resources: resources)
        try await store.apply([
            SyncChange(resource: "test.people", id: "p1", op: .upsert, syncVersion: "1", data: ["name": .string("Ada")])
        ], advancingTo: nil)
        try await store.resetForResync()
        #expect(try store.liveRows(resource: "test.people").isEmpty)
    }

    @Test("a store with no projection behaves exactly as before")
    func projectionFreeStoreIsUnchanged() async throws {
        let store = try store(projected: false)
        try await store.prepare(resources: resources)
        try await store.apply([
            SyncChange(resource: "test.people", id: "p1", op: .upsert,
                       syncVersion: "3", data: ["name": .string("Ada")])
        ], advancingTo: nil)
        try store.database.read { (conn: Database) throws in
            #expect(try conn.tableExists("test_people"))
            #expect(try conn.tableExists("people") == false)
        }
        #expect(try store.liveRow(resource: "test.people", id: "p1")
                == ["id": .string("p1"), "name": .string("Ada")])
    }

    @Test("an unprojected resource in a projected store keeps the JSON mirror")
    func unprojectedResourcesAreUntouched() async throws {
        let store = try store(projected: true)
        try await store.prepare(resources: resources)
        try await store.apply([
            SyncChange(resource: "test.other", id: "o1", op: .upsert,
                       syncVersion: "1", data: ["k": .string("v")])
        ], advancingTo: nil)
        #expect(try store.liveRow(resource: "test.other", id: "o1")
                == ["id": .string("o1"), "k": .string("v")])
    }
}
