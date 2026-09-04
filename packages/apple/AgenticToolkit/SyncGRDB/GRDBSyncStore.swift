import Foundation
import GRDB
import AgenticToolkitDatabase
import AgenticToolkitSync

/// Snapshot of local sync bookkeeping, consumed by hosts (e.g. Plan 4's
/// `/adhd/sync/status` daemon endpoint).
public struct GRDBSyncStoreStatus: Codable, Sendable {
    public let cursor: String?
    public let outboxDepth: Int
    public let quarantinedDepth: Int
    public let conflictCount: Int
}

/// `SyncStore` on `BoundedDatabase` (WAL pool): JSON-payload mirror tables, an
/// outbox, and a conflicts audit. The mirror is fed only by apply()/stage();
/// it is NEVER deleted as a recovery path (resetForResync truncates tables,
/// preserving the outbox and the file; purgeForIdentityChange additionally
/// clears the outbox — see its doc comment for why — but still never touches
/// the file).
public final class GRDBSyncStore: SyncStore, @unchecked Sendable {

    private let boundedDatabase: BoundedDatabase
    private let queue = DispatchQueue(label: "GRDBSyncStore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Resources this host may pull but never push. `stage(_:)` refuses them
    /// up front with `SyncStoreFailure.pullOnlyResource` (twin of
    /// `InMemorySyncStore.pullOnlyResources`).
    private let pullOnlyResources: Set<String>
    /// Optional typed storage for a subset of resources. `nil` — the default —
    /// is the historical all-JSON behaviour.
    private let mirrorProjection: (any SyncMirrorProjection)?

    public init(
        database: BoundedDatabase,
        pullOnlyResources: Set<String> = [],
        projection: (any SyncMirrorProjection)? = nil
    ) {
        self.boundedDatabase = database
        self.pullOnlyResources = pullOnlyResources
        self.mirrorProjection = projection
    }

    public var database: BoundedDatabase { boundedDatabase }

    /// The projection, but only when it claims this resource.
    private func projection(for resource: String) -> (any SyncMirrorProjection)? {
        guard let mirrorProjection, mirrorProjection.resources.contains(resource) else { return nil }
        return mirrorProjection
    }

    /// Resource strings are interpolated directly into SQL as identifiers
    /// (SQLite has no bind-parameter syntax for identifiers), so this is the
    /// one chokepoint every caller below routes through — reject anything
    /// outside `[a-z0-9_.]` before it ever reaches a query string (sync
    /// fix-wave item p2l).
    public static func mirrorTableName(for resource: String) throws -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        guard !resource.isEmpty, resource.allSatisfy({ allowed.contains($0) }) else {
            throw SyncStoreFailure.unknownResource(resource)
        }
        return resource.replacingOccurrences(of: ".", with: "_")
    }

    /// Deletes the mirror rows of the REGISTERED subset of `resources` — each
    /// one filtered against `_sync_resources` first, so an unregistered resource
    /// (no mirror table was ever created for it) is silently skipped rather than
    /// throwing "no such table". This is the shared body of the three per-resource
    /// mirror-truncation sites (`resetForResync`, `purgeResources`,
    /// `purgeForIdentityChange`) — one place that "empty a mirror table" lives, so
    /// purging an unregistered resource is a no-op in every path (twin parity with
    /// `InMemorySyncStore.purgeResources`, which already no-ops the unknown key).
    private func deleteMirrorRows(for resources: [String], in conn: Database) throws {
        for resource in resources {
            let isRegistered = try Bool.fetchOne(
                conn, sql: "SELECT EXISTS(SELECT 1 FROM _sync_resources WHERE resource = ?)",
                arguments: [resource]
            ) ?? false
            guard isRegistered else { continue }
            if let projection = projection(for: resource) {
                try projection.truncate(resources: [resource], in: conn)
            } else {
                try conn.execute(sql: "DELETE FROM \"\(try Self.mirrorTableName(for: resource))\"")
            }
        }
    }

    private func onQueue<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    // MARK: - SyncStore

