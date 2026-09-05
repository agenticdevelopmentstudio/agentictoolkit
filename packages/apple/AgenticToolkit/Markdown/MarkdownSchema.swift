import Foundation
import GRDB
import AgenticToolkitDatabase

/// The local half of adh's `content.markdown` family, transcribed from adh's
/// `schema.snapshot.sql`.
///
/// Every table carries adh's column names verbatim, including the two the
/// client never reads (`sync_stamped_at`, `sync_txid`): a pulled row carries
/// them, and a mirror that drops a column is a mirror that cannot round-trip.
/// Divergences from adh are marked `// LOCAL:` at the line that makes them.
public enum MarkdownSchema {

    /// Every table this schema creates, in dependency order. The test suite
    /// walks this list, so a table added to the DDL without being added here
    /// is a table nothing checks.
    public static let tables = [
        "markdown", "notes", "docs", "papers",
        "categories", "category_edges", "category_items",
        "keywords", "keyword_items"
    ]

    /// The tail every mirrored table carries. Written once rather than nine
    /// times — `dry`, and a transcription error here fails every table's
    /// column assertion at once instead of hiding in one of nine copies.
    private static let commonTail = """
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            sync_stamped_at TEXT,
            sync_txid INTEGER NOT NULL DEFAULT 0
        """

    /// The head every mirrored table carries.
    private static let commonHead = """
            id TEXT PRIMARY KEY NOT NULL,
            customer_id TEXT NOT NULL DEFAULT '',
            ecosystem_id TEXT NOT NULL DEFAULT ''
        """

    /// One marker table. `notes`, `docs` and `papers` are byte-identical
    /// upstream apart from the name, so they are generated rather than
    /// transcribed three times.
    ///
    /// adh has an `inherit_customer` trigger on `papers` alone. It is not
    /// ported: `MarkdownStore` sets `customer_id` explicitly on all three,
    /// which is what the trigger exists to guarantee.
    private static func markerTable(_ name: String) -> String {
        """
        CREATE TABLE IF NOT EXISTS \(name) (
        \(commonHead),
            markdown_id TEXT NOT NULL
                REFERENCES markdown(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
        \(commonTail),
            UNIQUE (ecosystem_id, id)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_\(name)_markdown
            ON \(name)(markdown_id) WHERE deleted_at IS NULL;
        CREATE INDEX IF NOT EXISTS ix_\(name)_tenant_user
            ON \(name)(ecosystem_id, customer_id);
        """
    }

