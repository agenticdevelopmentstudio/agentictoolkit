import Foundation
import GRDB
import AgenticToolkitSync
import AgenticToolkitSyncGRDB

/// Routes adh's nine `content.*` resources into `MarkdownSchema`'s typed tables
/// instead of `GRDBSyncStore`'s generic JSON mirror.
///
/// It is a table-driven mapper rather than nine hand-written statements: a
/// resource is a table name plus a column list, and both directions are
/// generated from that one description. `resources`/`syncResources` derive
/// from `MarkdownSchema.tables` directly, so the set of resources this
/// projection claims cannot drift from the DDL's own table list — a table
/// added to the schema and forgotten here is structurally impossible. The
/// per-resource *column* lists in `specificColumns` below are still
/// hand-maintained prose, though, so a column added to one table's DDL and
/// forgotten in its entry here is not caught by the type system; the
/// regression test `MarkdownProjectionTests.columnListsMatchTheRealSchema`
/// cross-checks every resource's known columns against `PRAGMA
/// table_info(...)` at runtime to catch that drift instead.
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
    /// `normalizedTimestamp(_:)`. `sync_stamped_at` is on every projected
    /// table and comes straight off the wire like the other three; nothing
    /// orders or range-filters on it today, but if that ever changes it
    /// inherits the same `.`-before-`Z` inversion this task exists to kill,
    /// so it is normalised now rather than left as a trap for later.
    private static let timestampColumns: Set<String> = [
        "created_at", "updated_at", "deleted_at", "sync_stamped_at"
    ]

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

    /// The single source of truth for which resources this projection
    /// claims — `MarkdownSchema.tables` itself, so `resources` and
    /// `syncResources` cannot name a resource the schema doesn't create a
    /// table for, or vice versa.
    private static let resourceNames: [String] = MarkdownSchema.tables.map { "content.\($0)" }

    public static let syncResources: [SyncResource] = resourceNames.map {
        SyncResource(resource: $0, schemaVersion: 1)
    }

    public let resources = Set(resourceNames)

    public init() {}

    private func table(for resource: String) -> String {
        String(resource.dropFirst("content.".count))
    }

    private func columns(for resource: String) -> [String] {
        Self.commonColumns + (Self.specificColumns[resource] ?? [])
    }

    /// Exposed for `MarkdownProjectionTests.columnListsMatchTheRealSchema`:
    /// the full set of columns this projection expects a resource's table to
    /// have, `id` and `sync_version` included — the two `columns(for:)`
    /// leaves out because the store passes them separately.
    static func knownColumns(for resource: String) -> Set<String> {
        Set(["id", "sync_version"] + commonColumns + (specificColumns[resource] ?? []))
    }

    /// Called from `GRDBSyncStore.prepare(resources:in:)`. On the
    /// `MarkdownStore` path this is redundant — `MarkdownStore.init` already
    /// ran `MarkdownSchema.migrate(_:)` against the same database before
    /// `prepare` ever runs — but `MarkdownSchema.createTables(in:)` is every
    /// `CREATE TABLE/INDEX IF NOT EXISTS` statement the schema owns, so
    /// running it twice is a no-op, not a second migration pass (it is a
    /// direct DDL run, not `DatabaseMigrator`, which has no `Database`-taking
    /// overload — only `migrate(_ writer: any DatabaseWriter)` — and so
    /// could not be called from here regardless). This is what makes the
    /// `SyncMirrorProjection` contract actually hold for a host that builds a
    /// bare `GRDBSyncStore` directly on this projection without going
    /// through `MarkdownStore`: `prepare` alone now leaves it with a working
    /// schema instead of "no such table: markdown" on the first pulled
    /// change.
    public func createTables(in conn: Database) throws {
        try MarkdownSchema.createTables(in: conn)
    }

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
    ///
    /// This is the `isFullRow`-unaware requirement `SyncMirrorProjection`
    /// declares; it forwards to the `isFullRow`-aware overload below with
    /// `isFullRow: true`, which is this method's only historical meaning —
    /// nothing calls this overload directly any more (`GRDBSyncStore`'s two
    /// call sites both use the overload below), it exists purely to satisfy
    /// the protocol's still-required original signature.
    public func upsert(
        resource: String, id: String, syncVersion: Int,
        data: [String: JSONValue], in conn: Database
    ) throws {
        // `true` is the full-row assumption; a partial-patch caller must use the
        // 6-parameter `isFullRow:` overload below, or this reintroduces tombstone
        // resurrection with no compile-time signal.
        try upsert(resource: resource, id: id, syncVersion: syncVersion, data: data, isFullRow: true, in: conn)
    }

    /// `isFullRow` distinguishes `apply`'s pull path (`true` — adh's whole
    /// current row) from `stage(_:)`'s local path (`false` — a deliberate
    /// partial patch, see the doc comment above). Round 1 force-bound
    /// `deleted_at`/`is_deleted` unconditionally, which fixed the pull path
    /// but was reachable from `stage(_:)` too — nothing stops a future
    /// taxonomy write method from staging a partial patch against an
    /// existing, previously-deleted row, and the force-bind would silently
    /// resurrect it (clear `deleted_at`) even though the patch never
    /// mentioned it. `isFullRow` makes the two paths tell `upsert` which one
    /// they are instead of relying on an audited-but-unenforced invariant
    /// about every current `stage(_:)` call site staging immediately after
    /// its own fresh `INSERT`: the delete-state columns are force-bound only
    /// when `isFullRow` is `true`.
    ///
    /// On a full-row pull, forcing `deleted_at` closes the hole a pulled
    /// delete-then-restore would otherwise fall into: the restore lands as
    /// one `upsert` call whose payload never mentions `deleted_at` (adh's
    /// wire format omits a key whose new value is null), so binding only
    /// present keys would leave it at its stale, still-tombstoned value
    /// forever — invisible to `rows`/`row`/`liveRow` (`WHERE deleted_at IS
    /// NULL`) even after `markDeleted`'s earlier tombstone should have been
    /// cleared. The five taxonomy tables have no `is_deleted` at all, so for
    /// them an un-forced `deleted_at` would make a restore unrecoverable,
    /// not just inconsistent.
    ///
    /// `is_deleted` (`content.markdown` only) is *not* simply force-bound to
    /// `excluded.is_deleted` the way `deleted_at` is, because that reopens a
    /// narrower version of the same inconsistency the wrong way: a payload
    /// that supplies `deleted_at` (a genuine tombstone) but omits
    /// `is_deleted` — exactly what `deletedAtColumnIsNormalisedOnIngest`
    /// already sends, and what any payload builder emitting only the
    /// columns common to the whole markdown family would produce — would
    /// let `excluded.is_deleted` fall back to the column's own `DEFAULT 0`,
    /// setting `is_deleted = 0` while `deleted_at` stays non-null: the two
    /// flags disagree, `document(id:)` (gates on `is_deleted` alone) shows a
    /// server-deleted document as live, and `liveRow` (gates on
    /// `deleted_at`) still hides it. So when `data` supplies `is_deleted`
    /// explicitly, it wins verbatim (`excluded.is_deleted`); when it does
    /// not, `is_deleted` is *derived* from whichever `deleted_at` this same
    /// statement is about to write, not defaulted independently of it.
    ///
    /// `excluded.<column>` resolves correctly even when `data` never
    /// supplies a column and it is absent from this `INSERT`'s own column
    /// list: SQLite fills the `excluded` pseudo-row with the value the
    /// statement *would* have inserted for every table column, including
    /// one it defaults — `NULL` for `deleted_at` (no `DEFAULT`, nullable) —
    /// so `deleted_at` needs nothing added to `bound`/`arguments`; only
    /// `assignments` changes. That materialisation only feeds `excluded.*`,
    /// though, and `excluded.*` only feeds the `ON CONFLICT` branch — a row
    /// that does not exist yet takes the plain `INSERT` branch instead,
    /// where an omitted column gets its column `DEFAULT`, full stop. So
    /// deriving `is_deleted` from `excluded.deleted_at` (an earlier version
    /// of this method did exactly that) is correct on an update but silently
    /// wrong on a first insert: `is_deleted` sits outside `bound`, the
    /// `INSERT` never mentions it, `ON CONFLICT` never fires, and it lands at
    /// its `DEFAULT 0` regardless of what `deleted_at` just got written —
    /// exactly the shape `deletedAtColumnIsNormalisedOnIngest` sends for a
    /// document that has never been pulled before. `is_deleted` must
    /// therefore be computed in Swift and placed in `bound`/`arguments` like
    /// any other column, so the same value lands on both the `INSERT` and
    /// (via `excluded.is_deleted`) the `ON CONFLICT UPDATE` branch.
    public func upsert(
        resource: String, id: String, syncVersion: Int,
        data: [String: JSONValue], isFullRow: Bool, in conn: Database
    ) throws {
        let present = Set(columns(for: resource).filter { data[$0] != nil })
        var bound = columns(for: resource).filter {
            data[$0] != nil || Self.requiredWithNoDefault.contains($0)
        }
        var assignmentColumns = present
        if isFullRow {
            assignmentColumns.insert("deleted_at")
            if resource == "content.markdown" { assignmentColumns.insert("is_deleted") }
        }
        // Only markdown carries `is_deleted`, and only when the payload
        // itself didn't supply it — a payload that did already has it in
        // `bound`/`present` via the ordinary path above.
        let derivesIsDeleted = isFullRow && resource == "content.markdown" && !present.contains("is_deleted")
        if derivesIsDeleted {
            bound.append("is_deleted")
        }
        // The mirror image of `derivesIsDeleted`: a full-row pull that supplies
        // `is_deleted` truthy but no non-null `deleted_at` must not let
        // `deleted_at` fall back to NULL (its column default) — that would leave
        // `document(id:)`/`documentExists` (gate on `is_deleted`) hiding the row
        // while `liveRow`/`rows` (gate on `deleted_at`) still show it as live, the
        // same two-flags-disagree corruption the other way round. Computed here
        // in Swift and placed in `bound`/`arguments` for the same reason
        // `is_deleted` is above: `ON CONFLICT ... SET` fires only on the UPDATE
        // branch, so a value derived there alone would be wrong on a first insert.
        let isDeletedTruthy = present.contains("is_deleted")
            && Self.isTruthy(Self.value(data["is_deleted"], column: "is_deleted"))
        let deletedAtSuppliedNonNull = Self.value(data["deleted_at"], column: "deleted_at") != nil
        let derivesDeletedAt = isFullRow && resource == "content.markdown"
            && isDeletedTruthy && !deletedAtSuppliedNonNull
        if derivesDeletedAt, !present.contains("deleted_at") {
            bound.append("deleted_at")
        }
        let names = ["id", "sync_version"] + bound
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let assignments = (["sync_version"] + assignmentColumns.sorted())
            .map { "\($0) = excluded.\($0)" }
            .joined(separator: ", ")
        var arguments: [(any DatabaseValueConvertible)?] = [id, syncVersion]
        arguments += bound.map { column -> (any DatabaseValueConvertible)? in
            if column == "is_deleted", derivesIsDeleted {
                // Whatever this same statement is about to write to
                // `deleted_at` — present in `data` (including an explicit
                // `.null` restore) or, absent, the `NULL` `deleted_at`
                // itself falls back to.
                return Self.value(data["deleted_at"], column: "deleted_at") == nil ? 0 : 1
            }
            if column == "deleted_at", derivesDeletedAt {
                // `is_deleted` came in truthy with no non-null `deleted_at` to
                // match it — stamp one now rather than let it fall back to NULL
                // (or clobber an explicit `.null` restore attempt that contradicts
                // the very `is_deleted: true` in the same payload).
                return MarkdownTimestamp.string(Date())
            }
            return data[column] != nil ? Self.value(data[column], column: column) : MarkdownTimestamp.string(Date())
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
        // `Int(number)` traps on a non-finite value (`number == number.rounded()`
        // is true for both `+infinity` and `-infinity`), so `isFinite` must be
        // checked first. Unreachable from `JSONDecoder` today — JSON has no
        // literal for infinity or NaN — but this guard is one comparison and
        // removes the trap as a live possibility for any future `JSONValue`
        // producer.
        case .number(let number): return number.isFinite && number == number.rounded() ? Int(number) : number
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

    /// Whether a value already bound through `value(_:column:)` reads as
    /// truthy — the two shapes `is_deleted` can take once decoded: a
    /// non-zero `Int` (`value(_:column:)` maps both a JSON number and a JSON
    /// bool to one) or a non-zero `Double`. Anything else, `nil` included,
    /// is not truthy.
    private static func isTruthy(_ boundValue: (any DatabaseValueConvertible)?) -> Bool {
        switch boundValue {
        case let intValue as Int: return intValue != 0
        case let doubleValue as Double: return doubleValue != 0
        default: return false
        }
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