    /// The bookkeeping tables (as opposed to per-resource mirror tables).
    /// Idempotent (`CREATE TABLE IF NOT EXISTS`) so it's safe to run from
    /// both `prepare(resources:)` and `cursor()` — the engine's pull loop
    /// calls `cursor()` before it has a manifest to hand `prepare`, so on a
    /// truly cold store (no prior `prepare` call ever made) `cursor()` would
    /// otherwise throw "no such table: _sync_state" on the very first sync.
    private static let bookkeepingSchema = """
        CREATE TABLE IF NOT EXISTS _sync_state (id INTEGER PRIMARY KEY CHECK (id = 1), cursor TEXT);
        CREATE TABLE IF NOT EXISTS _sync_resources (
            resource TEXT PRIMARY KEY, schema_version INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS _sync_outbox (
            op_id TEXT PRIMARY KEY, resource TEXT NOT NULL, row_id TEXT NOT NULL,
            type TEXT NOT NULL, base_version TEXT, payload TEXT,
            status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS _sync_conflicts (
            id INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT, resource TEXT,
            row_id TEXT, reason TEXT, resolved_at TEXT NOT NULL);
        """

    public func prepare(resources: [SyncResource]) async throws {
        let store = self
        try await onQueue {
            try store.boundedDatabase.write { conn in
                try store.prepare(resources: resources, in: conn)
            }
        }
    }

    /// The body of `prepare(resources:)`, for a caller that already holds a
    /// write transaction. Taking the connection rather than opening one is what
    /// lets a store built on top of this one register its resources and create
    /// its own tables in a single transaction.
    public func prepare(resources: [SyncResource], in conn: Database) throws {
        try conn.execute(sql: Self.bookkeepingSchema)
        try mirrorProjection?.createTables(in: conn)
        for resource in resources {
            if projection(for: resource.resource) == nil {
                let table = try Self.mirrorTableName(for: resource.resource)
                try conn.execute(sql: """
                    CREATE TABLE IF NOT EXISTS "\(table)" (
                        id TEXT PRIMARY KEY NOT NULL,
                        sync_version INTEGER NOT NULL DEFAULT 0,
                        deleted_at TEXT,
                        data TEXT NOT NULL DEFAULT '{}');
                    """)
            }
            try conn.execute(
                sql: """
                    INSERT INTO _sync_resources (resource, schema_version) VALUES (?, ?)
                    ON CONFLICT(resource) DO UPDATE SET schema_version = excluded.schema_version
                    """,
                arguments: [resource.resource, resource.schemaVersion]
            )
        }
    }

    public func cursor() async throws -> SyncCursor? {
        let boundedDatabase = self.boundedDatabase
        return try await onQueue {
            try boundedDatabase.write { conn in
                try conn.execute(sql: Self.bookkeepingSchema)
                return try String.fetchOne(conn, sql: "SELECT cursor FROM _sync_state WHERE id = 1")
            }.map(SyncCursor.init(rawValue:))
        }
    }

