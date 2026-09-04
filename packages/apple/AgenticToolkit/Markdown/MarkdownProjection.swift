import Foundation
import GRDB
import AgenticToolkitSync
import AgenticToolkitSyncGRDB

/// Routes adh's nine `content.*` resources into `MarkdownSchema`'s typed tables
/// instead of `GRDBSyncStore`'s generic JSON mirror.
///
/// It is a table-driven mapper rather than nine hand-written statements: a
/// resource is a table name plus a column list, and both directions are
/// generated from that one description. A column added to the DDL and forgotten
/// here would silently stop syncing, so the description lives next to the DDL's
/// own column list and the schema test asserts them both.
public struct MarkdownProjection: SyncMirrorProjection {

    /// The columns every mirrored table carries, minus `id` and `sync_version`,
    /// which the store passes separately.
    private static let commonColumns = [
        "customer_id", "ecosystem_id",
        "created_at", "updated_at", "deleted_at",
        "sync_stamped_at", "sync_txid"
    ]

    /// Columns whose incoming value is an ISO-8601 timestamp and must be
    /// round-tripped through `MarkdownTimestamp` before it is written — see
    /// `normalizedTimestamp(_:)`.
    private static let timestampColumns: Set<String> = ["created_at", "updated_at", "deleted_at"]

    /// `created_at`/`updated_at` are `NOT NULL` with no schema `DEFAULT` on
    /// every projected table, yet a local `stage(_:)` mutation never carries
    /// them — `MarkdownTaxonomy`'s `LocalMutation` payloads only ever hold
    /// the pushable fields, because the row's audit columns were already
    /// written moments earlier by the direct `INSERT` that preceded the
    /// `stage(_:)` call in the same transaction. SQLite validates `NOT NULL`
    /// on the row an `INSERT … ON CONFLICT` statement would build *before*
    /// it discovers the conflict and switches to `UPDATE`, so simply
    /// omitting these two columns (as every other absent column is) makes
    /// even the update-only path throw. They are therefore always bound —
    /// with a throwaway value when `data` omits them — but never listed in
    /// the `ON CONFLICT` `SET` clause unless `data` actually supplied them,
    /// so that throwaway value can never land on an existing row.
    private static let requiredWithNoDefault: Set<String> = ["created_at", "updated_at"]

    private static let specificColumns: [String: [String]] = [
        "content.markdown": [
            "title", "content", "frontmatter", "content_hash", "size_bytes",
            "current_version", "latest_version_id", "is_deleted", "public_route",
            "visibility", "stage", "owner_kind", "owner_id"
        ],
        "content.notes": ["markdown_id"],
        "content.docs": ["markdown_id"],
        "content.papers": ["markdown_id"],
        "content.categories": ["name", "description", "color", "icon", "sort_order"],
        "content.category_edges": ["parent_id", "child_id", "sort_order"],
        "content.category_items": ["category_id", "target_kind", "target_id", "sort_order"],
        "content.keywords": ["label", "color", "description"],
        "content.keyword_items": ["keyword_id", "target_kind", "target_id", "sort_order"]
    ]

    /// adh derives `title`, hashes `content`, sizes it and owns version
    /// history, so a client has no right to push a whole `content.markdown`
    /// row — nor a marker, which the document routes create and destroy.
    /// These four are `pullOnly` in `ADHSyncCatalog` for that reason, and
    /// `MarkdownStore` queues their edits over REST instead.
    public static let pullOnlyResources = [
        "content.markdown", "content.notes", "content.docs", "content.papers"
    ]

    public static let syncResources: [SyncResource] = specificColumns.keys.sorted().map {
        SyncResource(resource: $0, schemaVersion: 1)
    }

    public let resources = Set(specificColumns.keys)

    public init() {}

    private func table(for resource: String) -> String {
        String(resource.dropFirst("content.".count))
    }

    private func columns(for resource: String) -> [String] {
        Self.commonColumns + (Self.specificColumns[resource] ?? [])
    }

    /// Called from `GRDBSyncStore.prepare(resources:in:)`, which is itself
    /// preceded — on every path that actually reaches this projection today
    /// — by `MarkdownSchema.migrate(_:)` against the `BoundedDatabase` this
    /// connection belongs to (see `MarkdownStore.init`). That call goes
    /// through `DatabaseMigrator.migrate(_ writer: any DatabaseWriter)`,
    /// which only accepts a pool/queue, not the `Database` connection this
    /// method is handed — so the DDL cannot be (re-)run from here, and this
    /// is a deliberate no-op rather than a second migration pass. A host
    /// that builds a bare `GRDBSyncStore` directly on this projection, never
    /// calling `MarkdownSchema.migrate` itself, must do so before `prepare`
    /// — this method has no way to make that happen on its own.
    public func createTables(in conn: Database) throws {}