    /// Creates the nine mirrored tables directly against a connection —
    /// every statement is `CREATE TABLE/INDEX IF NOT EXISTS`, so this has no
    /// `DatabaseMigrator` bookkeeping to conflict with `migrate(_:)`, which
    /// runs the same DDL (plus the local-only outbox table) through the
    /// migrator on every path that goes through `MarkdownStore.init`.
    ///
    /// This exists for `MarkdownProjection.createTables(in:)`, called from
    /// `GRDBSyncStore.prepare(resources:in:)` — a host that builds a bare
    /// `GRDBSyncStore` directly on `MarkdownProjection`, bypassing
    /// `MarkdownStore` entirely, needs `prepare` alone to leave it with a
    /// working schema rather than "no such table: markdown" on its first
    /// pulled change. It does not turn `PRAGMA foreign_keys` on — that
    /// pragma is a no-op inside a transaction (see `migrate(_:)`'s doc
    /// comment), and `prepare` always runs inside one — so a caller on that
    /// bypass path must still do that itself, the way `migrate(_:)` does via
    /// `writeWithoutTransaction`.
    public static func createTables(in conn: Database) throws {
        try conn.execute(sql: documentDDL)
        for name in ["notes", "docs", "papers"] {
            try conn.execute(sql: markerTable(name))
        }
        try conn.execute(sql: taxonomyDDL)
    }

    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("markdown-v1") { conn in
            try conn.execute(sql: documentDDL)
            for name in ["notes", "docs", "papers"] {
                try conn.execute(sql: markerTable(name))
            }
            try conn.execute(sql: taxonomyDDL)
            try conn.execute(sql: outboxDDL)
        }
        migrator.registerMigration("markdown-v2-outbox-order") { conn in
            try conn.execute(sql: outboxOrderDDL)
        }
        // `markdown-v3-frontmatter-owner`: records which frontmatter keys *this
        // client* wrote into a document.
        //
        // Local-only, like the outbox and `_markdown_remote_id`, and for the
        // same reason: it is a fact about who authored a line, and adh has no
        // column for it. It exists because a frontmatter key is only ever bytes
        // — nothing in `title: Groceries` says whether the app derived it from
        // a rename or the user typed it — and every rule that matters turns on
        // the difference. A key the app owns is the app's to rewrite, to clear,
        // and to hide from the editor; a key the user typed is theirs, and is
        // never touched. Guessing from the value instead is what let a save
        // overwrite a hand-typed `title:` and an unpin fail to persist.
        //
        // A row per `(document, key)` rather than a list column, so a key can
        // be claimed and released on its own — which is what lets a pull
        // release only the claims its content actually invalidated
        // (`MarkdownProjection.releaseFrontmatterClaimsInvalidated(by:...)`).
        // Rows are deleted with their document; an orphan would be harmless
        // anyway, since ids are UUIDs and are never reused.
        migrator.registerMigration("markdown-v3-frontmatter-owner") { conn in
            try conn.execute(sql: frontmatterOwnerDDL)
            try backfillFrontmatterOwners(in: conn)
        }
        return migrator
    }

    /// Runs the migration against a `BoundedDatabase`, turning foreign keys on
    /// first. SQLite itself defaults `foreign_keys` to *off*, but GRDB does not
    /// leave it there: `Configuration.foreignKeysEnabled` defaults to `true`
    /// and GRDB issues the pragma on every connection it opens, so this
    /// statement is confirming the state rather than establishing it. It stays
    /// because it is cheap, because it is the only line in this file that says
    /// out loud that the `REFERENCES` clauses below are enforced, and because a
    /// host that ever hands `BoundedDatabase` a configuration with
    /// `foreignKeysEnabled = false` would otherwise get a schema full of
    /// constraints that quietly enforce nothing (`explicit-over-implicit`).
    ///
    /// `PRAGMA foreign_keys` is a no-op inside a transaction, so it runs via
    /// `writeWithoutTransaction`, not `write`. `DatabaseMigrator` has no
    /// overload taking a `Database` in this GRDB version — only
    /// `migrate(_ writer: any DatabaseWriter)` — so the migration itself runs
    /// against `BoundedDatabase`'s underlying writer directly, outside the
    /// bounded `read`/`write` chokepoint.
    public static func migrate(_ database: BoundedDatabase) throws {
        try database.writeWithoutTransaction { conn in
            try conn.execute(sql: "PRAGMA foreign_keys = ON")
        }
        try migrator().migrate(database.writer)
    }

    // MARK: - content.markdown

    private static let documentDDL = """
        CREATE TABLE IF NOT EXISTS markdown (
        \(commonHead),
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            frontmatter TEXT,
            content_hash TEXT NOT NULL DEFAULT '',
            size_bytes INTEGER NOT NULL DEFAULT 0,
            current_version INTEGER NOT NULL DEFAULT 1,
            latest_version_id TEXT,
            is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
            public_route TEXT,
            -- LOCAL: adh constrains only owner_kind. A visibility or stage the
            -- client cannot render should fail on arrival, naming its column,
            -- rather than be stored as a state no local code handles.
            visibility TEXT NOT NULL DEFAULT 'private'
                CHECK (visibility IN ('private', 'public')),
            stage TEXT NOT NULL DEFAULT 'draft'
                CHECK (stage IN ('draft', 'final')),
            owner_kind TEXT NOT NULL DEFAULT 'customer'
                CHECK (owner_kind IN ('customer', 'organization')),   -- markdown_owner_kind_chk
            owner_id TEXT NOT NULL DEFAULT '',
        \(commonTail),
            UNIQUE (ecosystem_id, id)
        );
        CREATE INDEX IF NOT EXISTS idx_markdown_content_hash ON markdown(content_hash);
        CREATE INDEX IF NOT EXISTS idx_markdown_owner ON markdown(owner_kind, owner_id);
        CREATE INDEX IF NOT EXISTS idx_markdown_updated
            ON markdown(ecosystem_id, customer_id, updated_at) WHERE is_deleted = 0;
        CREATE INDEX IF NOT EXISTS idx_markdown_public_updated
            ON markdown(updated_at) WHERE visibility = 'public' AND is_deleted = 0;
        CREATE UNIQUE INDEX IF NOT EXISTS uq_markdown_author_route
            ON markdown(customer_id, public_route)
            WHERE public_route IS NOT NULL AND is_deleted = 0;
        -- The index that makes a document's *kind* real without a kind column.
        -- SQLite's json_extract over a partial expression index is the direct
        -- analogue of PG's `frontmatter ->> 'adh_source'`.
        CREATE UNIQUE INDEX IF NOT EXISTS uq_markdown_adh_source
            ON markdown(customer_id, json_extract(frontmatter, '$.adh_source'))
            WHERE json_extract(frontmatter, '$.adh_source') IS NOT NULL AND is_deleted = 0;
        """

    // MARK: - content.categories, category_edges, category_items, keywords, keyword_items

    private static let taxonomyDDL = """
        CREATE TABLE IF NOT EXISTS categories (
        \(commonHead),
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            color TEXT NOT NULL DEFAULT '',
            icon TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
        \(commonTail),
            UNIQUE (ecosystem_id, id)
        );
        CREATE INDEX IF NOT EXISTS ix_categories_tenant_user
            ON categories(ecosystem_id, customer_id);

        CREATE TABLE IF NOT EXISTS category_edges (
        \(commonHead),
            parent_id TEXT NOT NULL
                REFERENCES categories(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
            child_id TEXT NOT NULL
                REFERENCES categories(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
            sort_order INTEGER NOT NULL DEFAULT 0,
        \(commonTail),
            UNIQUE (ecosystem_id, id),
            UNIQUE (ecosystem_id, parent_id, child_id),
            -- LOCAL: adh rejects a self-edge in a trigger; SQLite states it as
            -- a CHECK, which is cheaper and cannot be forgotten by a writer.
            -- Longer cycles are not expressible here — MarkdownStore walks for
            -- those (Task 11).
            CHECK (parent_id <> child_id)
        );
        CREATE INDEX IF NOT EXISTS ix_category_edges_parent
            ON category_edges(ecosystem_id, parent_id);
        -- The child index is what makes the recursive descendant walk cheap.
        CREATE INDEX IF NOT EXISTS ix_category_edges_child
            ON category_edges(ecosystem_id, child_id);

        CREATE TABLE IF NOT EXISTS category_items (
        \(commonHead),
            category_id TEXT NOT NULL
                REFERENCES categories(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
            target_kind TEXT NOT NULL,
            target_id TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
        \(commonTail),
            UNIQUE (ecosystem_id, id),
            UNIQUE (ecosystem_id, category_id, target_kind, target_id)
        );
        CREATE INDEX IF NOT EXISTS ix_category_items_target
            ON category_items(target_kind, target_id);
        CREATE INDEX IF NOT EXISTS ix_category_items_tenant_user
            ON category_items(ecosystem_id, customer_id);

        CREATE TABLE IF NOT EXISTS keywords (
        \(commonHead),
            label TEXT NOT NULL,
            color TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
        \(commonTail),
            UNIQUE (ecosystem_id, id),
            UNIQUE (customer_id, ecosystem_id, label)
        );

        CREATE TABLE IF NOT EXISTS keyword_items (
        \(commonHead),
            keyword_id TEXT NOT NULL
                REFERENCES keywords(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
            target_kind TEXT NOT NULL,
            target_id TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
        \(commonTail),
            UNIQUE (ecosystem_id, id),
            UNIQUE (ecosystem_id, keyword_id, target_kind, target_id)
        );
        CREATE INDEX IF NOT EXISTS ix_keyword_items_target
            ON keyword_items(target_kind, target_id);
        CREATE INDEX IF NOT EXISTS ix_keyword_items_tenant_user
            ON keyword_items(ecosystem_id, customer_id);
        """

    // MARK: - The local REST queue

    /// Local-only, and deliberately not one of `tables`: nothing syncs it, and
    /// it has no adh counterpart. `content.markdown` is pull-only in
    /// `ADHSyncCatalog`, so a local edit cannot ride the sync outbox; it queues
    /// here instead and drains over REST once a writer exists (Task 10).
    /// Frozen at its `markdown-v1` shape on purpose. `DatabaseMigrator` replays
    /// v1 verbatim on a brand-new database before it runs v2, so editing this
    /// string to include v2's columns would make v2's `ALTER TABLE` fail with
    /// "duplicate column name" on exactly the fresh installs it is meant to
    /// leave alone. Later shape changes go in a new migration, not here.
    private static let outboxDDL = """
        CREATE TABLE IF NOT EXISTS _markdown_outbox (
            op_id TEXT PRIMARY KEY NOT NULL,
            document_id TEXT NOT NULL,
            intent TEXT NOT NULL,
            payload TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS ix_markdown_outbox_document
            ON _markdown_outbox(document_id, intent);
        """

    /// Claims every `title`/`pinned` already on disk for the app.
    ///
    /// Before this table existed the app was the only *intentional* writer of
    /// those two keys and read every one of them as its own — a `pinned: true`
    /// pinned the note whoever typed it. Backfilling therefore reproduces
    /// exactly what the user sees today; leaving the table empty instead would
    /// unpin every pinned note and un-rename every renamed one on first launch
    /// after the upgrade, which is data loss dressed up as a stricter rule. The
    /// new rule applies to everything written from here on, where the answer is
    /// known rather than assumed.
    private static func backfillFrontmatterOwners(in conn: Database) throws {
        for row in try Row.fetchAll(conn, sql: "SELECT id, content FROM markdown") {
            let content: String = row["content"]
            let id: String = row["id"]
            for key in ["title", "pinned"] where Frontmatter.value(key, in: content) != nil {
                try conn.execute(
                    sql: """
                        INSERT OR IGNORE INTO _markdown_frontmatter_owner (document_id, key)
                        VALUES (?, ?)
                        """,
                    arguments: [id, key])
            }
        }
    }

    private static let frontmatterOwnerDDL = """
        CREATE TABLE IF NOT EXISTS _markdown_frontmatter_owner (
            document_id TEXT NOT NULL,
            key TEXT NOT NULL,
            PRIMARY KEY (document_id, key)
        );
        """

    /// A strict send order for the queue, and a place to record the id adh
    /// minted for a locally-created document. Run by `markdown-v2-outbox-order`.
    ///
    /// `seq` exists because `ORDER BY created_at, op_id` is not an order at
    /// all when two ops share a millisecond — `created_at` is truncated to
    /// milliseconds and `op_id` is a UUIDv7 whose tie-break is its own random
    /// tail — so a `create` and the `update` that followed it could come back
    /// in either order, and sending the update first pushes a write for a
    /// document adh has never seen. `MarkdownStore` assigns `MAX(seq) + 1`
    /// rather than using `AUTOINCREMENT`, which SQLite allows only on an
    /// `INTEGER PRIMARY KEY` and therefore cannot be added by `ALTER TABLE`;
    /// reuse after a drain is harmless because every row that could have held
    /// a reused value is gone by then.
    ///
    /// `_markdown_remote_id` is local-only for the same reason the outbox is:
    /// it records that *this* client once created *that* document upstream, a
    /// fact no other client needs and adh has no column for. Backfilling
    /// existing rows from `rowid` keeps the ops already queued on a
    /// pre-migration install in the order they were enqueued.
    private static let outboxOrderDDL = """
        ALTER TABLE _markdown_outbox ADD COLUMN seq INTEGER NOT NULL DEFAULT 0;
        UPDATE _markdown_outbox SET seq = rowid;
        CREATE INDEX IF NOT EXISTS ix_markdown_outbox_seq ON _markdown_outbox(seq);

        CREATE TABLE IF NOT EXISTS _markdown_remote_id (
            local_id TEXT PRIMARY KEY NOT NULL,
            remote_id TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """
}