    public func apply(_ batch: [SyncChange], advancingTo cursor: SyncCursor?) async throws {
        let store = self
        let encoder = self.encoder
        try await onQueue {
            try store.boundedDatabase.write { conn in
                for change in batch {
                    let isKnown = try Bool.fetchOne(
                        conn, sql: "SELECT EXISTS(SELECT 1 FROM _sync_resources WHERE resource = ?)",
                        arguments: [change.resource]
                    ) ?? false
                    guard isKnown else {
                        throw SyncStoreFailure.unknownResource(change.resource)
                    }
                    // Strict: reject an unparseable syncVersion rather than
                    // silently coercing to 0 and corrupting the mirror's version
                    // ordering. Two distinct sources feed this guard, and only one
                    // is wire-validated: a *pulled* change's syncVersion is
                    // guaranteed `/^\d+$/` by the wire schema (adh src/sync/wire.ts),
                    // but a change synthesized from a conflict's `current` blob is
                    // NOT — that blob is unvalidated on the wire. The engine
                    // pre-screens conflict adoptions numerically (SyncEngine
                    // `adoptedVersion`, quarantining a non-numeric current before it
                    // ever reaches apply), so by the time we get here the value is
                    // either wire-guaranteed (pull) or engine-guaranteed (adoption);
                    // a failure here therefore means something upstream is genuinely
                    // broken, hence the loud throw.
                    guard let version = Int(change.syncVersion) else {
                        throw SyncStoreFailure.invalidChange("unparseable syncVersion: \(change.syncVersion)")
                    }
                    if let projection = store.projection(for: change.resource) {
                        if change.op == .delete {
                            try projection.markDeleted(
                                resource: change.resource, id: change.id,
                                syncVersion: version, in: conn)
                        } else {
                            try projection.upsert(
                                resource: change.resource, id: change.id, syncVersion: version,
                                data: change.data ?? [:], in: conn)
                        }
                        continue
                    }
                    let table = try Self.mirrorTableName(for: change.resource)
                    if change.op == .delete {
                        try conn.execute(
                            sql: """
                                INSERT INTO "\(table)" (id, sync_version, deleted_at, data)
                                VALUES (?, ?, datetime('now'), '{}')
                                ON CONFLICT(id) DO UPDATE SET
                                    sync_version = excluded.sync_version, deleted_at = excluded.deleted_at, data = '{}'
                                """,
                            arguments: [change.id, version]
                        )
                    } else {
                        let payload = String(data: try encoder.encode(change.data ?? [:]), encoding: .utf8) ?? "{}"
                        try conn.execute(
                            sql: """
                                INSERT INTO "\(table)" (id, sync_version, deleted_at, data) VALUES (?, ?, NULL, ?)
                                ON CONFLICT(id) DO UPDATE SET
                                    sync_version = excluded.sync_version, deleted_at = NULL, data = excluded.data
                                """,
                            arguments: [change.id, version, payload]
                        )
                    }
                }
                if let cursor {
                    try conn.execute(
                        sql: """
                            INSERT INTO _sync_state (id, cursor) VALUES (1, ?)
                            ON CONFLICT(id) DO UPDATE SET cursor = excluded.cursor
                            """,
                        arguments: [cursor.rawValue]
                    )
                }
            }
        }
    }

    /// Local mutation: optimistic mirror write + outbox op, atomic. If a
    /// `pending` (not yet `inflight`/`quarantined`) outbox op already exists
    /// for this (resource, rowId), it is coalesced in place — same opId,
    /// same original `baseVersion` (the version the user's edits started
    /// from) — rather than minting a second op with a now-stale baseVersion
    /// that would conflict against the first on push. See sync fix-wave
    /// item p2a: two ops with the same baseVersion → server applies the
    /// first and stale-conflicts the second, silently dropping the newer
    /// edit.
    ///
    /// The resource must already be registered via `prepare(resources:)` —
    /// staging offline for an unprepared resource throws
    /// `SyncStoreFailure.unknownResource` rather than a raw SQL error
    /// against a mirror table that was never created (sync fix-wave item
    /// p2o).
    public func stage(_ mutation: LocalMutation) async throws {
        // Pull-only guard first, before any DB work — twin-identical ordering
        // to InMemorySyncStore.stage (pull-only refusal precedes the
        // unknown-resource check).
        guard !pullOnlyResources.contains(mutation.resource) else {
            throw SyncStoreFailure.pullOnlyResource(mutation.resource)
        }
        let store = self
        try await onQueue {
            try store.boundedDatabase.write { conn in
                try store.stage(mutation, in: conn)
            }
        }
    }

