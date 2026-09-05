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
public enum MarkdownProjectionError: Error, Equatable {
    /// A purge named a resource whose mirror table is a foreign-key parent of
    /// another resource's, and left that other resource out. Emptying the
    /// parent alone would leave `rows` rows in `referencedBy` pointing at
    /// nothing — which SQLite would catch, but only at `COMMIT`, naming
    /// neither table.
    case purgeWouldOrphanRows(resource: String, referencedBy: String, rows: Int)

    /// A staged local mutation (`isFullRow: false`) named both `deleted_at`
    /// and `is_deleted` and gave them opposite senses. `upsert` normalises the
    /// pair only on a full-row pull, where the whole row is present to
    /// normalise; a partial patch that contradicts itself has no half to
    /// prefer, so it is refused rather than half-written.
    case partialPatchDeleteStateDisagrees(resource: String, id: String)
}

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
    /// `deleted_at` and `is_deleted` (the latter on `content.markdown` alone)
    /// are two records of one fact, and neither is passed through from `data`
    /// on a full-row markdown pull. Both are *derived together* in Swift from
    /// a single decision — see the block comment inside the method — and both
    /// are appended to `bound` so the same pair of values lands on the
    /// `INSERT` and, via `excluded.*`, on the `ON CONFLICT UPDATE`.
    ///
    /// Deriving them separately is what let them disagree, and passing either
    /// one through verbatim is a form of deriving them separately: a payload
    /// supplying `deleted_at` but omitting `is_deleted` — exactly what
    /// `deletedAtColumnIsNormalisedOnIngest` sends, and what any payload
    /// builder emitting only the columns common to the whole markdown family
    /// would produce — would leave `is_deleted` at its `DEFAULT 0` while
    /// `deleted_at` stayed non-null, so `document(id:)` (gates on
    /// `is_deleted`) would show a server-deleted document as live while
    /// `liveRow` (gates on `deleted_at`) still hid it. Symmetrically, a
    /// payload supplying `is_deleted: 0` alongside a genuine `deleted_at`
    /// must not be taken at its word. Non-null `deleted_at` therefore wins
    /// over a falsy `is_deleted`, and a truthy `is_deleted` with no stamp of
    /// its own is stamped now rather than left NULL.
    ///
    /// Neither column can be left to `excluded.*` alone. `excluded.<column>`
    /// does resolve even for a column `data` never supplies and this
    /// `INSERT`'s column list never mentions — SQLite materialises the whole
    /// row the statement *would* have inserted, defaults included — but that
    /// materialisation only feeds `excluded.*`, and `excluded.*` only feeds
    /// the `ON CONFLICT` branch. A row that does not exist yet takes the
    /// plain `INSERT` branch, where an omitted column gets its column
    /// `DEFAULT`, full stop. An earlier version derived `is_deleted` from
    /// `excluded.deleted_at` and was correct on an update and silently wrong
    /// on a first insert — `is_deleted` sat outside `bound`, `ON CONFLICT`
    /// never fired, and it landed at `DEFAULT 0` regardless of the
    /// `deleted_at` just written, which is exactly the shape
    /// `deletedAtColumnIsNormalisedOnIngest` sends for a document that has
    /// never been pulled before. Hence: computed in Swift, bound like any
    /// other column.
    ///
    /// A full-row `content.markdown` pull also releases the local frontmatter
    /// claims the incoming content invalidates, before it overwrites
    /// `content` — see `releaseFrontmatterClaimsInvalidated(by:)`.
    public func upsert(
        resource: String, id: String, syncVersion: Int,
        data: [String: JSONValue], isFullRow: Bool, in conn: Database
    ) throws {
        let present = Set(columns(for: resource).filter { data[$0] != nil })
        try Self.rejectPartialDeleteStateDisagreement(
            resource: resource, id: id, data: data, present: present, isFullRow: isFullRow)
        // A pull replaces `content` wholesale, and `_markdown_frontmatter_owner`
        // is a claim *about those bytes*. Released here, at the write, rather
        // than second-guessed later at the read.
        if isFullRow, resource == "content.markdown", case .string(let incoming) = data["content"] {
            try Self.releaseFrontmatterClaimsInvalidated(by: incoming, documentID: id, in: conn)
        }
        var bound = columns(for: resource).filter {
            data[$0] != nil || Self.requiredWithNoDefault.contains($0)
        }
        var assignmentColumns = present
        if isFullRow {
            assignmentColumns.insert("deleted_at")
            if resource == "content.markdown" { assignmentColumns.insert("is_deleted") }
        }
        // `deleted_at` and `is_deleted` are one fact — "has this document been
        // deleted?" — recorded in two columns because adh records it in two,
        // and the corruption this closes is the two of them disagreeing.
        //
        // Deriving them separately, each under its own condition, is what let
        // them disagree: a pull supplying `deleted_at` non-null *and*
        // `is_deleted` explicitly falsy satisfied neither condition and wrote
        // both values through untouched. So on a full-row markdown pull the
        // fact is decided once, here, and *both* columns are then bound from
        // it — there is no path through this method that writes one without
        // the other. `document(id:)` gates on `is_deleted` and `liveRow` gates
        // on `deleted_at`; a row they disagree about is a note the user can
        // open and edit after the server deleted it.
        //
        // Non-null `deleted_at` wins over a falsy `is_deleted` because it is
        // the stronger claim: it carries *when*, which a bare flag cannot, and
        // adh only ever stamps it on a real delete. Both are bound in Swift
        // rather than left to `excluded.*` because `ON CONFLICT ... SET` fires
        // only on the UPDATE branch — a value derived there alone is right on
        // an update and silently wrong on a first insert, where an unmentioned
        // column takes its column `DEFAULT` instead.
        //
        // A partial patch (`isFullRow: false`) is deliberately *not* normalised
        // here, and this is the seam where that limit lives. A patch that names
        // only one of the two columns cannot have the other derived from it:
        // deriving `is_deleted` from a `deleted_at` the patch did name would
        // write a column the caller never mentioned, which is the force-bind
        // that used to resurrect a tombstoned row through `stage(_:)`; and
        // deriving `deleted_at` from a bare `is_deleted: 1` would have to
        // invent a *when* that nothing in the patch supplies. Reading the
        // stored row for the missing half does not rescue it either — the
        // stored half is precisely what the patch is silent about, so
        // "agreeing" with it is a guess dressed as a lookup.
        //
        // The one case that is not unknown is closed instead of tolerated: a
        // patch that names *both* columns and contradicts itself is rejected
        // above by `rejectPartialDeleteStateDisagreement`, because there is
        // nothing to infer there — the caller stated two facts that cannot
        // both be true, and writing either of them would be picking a winner
        // on the caller's behalf.
        let normalisesDeleteState = isFullRow && resource == "content.markdown"
        let suppliedDeletedAt = Self.value(data["deleted_at"], column: "deleted_at")
        let isDeleted = suppliedDeletedAt != nil
            || (present.contains("is_deleted")
                && Self.isTruthy(Self.value(data["is_deleted"], column: "is_deleted")))
        if normalisesDeleteState {
            if !bound.contains("is_deleted") { bound.append("is_deleted") }
            if !bound.contains("deleted_at") { bound.append("deleted_at") }
        }
        let names = ["id", "sync_version"] + bound
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let assignments = (["sync_version"] + assignmentColumns.sorted())
            .map { "\($0) = excluded.\($0)" }
            .joined(separator: ", ")
        var arguments: [(any DatabaseValueConvertible)?] = [id, syncVersion]
        arguments += bound.map { column -> (any DatabaseValueConvertible)? in
            // The two halves of the one delete fact, written together. A
            // deleted row with no stamp of its own is stamped now rather than
            // left NULL; a live row clears both, which is what a pulled
            // restore looks like (adh omits a key whose new value is null).
            if normalisesDeleteState, column == "is_deleted" { return isDeleted ? 1 : 0 }
            if normalisesDeleteState, column == "deleted_at" {
                guard isDeleted else { return nil }
                return suppliedDeletedAt ?? MarkdownTimestamp.string(Date())
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

    /// Refuses a partial patch whose two delete columns contradict each other.
    ///
    /// Only `content.markdown` has both columns, and only a partial patch
    /// reaches this — a full-row pull decides the pair itself in `upsert` and
    /// never asks. See the block comment at `normalisesDeleteState` for why
    /// this is a rejection rather than a normalisation.
    ///
    /// Nothing can reach it *today*: `content.markdown` is in
    /// `pullOnlyResources`, so `GRDBSyncStore.stage(_:in:)` refuses it before
    /// the projection is consulted, and the taxonomy resources that do stage
    /// have no `is_deleted` column at all. This is a backstop against the
    /// combination becoming reachable, which is why it is a guard here rather
    /// than a note in the doc comment above.
    private static func rejectPartialDeleteStateDisagreement(
        resource: String, id: String, data: [String: JSONValue],
        present: Set<String>, isFullRow: Bool
    ) throws {
        guard !isFullRow, resource == "content.markdown",
              present.contains("deleted_at"), present.contains("is_deleted") else { return }
        // A key present as JSON `null` is a deliberate clear, not an omission —
        // that is why `present` is membership rather than non-nullness.
        let tombstoned = Self.value(data["deleted_at"], column: "deleted_at") != nil
        let flagged = Self.isTruthy(Self.value(data["is_deleted"], column: "is_deleted"))
        guard tombstoned != flagged else { return }
        throw MarkdownProjectionError.partialPatchDeleteStateDisagrees(resource: resource, id: id)
    }

    /// Drops this client's ownership of any frontmatter key whose value the
    /// incoming content changes.
    ///
    /// `_markdown_frontmatter_owner` records that *this app* wrote a given
    /// frontmatter key into a given document — the fact `MarkdownNoteStorage`
    /// stopped guessing from the value. A pull replaces `content` outright, so
    /// a claim about the bytes that were there is a claim about bytes that no
    /// longer exist; leaving it standing lets `strippedContent` hide a
    /// `title:` a human typed on the web and lets the next save rewrite it.
    ///
    /// **Only the claims whose key changed value are released, not all of
    /// them.** `content.markdown` is pull-only in `ADHSyncCatalog`: every local
    /// edit leaves through the REST outbox and comes *back* down this same
    /// path, so the overwhelmingly common pull is an echo of the app's own
    /// push. Releasing every claim on any pull would therefore disown the
    /// app's own `title:`/`pinned:` at the first round trip, after which
    /// `mayWrite` — which refuses to touch an unowned key whose value differs
    /// — would make the next rename or unpin a silent no-op. That is the wave
    /// 4 defect reintroduced by a blunter rule.
    ///
    /// Comparing the two contents is not the value-guessing the ownership
    /// table replaced. The guess was *authorship* — inferring from
    /// `title: Groceries` whether the app or a human typed it. This asks a
    /// question with an actual answer: are the bytes this claim was made about
    /// still there? If they are, the claim is still true and nothing about who
    /// wrote them has been inferred; if they are not, the claim is false
    /// whoever wrote the replacement.
    private static func releaseFrontmatterClaimsInvalidated(
        by incoming: String, documentID: String, in conn: Database
    ) throws {
        // Local-only and created by migration `markdown-v3-frontmatter-owner`,
        // not by `MarkdownSchema.createTables(in:)` — a host that builds a bare
        // `GRDBSyncStore` on this projection has the mirror tables and no
        // ownership table at all, and a pull must not fail for it.
        guard try conn.tableExists("_markdown_frontmatter_owner") else { return }
        let claimed = try String.fetchAll(
            conn,
            sql: "SELECT key FROM _markdown_frontmatter_owner WHERE document_id = ?",
            arguments: [documentID])
        guard !claimed.isEmpty else { return }
        // No stored row yet means no bytes this claim could have been about;
        // the rows are keyed by document id, so another document's claims are
        // untouched either way.
        guard let stored = try String.fetchOne(
            conn, sql: "SELECT content FROM markdown WHERE id = ?", arguments: [documentID])
        else { return }
        for key in claimed
        where Frontmatter.value(key, in: stored) != Frontmatter.value(key, in: incoming) {
            try conn.execute(
                sql: "DELETE FROM _markdown_frontmatter_owner WHERE document_id = ? AND key = ?",
                arguments: [documentID, key])
        }
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

    /// `GRDBSyncStore.deleteMirrorRows(for:in:)` hands this every one of the
    /// projection's resources in a purge in a single call, so `resources` is
    /// the whole batch and this method can reason about it as a set. Within
    /// that batch the deletes still run in arbitrary order, which
    /// `PRAGMA defer_foreign_keys` makes safe: enforcement moves to the end of
    /// the enclosing transaction, so `DELETE FROM markdown` may precede the
    /// deletion of its `notes`/`docs`/`papers` children as long as every
    /// referencing row is gone by commit. That pragma is connection-scoped and
    /// resets itself to `OFF` when the transaction ends, so setting it on
    /// every call is idempotent and never leaks past this write.
    ///
    /// A purge that is *missing* a family member is a different matter, and it
    /// is refused up front rather than left to fail at `COMMIT`. SQLite's
    /// deferred-constraint failure names neither the resource that was purged
    /// nor the one still pointing at it, arrives from a statement the caller
    /// did not issue, and rolls back the whole transaction — so
    /// `purgeResources(["content.markdown"])` used to report an opaque
    /// `FOREIGN KEY constraint failed` for a mistake that is entirely knowable
    /// beforehand.
    public func truncate(resources: [String], in conn: Database) throws {
        try refusePartialFamilyPurge(resources, in: conn)
        try conn.execute(sql: "PRAGMA defer_foreign_keys = ON")
        for resource in resources {
            try conn.execute(sql: "DELETE FROM \(table(for: resource))")
        }
    }

    /// Which of this projection's resources hold rows referencing each
    /// foreign-key parent among them. `category_items`/`keyword_items` name
    /// their *target* polymorphically (`target_kind`, `target_id`) with no
    /// foreign key at all, so they are dependents of `content.categories` and
    /// `content.keywords` — their owner column — and not of
    /// `content.markdown`.
    private static let dependentResources: [String: [String]] = [
        "content.markdown": ["content.notes", "content.docs", "content.papers"],
        "content.categories": ["content.category_edges", "content.category_items"],
        "content.keywords": ["content.keyword_items"]
    ]

    private func refusePartialFamilyPurge(_ resources: [String], in conn: Database) throws {
        let purging = Set(resources)
        for parent in resources {
            for dependent in Self.dependentResources[parent] ?? [] where !purging.contains(dependent) {
                // Every row in a dependent table references *some* parent row,
                // and the parent table is about to be emptied — so any row at
                // all in the dependent is a row that would be orphaned.
                let orphans = try Int.fetchOne(
                    conn, sql: "SELECT COUNT(*) FROM \(table(for: dependent))") ?? 0
                guard orphans == 0 else {
                    throw MarkdownProjectionError.purgeWouldOrphanRows(
                        resource: parent, referencedBy: dependent, rows: orphans)
                }
            }
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
        // `Int(number)` traps on anything `Int` cannot hold, and there are two
        // such ranges, not one. `isFinite` covers only NaN and the infinities
        // (`number == number.rounded()` is true for both). Magnitude is the
        // other, and it is the reachable one: `JSONValue` decodes every JSON
        // number as `Double`, so a server row carrying `1e19` — finite,
        // integral, and larger than `Double(Int64.max)` — used to trap here,
        // inside `GRDBSyncStore`'s single batch transaction, leaving the cursor
        // unadvanced so the same batch re-pulled and re-crashed on every
        // launch. Out-of-range values stay `Double`: SQLite stores them as
        // REAL, which is lossy past 2^53 but is what the wire already handed us.
        //
        // `-Double(Int64.min)` is exactly 2^63 and the bound is exclusive,
        // because `Double(Int64.max)` rounds *up* to 2^63 and is not
        // representable as an `Int64`. `Double(Int64.min)` is exactly -2^63, so
        // that bound is inclusive.
        case .number(let number):
            guard number.isFinite, number == number.rounded(),
                  number >= Double(Int64.min), number < -Double(Int64.min) else { return number }
            return Int(number)
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
    /// truthy — the three shapes `is_deleted` can take once decoded: a
    /// non-zero `Int` (`value(_:column:)` maps both a JSON number and a JSON
    /// bool to one), a non-zero `Double`, or a string.
    ///
    /// The string case is not hypothetical: adh's column is a Postgres
    /// `boolean` and JSON is not the only serialiser that has ever crossed
    /// that wire — `"1"`, `"true"` and `"t"` (Postgres's own text output for
    /// `true`) all mean deleted, and reading them as falsy is the same
    /// two-flags-disagree corruption `upsert` closes, arriving from the other
    /// direction. Anything else, `nil` included, is not truthy.
    private static func isTruthy(_ boundValue: (any DatabaseValueConvertible)?) -> Bool {
        switch boundValue {
        case let intValue as Int: return intValue != 0
        case let doubleValue as Double: return doubleValue != 0
        case let text as String:
            let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
            if let number = Double(lowered) { return number != 0 }
            return ["true", "t", "yes", "y"].contains(lowered)
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
