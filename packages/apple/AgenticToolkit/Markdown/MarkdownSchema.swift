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
        return migrator
    }

    /// Runs the migration against a `BoundedDatabase`, turning foreign keys on
    /// first. SQLite defaults `foreign_keys` to *off* — a schema full of
    /// `REFERENCES` clauses that enforce nothing is worse than no clauses at
    /// all, because it reads as if it were safe (`explicit-over-implicit`).
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
}