    /// The body of `stage(_:)`, for a caller that already holds a write
    /// transaction — the mirror write and the outbox op must land together,
    /// and `stage(_:)`'s queue hop would lose the caller's transaction and
    /// deadlock the pool's writer.
    public func stage(_ mutation: LocalMutation, in conn: Database) throws {
        guard !pullOnlyResources.contains(mutation.resource) else {
            throw SyncStoreFailure.pullOnlyResource(mutation.resource)
        }
        let isKnown = try Bool.fetchOne(
            conn, sql: "SELECT EXISTS(SELECT 1 FROM _sync_resources WHERE resource = ?)",
            arguments: [mutation.resource]
        ) ?? false
        guard isKnown else {
            throw SyncStoreFailure.unknownResource(mutation.resource)
        }

        let base: Int?
        if let projection = projection(for: mutation.resource) {
            base = try projection.syncVersion(resource: mutation.resource, id: mutation.rowId, in: conn)
            if mutation.type == .delete {
                try projection.markDeleted(
                    resource: mutation.resource, id: mutation.rowId, syncVersion: nil, in: conn)
            } else {
                try projection.upsert(
                    resource: mutation.resource, id: mutation.rowId, syncVersion: base ?? 0,
                    data: mutation.data ?? [:], in: conn)
            }
        } else {
            let table = try Self.mirrorTableName(for: mutation.resource)
            base = try Int.fetchOne(
                conn, sql: "SELECT sync_version FROM \"\(table)\" WHERE id = ?", arguments: [mutation.rowId]
            )
            if mutation.type == .delete {
                try conn.execute(
                    sql: "UPDATE \"\(table)\" SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [mutation.rowId]
                )
            } else {
                let payload = String(data: try encoder.encode(mutation.data ?? [:]), encoding: .utf8) ?? "{}"
                try conn.execute(
                    sql: """
                        INSERT INTO "\(table)" (id, sync_version, deleted_at, data) VALUES (?, ?, NULL, ?)
                        ON CONFLICT(id) DO UPDATE SET deleted_at = NULL, data = excluded.data
                        """,
                    arguments: [mutation.rowId, base ?? 0, payload]
                )
            }
        }

        let existing = try Row.fetchOne(
            conn,
            sql: """
                SELECT op_id, payload FROM _sync_outbox
                WHERE resource = ? AND row_id = ? AND status = 'pending' LIMIT 1
                """,
            arguments: [mutation.resource, mutation.rowId]
        )
        if let existing {
            let opId: String = existing["op_id"]
            let mergedPayload: [String: JSONValue]
            switch mutation.type {
            case .upsert:
                let existingPayload: [String: JSONValue] = try (existing["payload"] as String?)
                    .flatMap { $0.data(using: .utf8) }
                    .map { try decoder.decode([String: JSONValue].self, from: $0) } ?? [:]
                mergedPayload = existingPayload.merging(mutation.data ?? [:]) { _, new in new }
            case .delete:
                mergedPayload = [:]
            }
            let mergedPayloadString = String(data: try encoder.encode(mergedPayload), encoding: .utf8) ?? "{}"
            try conn.execute(
                sql: "UPDATE _sync_outbox SET type = ?, payload = ? WHERE op_id = ?",
                arguments: [mutation.type.rawValue, mergedPayloadString, opId]
            )
        } else {
            let opPayload = String(data: try encoder.encode(mutation.data ?? [:]), encoding: .utf8) ?? "{}"
            try conn.execute(
                sql: """
                    INSERT INTO _sync_outbox
                        (op_id, resource, row_id, type, base_version, payload, status, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'pending', datetime('now'))
                    """,
                arguments: [SyncID.uuidV7(), mutation.resource, mutation.rowId, mutation.type.rawValue,
                            base.map(String.init), opPayload]
            )
        }
    }