    /// Only the fields actually present in `data` are written — `.null` and
    /// "the key is absent" are different things here, not the same NULL.
    ///
    /// A local `stage(_:)` mutation (every `LocalMutation` `MarkdownTaxonomy`
    /// builds) carries a deliberate subset: the pushable fields only, never
    /// `customer_id`/`ecosystem_id`/`created_at`/… — those are already on
    /// the row from the direct `INSERT` `MarkdownTaxonomy` ran moments
    /// earlier in the same transaction. Binding every projected column
    /// unconditionally (the shape this method started with) turned that
    /// omission into `column = excluded.column` with `excluded.column`
    /// NULL — clobbering `customer_id` on every local create and tripping
    /// its `NOT NULL` the moment `MarkdownProjection` actually claimed
    /// `content.categories`/`content.keywords`/… (Task 10/11's tests never
    /// caught it: the Task 10 stub claimed nothing, so `stage(_:)` always
    /// fell through to the generic JSON mirror for these resources). Binding
    /// only the present keys means an `INSERT` leans on the table's own
    /// `DEFAULT`/`NOT NULL` for anything omitted, and an `ON CONFLICT`
    /// `UPDATE` leaves an omitted column untouched instead of blanking it —
    /// while a key sent explicitly as `.null` (adh clearing `public_route`,
    /// say) still lands as SQL NULL, because it *is* present.
    public func upsert(
        resource: String, id: String, syncVersion: Int,
        data: [String: JSONValue], in conn: Database
    ) throws {
        let present = columns(for: resource).filter { data[$0] != nil }
        let bound = columns(for: resource).filter {
            data[$0] != nil || Self.requiredWithNoDefault.contains($0)
        }
        let names = ["id", "sync_version"] + bound
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let assignments = (["sync_version"] + present)
            .map { "\($0) = excluded.\($0)" }
            .joined(separator: ", ")
        var arguments: [(any DatabaseValueConvertible)?] = [id, syncVersion]
        arguments += bound.map { column in
            data[column] != nil ? Self.value(data[column], column: column) : MarkdownTimestamp.string(Date())
        }
        try conn.execute(
            sql: """
                INSERT INTO \(table(for: resource)) (\(names.joined(separator: ", ")))
                VALUES (\(placeholders))
                ON CONFLICT(id) DO UPDATE SET \(assignments)
                """,
            arguments: StatementArguments(arguments))
    }

    public func markDeleted(
        resource: String, id: String, syncVersion: Int?, in conn: Database
    ) throws {
        let stamp = MarkdownTimestamp.string(Date())
        // `content.markdown` alone carries both tombstones, and every one of
        // its indexes filters on `is_deleted`, so setting only `deleted_at`
        // would leave a deleted document listed.
        let extra = resource == "content.markdown" ? ", is_deleted = 1" : ""
        try conn.execute(
            sql: """
                UPDATE \(table(for: resource))
                SET deleted_at = ?, updated_at = ?,
                    sync_version = COALESCE(?, sync_version)\(extra)
                WHERE id = ?
                """,
            arguments: [stamp, stamp, syncVersion, id])
    }

    public func setSyncVersion(
        _ version: Int, resource: String, id: String, in conn: Database
    ) throws {
        try conn.execute(
            sql: "UPDATE \(table(for: resource)) SET sync_version = ? WHERE id = ?",
            arguments: [version, id])
    }

    public func syncVersion(resource: String, id: String, in conn: Database) throws -> Int? {
        try Int.fetchOne(
            conn, sql: "SELECT sync_version FROM \(table(for: resource)) WHERE id = ?",
            arguments: [id])
    }