    /// Returns up to `limit` outbox ops in insertion order (`rowid` — the
    /// FIFO order the ops were created in), and marks every returned op
    /// `inflight` in the same transaction. Ops already `inflight` (from a
    /// prior call whose push never completed — a crash, or a server
    /// round-trip still outstanding) are included again: replaying the same
    /// opIds on retry is the server contract's idempotency guarantee.
    public func pendingOps(limit: Int) async throws -> [SyncPushOp] {
        let boundedDatabase = self.boundedDatabase
        let decoder = self.decoder
        return try await onQueue {
            try boundedDatabase.write { conn in
                let rows = try Row.fetchAll(
                    conn,
                    sql: """
                        SELECT op_id, resource, row_id, type, base_version, payload FROM _sync_outbox
                        WHERE status IN ('pending', 'inflight') ORDER BY rowid LIMIT ?
                        """,
                    arguments: [limit]
                )
                let opIds: [String] = rows.map { $0["op_id"] }
                if !opIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: opIds.count).joined(separator: ", ")
                    try conn.execute(
                        sql: "UPDATE _sync_outbox SET status = 'inflight' WHERE op_id IN (\(placeholders))",
                        arguments: StatementArguments(opIds)
                    )
                }
                return try rows.map { row in
                    let payload: [String: JSONValue] = try (row["payload"] as String?)
                        .flatMap { $0.data(using: .utf8) }
                        .map { try decoder.decode([String: JSONValue].self, from: $0) } ?? [:]
                    let typeColumn: String = row["type"]
                    // Strict: a corrupt/unrecognized `type` column means the
                    // outbox row can't be trusted — silently defaulting to
                    // `.upsert` could push a mutation the caller never made
                    // (e.g. resurrect a row that was actually staged as a
                    // delete). Fail loudly instead.
                    guard let type = SyncChangeOp(rawValue: typeColumn) else {
                        throw SyncStoreFailure.invalidChange("corrupt outbox type column: \(typeColumn)")
                    }
                    return SyncPushOp(
                        opId: row["op_id"],
                        resource: row["resource"],
                        rowId: row["row_id"],
                        type: type,
                        baseVersion: row["base_version"],
                        data: payload.isEmpty ? nil : payload
                    )
                }
            }
        }
    }

    public func complete(_ results: [SyncPushResult]) async throws {
        let store = self
        try await onQueue {
            try store.boundedDatabase.write { conn in
                for result in results {
                    switch result.status {
                    case .applied, .conflict:
                        let meta = try Row.fetchOne(
                            conn, sql: "SELECT resource, row_id FROM _sync_outbox WHERE op_id = ?",
                            arguments: [result.opId]
                        )
                        if result.status == .conflict {
                            try conn.execute(
                                sql: """
                                    INSERT INTO _sync_conflicts (op_id, resource, row_id, reason, resolved_at)
                                    VALUES (?, ?, ?, ?, datetime('now'))
                                    """,
                                arguments: [
                                    result.opId, meta?["resource"] as String?, meta?["row_id"] as String?,
                                    result.reason
                                ]
                            )
                        } else if let newVersion = result.newVersion,
                                  let resource = meta?["resource"] as String?,
                                  let rowId = meta?["row_id"] as String? {
                            // Adopt the server's post-apply sync_version onto the mirror
                            // row BEFORE deleting the outbox row, in the same
                            // transaction, so a stage() call racing this completion
                            // (or arriving right after it) snapshots the correct
                            // baseVersion — closing the stage-during-push
                            // self-conflict race (adh sync.md §3).
                            //
                            // Strict, same rationale as item (g): `Int(newVersion) ?? 0`
                            // would silently stamp sync_version = 0 on an unparseable
                            // value, corrupting the mirror row's ordering. But unlike
                            // apply()'s invalidChange throw, this runs inside the push
                            // completion transaction — throwing here would abort the
                            // whole transaction, leave the outbox row in place, and
                            // wedge on replay even though the server already applied the
                            // op. So: skip adoption (treat as absent) rather than throw;
                            // the outbox row is still deleted below.
                            if let intVersion = Int(newVersion) {
                                if let projection = store.projection(for: resource) {
                                    try projection.setSyncVersion(
                                        intVersion, resource: resource, id: rowId, in: conn)
                                } else {
                                    let table = try Self.mirrorTableName(for: resource)
                                    try conn.execute(
                                        sql: "UPDATE \"\(table)\" SET sync_version = ? WHERE id = ?",
                                        arguments: [intVersion, rowId]
                                    )
                                }
                            }
                        }
                        try conn.execute(sql: "DELETE FROM _sync_outbox WHERE op_id = ?", arguments: [result.opId])
                    case .rejected:
                        try conn.execute(
                            sql: """
                                UPDATE _sync_outbox SET status = 'quarantined', attempts = attempts + 1
                                WHERE op_id = ?
                                """,
                            arguments: [result.opId]
                        )
                    }
                }
            }
        }
    }

    public func resetForResync() async throws {
        let store = self
        try await onQueue {
            try store.boundedDatabase.write { conn in
                let tables = try String.fetchAll(conn, sql: "SELECT resource FROM _sync_resources")
                try store.deleteMirrorRows(for: tables, in: conn)
                try conn.execute(sql: "DELETE FROM _sync_state")
            }
        }
    }

    /// resource -> registered schema_version, the twin of
    /// `InMemorySyncStore.registrations()`. Bootstraps the bookkeeping schema
    /// first (same cold-start rationale as `cursor()`): on a never-prepared
    /// store this returns `[:]` rather than throwing "no such table:
    /// _sync_resources".
    public func registrations() async throws -> [String: Int] {
        let boundedDatabase = self.boundedDatabase
        return try await onQueue {
            try boundedDatabase.write { conn in
                try conn.execute(sql: Self.bookkeepingSchema)
                var out: [String: Int] = [:]
                let rows = try Row.fetchAll(
                    conn, sql: "SELECT resource, schema_version FROM _sync_resources")
                for row in rows { out[row["resource"]] = row["schema_version"] }
                return out
            }
        }
    }

    /// Enrollment-disable transition (twin of
    /// `InMemorySyncStore.purgeResources`): for each named resource, empty its
    /// mirror table, move its `pending`/`inflight` outbox ops to
    /// `quarantined` (never dropped — a fixed retry must re-`stage` for a
    /// fresh opId; already-`quarantined`/completed rows untouched), and remove
    /// its registration. The cursor (`_sync_state`) is deliberately left
    /// untouched. Like the other recovery paths this only ever `DELETE`s rows
    /// — it never drops a table or touches the database file.
    public func purgeResources(_ resources: [String]) async throws {
        guard !resources.isEmpty else { return }
        let store = self
        try await onQueue {
            try store.boundedDatabase.write { conn in
                // Empty the mirror rows of the registered subset only — an
                // unregistered resource has no mirror table, so its purge is a
                // silent no-op (twin of InMemorySyncStore.purgeResources) rather
                // than a "no such table" throw.
                try store.deleteMirrorRows(for: resources, in: conn)
                for resource in resources {
                    try conn.execute(
                        sql: """
                            UPDATE _sync_outbox SET status = 'quarantined'
                            WHERE resource = ? AND status IN ('pending', 'inflight')
                            """,
                        arguments: [resource])
                    try conn.execute(
                        sql: "DELETE FROM _sync_resources WHERE resource = ?",
                        arguments: [resource])
                }
            }
        }
    }

    /// Account-boundary purge: call this when the signed-in identity itself
    /// changes (sign-out, switch account) — not for an ordinary resync.
    /// In one write transaction: every registered mirror table is emptied,
    /// `_sync_state` (the cursor) is cleared, and every `_sync_outbox` row is
    /// deleted regardless of status — `pending`, `inflight`, *and*
    /// `quarantined` alike.
    ///
    /// This is the deliberate difference from `resetForResync()`, which
    /// preserves the outbox: a resync happens because the *data* needs
    /// re-fetching while the identity performing it is unchanged, so
    /// queued local edits are still owed to the server under that same
    /// identity and must survive. Here the identity itself is changing —
    /// every queued op belongs to the *departing* identity, and pushing it
    /// under a new identity's credentials would misattribute the mutation.
    /// That's the defect this method exists to close; nothing may survive
    /// the boundary except the app-level resource registrations.
    ///
    /// `_sync_resources` is intentionally left untouched: it's the set of
    /// resources this app knows how to sync (from `prepare(resources:)`),
    /// not per-identity state — the next identity needs the same
    /// registrations, and callers should not need to re-`prepare` before
    /// their first post-purge `stage(_:)`.
    ///
    /// `_sync_conflicts` (the audit log) is also left untouched — it's a
    /// historical record, not live sync state, and isn't read back into any
    /// sync decision.
    ///
    /// Like `resetForResync()`, this never touches the database file itself
    /// — only rows within it, in one transaction.
    public func purgeForIdentityChange() async throws {
        let store = self
        try await onQueue {
            try store.boundedDatabase.write { conn in
                let tables = try String.fetchAll(conn, sql: "SELECT resource FROM _sync_resources")
                try store.deleteMirrorRows(for: tables, in: conn)
                try conn.execute(sql: "DELETE FROM _sync_state")
                try conn.execute(sql: "DELETE FROM _sync_outbox")
            }
        }
    }

    // MARK: - Read helpers (hosts: daemon serving + UI observation)

    /// The resource must already be registered via `prepare(resources:)`;
    /// an unregistered resource throws `SyncStoreFailure.unknownResource`
    /// (checked against `_sync_resources` before the mirror table is even
    /// named — sync fix-wave item p2o).
    ///
    /// Offset pagination here is contract-bound, not a free design choice:
    /// the mirror deliberately shadows the backend's own offset/limit REST
    /// paging contract, because the daemon is a transparent proxy — it
    /// cannot invent a different paging API for its offline fallback.
    /// `O(offset)` is therefore accepted rather than eliminated: callers cap
    /// `limit` (`MirrorServer`'s `listLimit`, currently 200), which bounds
    /// how deep a page scan can go. `ORDER BY id` rides the mirror table's
    /// primary-key index for free; access beyond `id` would go through the
    /// JSON1 expressions over the `data` blob by design — the mirror stores
    /// arbitrary resource fields schema-evolution-free, without a typed
    /// column per field, so there is nowhere else for non-PK access to live.
    public func liveRows(resource: String, limit: Int = 100, offset: Int = 0) throws -> [[String: JSONValue]] {
        try boundedDatabase.read { conn in
            let isKnown = try Bool.fetchOne(
                conn, sql: "SELECT EXISTS(SELECT 1 FROM _sync_resources WHERE resource = ?)",
                arguments: [resource]
            ) ?? false
            guard isKnown else {
                throw SyncStoreFailure.unknownResource(resource)
            }
            if let projection = self.projection(for: resource) {
                return try projection.rows(resource: resource, limit: limit, offset: offset, in: conn)
            }
            let table = try Self.mirrorTableName(for: resource)
            let rows = try Row.fetchAll(
                conn,
                sql: "SELECT id, data FROM \"\(table)\" WHERE deleted_at IS NULL ORDER BY id LIMIT ? OFFSET ?",
                arguments: [limit, offset]
            )
            return try rows.map { try self.materialize($0) }
        }
    }

    /// Same unregistered-resource contract as `liveRows` above.
    public func liveRow(resource: String, id: String) throws -> [String: JSONValue]? {
        try boundedDatabase.read { conn in
            let isKnown = try Bool.fetchOne(
                conn, sql: "SELECT EXISTS(SELECT 1 FROM _sync_resources WHERE resource = ?)",
                arguments: [resource]
            ) ?? false
            guard isKnown else {
                throw SyncStoreFailure.unknownResource(resource)
            }
            if let projection = self.projection(for: resource) {
                return try projection.row(resource: resource, id: id, in: conn)
            }
            let table = try Self.mirrorTableName(for: resource)
            return try Row.fetchOne(
                conn,
                sql: "SELECT id, data FROM \"\(table)\" WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            ).map { try self.materialize($0) }
        }
    }

    private func materialize(_ row: Row) throws -> [String: JSONValue] {
        var object = try ((row["data"] as String?)?.data(using: .utf8))
            .map { try decoder.decode([String: JSONValue].self, from: $0) } ?? [:]
        object["id"] = .string(row["id"])
        return object
    }

    public func registeredResources() throws -> Set<String> {
        try boundedDatabase.read { conn in
            Set(try String.fetchAll(conn, sql: "SELECT resource FROM _sync_resources"))
        }
    }

    public func status() throws -> GRDBSyncStoreStatus {
        try boundedDatabase.read { conn in
            // pending + inflight: both are unresolved ops still owed to the
            // server (inflight just means a push round-trip is outstanding).
            let outboxDepth = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM _sync_outbox WHERE status IN ('pending', 'inflight')"
            ) ?? 0
            let quarantinedDepth = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM _sync_outbox WHERE status = 'quarantined'"
            ) ?? 0
            return GRDBSyncStoreStatus(
                cursor: try String.fetchOne(conn, sql: "SELECT cursor FROM _sync_state WHERE id = 1"),
                outboxDepth: outboxDepth,
                quarantinedDepth: quarantinedDepth,
                conflictCount: try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM _sync_conflicts") ?? 0
            )
        }
    }
}