    /// `GRDBSyncStore.deleteMirrorRows(for:in:)` calls this once per
    /// resource, with a **singleton** `resources` array each time — never the
    /// full batch — so no ordering this method imposes on its own `resources`
    /// argument can sequence "children before parents" across separate
    /// calls. `resetForResync`/`purgeForIdentityChange` nonetheless issue
    /// every one of those calls inside a single `boundedDatabase.write`
    /// transaction (see `GRDBSyncStore.resetForResync`), so deferring
    /// foreign-key enforcement to the end of that transaction — rather than
    /// per-statement — lets `DELETE FROM markdown` run before its `notes`/
    /// `docs`/`papers` children are deleted in a later call, as long as every
    /// referencing row is gone by commit. `PRAGMA defer_foreign_keys` is
    /// connection-scoped and resets itself to `OFF` when the transaction
    /// ends, so setting it on every call is idempotent and never leaks past
    /// this write.
    ///
    /// This does not weaken the constraint for a genuinely partial purge:
    /// `purgeResources(["content.markdown"])` alone, without also purging its
    /// three marker resources in the same call, still fails at commit — the
    /// orphaned `notes`/`docs`/`papers` rows are never deleted, so the
    /// deferred check still trips. Nothing in this toolkit purges a subset of
    /// the markdown family today (`SyncEngine`'s `plan.disabled`/`plan.bumped`
    /// are driven by resource enrollment, not this schema's dependency
    /// shape), so that failure mode is latent rather than exercised.
    public func truncate(resources: [String], in conn: Database) throws {
        try conn.execute(sql: "PRAGMA defer_foreign_keys = ON")
        for resource in resources {
            try conn.execute(sql: "DELETE FROM \(table(for: resource))")
        }
    }

    public func rows(
        resource: String, limit: Int, offset: Int, in conn: Database
    ) throws -> [[String: JSONValue]] {
        try Row.fetchAll(
            conn,
            sql: """
                SELECT * FROM \(table(for: resource))
                WHERE deleted_at IS NULL ORDER BY id LIMIT ? OFFSET ?
                """,
            arguments: [limit, offset]
        ).map { materialize($0, resource: resource) }
    }

    public func row(resource: String, id: String, in conn: Database) throws -> [String: JSONValue]? {
        try Row.fetchOne(
            conn,
            sql: "SELECT * FROM \(table(for: resource)) WHERE id = ? AND deleted_at IS NULL",
            arguments: [id]
        ).map { materialize($0, resource: resource) }
    }

    // MARK: - Column values

    /// A wire value as a bound SQLite value. `nil` and `.null` are both NULL,
    /// which is what lets `frontmatter`, `public_route` and `latest_version_id`
    /// come back absent without a special case each.
    ///
    /// `created_at`/`updated_at`/`deleted_at` are round-tripped through
    /// `MarkdownTimestamp.date(_:)` then `.string(_:)` before they are bound.
    /// `.string` always emits the fractional (millisecond) form, but `.date`
    /// also accepts the non-fractional form a server row may carry — and `.`
    /// (0x2E) sorts before `Z` (0x5A) in ASCII, so an un-normalised
    /// `...00:00:00Z` would sort *after* a local `...00:00:00.500Z` under
    /// `idx_markdown_updated`, silently inverting order within the same
    /// second. A value that fails to parse is stored verbatim rather than
    /// dropped — it is unexpected, not proof the row is worthless.
    private static func value(_ json: JSONValue?, column: String) -> (any DatabaseValueConvertible)? {
        if timestampColumns.contains(column), case .string(let text) = json {
            return normalizedTimestamp(text)
        }
        switch json {
        case .string(let text): return text
        case .number(let number): return number == number.rounded() ? Int(number) : number
        case .bool(let flag): return flag ? 1 : 0
        case .null, .none: return nil
        case .array, .object:
            // Only `frontmatter` is structured, and adh sends it as a JSON
            // string, not an object. Anything else structured is stored as its
            // JSON text rather than dropped.
            guard let encoded = try? JSONEncoder().encode(json) else { return nil }
            return String(bytes: encoded, encoding: .utf8)
        }
    }

    private static func normalizedTimestamp(_ text: String) -> String {
        MarkdownTimestamp.date(text).map(MarkdownTimestamp.string) ?? text
    }

    private func materialize(_ row: Row, resource: String) -> [String: JSONValue] {
        var object: [String: JSONValue] = ["id": .string(row["id"])]
        for column in columns(for: resource) {
            guard let value = row[column] as DatabaseValue?, !value.isNull else { continue }
            switch value.storage {
            case .string(let text): object[column] = .string(text)
            case .int64(let number): object[column] = .number(Double(number))
            case .double(let number): object[column] = .number(number)
            default: continue
            }
        }
        return object
    }
}
