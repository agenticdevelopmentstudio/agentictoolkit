import Foundation
import GRDB
import AgenticToolkitSync

public struct MarkdownCategory: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var description: String
    public var color: String
    public var icon: String
    public var sortOrder: Int

    public init(
        id: String, name: String, description: String = "",
        color: String = "", icon: String = "", sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
    }
}

public struct MarkdownKeyword: Identifiable, Equatable, Sendable {
    public let id: String
    public var label: String
    public var color: String
    public var description: String

    public init(id: String, label: String, color: String = "", description: String = "") {
        self.id = id
        self.label = label
        self.color = color
        self.description = description
    }
}

extension MarkdownStore {

    /// adh's polymorphic join tables address a row by `(target_kind, target_id)`,
    /// and the kind is the sync resource name — the same string `ADHSyncCatalog`
    /// uses, so a filed item survives a round-trip through the server unchanged.
    static let documentTargetKind = "content.markdown"

    // MARK: - Categories

    public func createCategory(
        name: String, description: String = "", color: String = "",
        icon: String = "", sortOrder: Int = 0, now: Date = Date()
    ) throws -> MarkdownCategory {
        let category = MarkdownCategory(
            id: UUID().uuidString.lowercased(), name: name, description: description,
            color: color, icon: icon, sortOrder: sortOrder)
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO categories
                        (id, customer_id, ecosystem_id, name, description, color, icon,
                         sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [category.id, customerID, ecosystemID, name, description,
                            color, icon, sortOrder, stamp, stamp])
            // Taxonomy is not pull-only, so it rides the generic outbox — the
            // typed row and its push op land in one transaction, which is what
            // `stage(_:in:)` exists for (Task 8).
            try syncStore.stage(LocalMutation(
                resource: "content.categories", rowId: category.id, type: .upsert,
                data: [
                    "name": .string(name), "description": .string(description),
                    "color": .string(color), "icon": .string(icon),
                    "sort_order": .number(Double(sortOrder))
                ]), in: conn)
        }
        return category
    }

    public func categories() throws -> [MarkdownCategory] {
        try database.read { conn in
            try Row.fetchAll(
                conn,
                sql: """
                    SELECT * FROM categories WHERE deleted_at IS NULL
                    ORDER BY sort_order, name
                    """
            ).map {
                MarkdownCategory(
                    id: $0["id"], name: $0["name"], description: $0["description"],
                    color: $0["color"], icon: $0["icon"], sortOrder: $0["sort_order"])
            }
        }
    }

    /// Every live `parent → child` edge, with no `ecosystem_id` predicate —
    /// matching `categories()`, whose output this must line up with. Scoping
    /// this one and not that one would silently orphan a node whose parent is
    /// filtered out of the edge list but not out of the category list.
    public func categoryEdges() throws -> [(parent: String, child: String)] {
        try database.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT parent_id, child_id FROM category_edges WHERE deleted_at IS NULL"
            ).map { (parent: $0["parent_id"], child: $0["child_id"]) }
        }
    }

    /// How many *notes* are filed directly under each category.
    ///
    /// Direct membership only — no recursive walk down to a category's
    /// children. `category_items` records a direct assignment, and nothing in
    /// the schema makes a child's items belong to its parent, so a parent's
    /// count can be smaller than the sum of its children's; that is correct,
    /// not a bug. Counting transitively would double-count a note reachable
    /// through two parents, and the graph is a DAG, so that is not a rare
    /// case. This also matches Apple Notes' own folder badges, which count a
    /// folder's own notes.
    ///
    /// A *note* is a `markdown` row with a live `notes` marker row — the same
    /// join `documents(marker: .note)` uses — so a `doc` or a `paper` filed
    /// under a category is not counted here.
    ///
    /// Also filters to rows whose id parses as a `UUID`, the same filter
    /// `noteCount(marker:)` applies for the "All Notes" total — a
    /// server-authored, non-UUID document is one `fetchAllNotes()` drops from
    /// the list, and a per-folder badge that still counted it would disagree
    /// with what that folder's list shows. Grouping moves into Swift because
    /// the filter needs each row's id, not just its category.
    public func categoryNoteCounts() throws -> [String: Int] {
        try database.read { conn in
            let rows = try Row.fetchAll(
                conn,
                sql: """
                    SELECT i.category_id AS category_id, m.id AS document_id
                    FROM category_items i
                    JOIN markdown m ON m.id = i.target_id AND m.is_deleted = 0
                    JOIN notes n ON n.markdown_id = m.id AND n.deleted_at IS NULL
                    WHERE i.target_kind = ? AND i.deleted_at IS NULL
                    """,
                arguments: [Self.documentTargetKind])
            var counts: [String: Int] = [:]
            for row in rows {
                let documentID: String = row["document_id"]
                guard UUID(uuidString: documentID) != nil else { continue }
                let categoryID: String = row["category_id"]
                counts[categoryID, default: 0] += 1
            }
            return counts
        }
    }

    /// The ids of every *note* filed directly under `categoryID` — the inverse
    /// of `categories(forDocument:)`. Same joins as `categoryNoteCounts()`, but
    /// scoped to one category rather than grouped over all of them, so a
    /// folder's row can be filtered without an N-query sweep of every note.
    public func documentIDs(forCategory categoryID: String) throws -> Set<String> {
        try database.read { conn in
            let ids = try String.fetchAll(
                conn,
                sql: """
                    SELECT i.target_id
                    FROM category_items i
                    JOIN markdown m ON m.id = i.target_id AND m.is_deleted = 0
                    JOIN notes n ON n.markdown_id = m.id AND n.deleted_at IS NULL
                    WHERE i.category_id = ? AND i.target_kind = ? AND i.deleted_at IS NULL
                    """,
                arguments: [categoryID, Self.documentTargetKind])
            return Set(ids)
        }
    }

    /// Adds `parent → child`, refusing an edge that would close a cycle.
    ///
    /// The schema's `CHECK (parent_id <> child_id)` catches the one-node case;
    /// everything longer needs the graph, so it is checked here. The walk is
    /// downward from `child`: if `parent` is already reachable from `child`,
    /// the new edge closes a loop. Scoped to `ecosystem_id`, matching every
    /// uniqueness constraint on this table (a cross-tenant loop is
    /// unreachable today — ids are UUIDs — but the walk should not rely on
    /// that). Per `EXPLAIN QUERY PLAN`, the ecosystem scoping lets the setup
    /// step seek `ix_category_edges_parent` directly on `(ecosystem_id,
    /// parent_id)`; the recursive step seeks `ix_category_edges_child` on
    /// `ecosystem_id` alone, which bounds the walk to that tenant's edges but
    /// is not a per-row indexed lookup — without the `ecosystem_id` predicate
    /// SQLite instead falls back to a full table scan for the whole walk.
    public func addCategoryEdge(
        parent: String, child: String, sortOrder: Int = 0, now: Date = Date()
    ) throws {
        try database.write { conn in
            let closesLoop = try Bool.fetchOne(
                conn,
                sql: """
                    WITH RECURSIVE descendants(id) AS (
                        SELECT child_id FROM category_edges
                            WHERE ecosystem_id = ? AND parent_id = ? AND deleted_at IS NULL
                        UNION
                        SELECT e.child_id FROM category_edges e
                            JOIN descendants d ON e.parent_id = d.id
                            WHERE e.ecosystem_id = ? AND e.deleted_at IS NULL
                    )
                    SELECT EXISTS(SELECT 1 FROM descendants WHERE id = ?)
                    """,
                arguments: [ecosystemID, child, ecosystemID, parent]) ?? false
            guard !closesLoop else {
                throw MarkdownStoreError.categoryCycle(parent: parent, child: child)
            }

            let newID = UUID().uuidString.lowercased()
            let stamp = MarkdownTimestamp.string(now)
            try conn.execute(
                sql: """
                    INSERT INTO category_edges
                        (id, customer_id, ecosystem_id, parent_id, child_id, sort_order,
                         created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(ecosystem_id, parent_id, child_id) DO UPDATE SET
                        deleted_at = NULL,
                        sort_order = excluded.sort_order,
                        updated_at = excluded.updated_at
                    WHERE category_edges.deleted_at IS NOT NULL
                    """,
                arguments: [newID, customerID, ecosystemID, parent, child, sortOrder, stamp, stamp])
            // `UNIQUE (ecosystem_id, parent_id, child_id)` is unconditional —
            // deliberately, because adh's is — so `removeCategoryEdge`'s
            // tombstone keeps occupying the key forever. A plain
            // `DO NOTHING` therefore made re-adding an edge that was once
            // removed a permanent silent no-op: nothing written, nothing
            // staged, and a *successful* return. Reviving is the same answer
            // `createKeyword` reaches for the same constraint, and for the
            // same reason — a second row for the key is a local state adh
            // would reject on push.
            //
            // The `WHERE` makes the UPDATE branch a no-op for a live row, so
            // zero changes here still means precisely "this edge already
            // exists and is live", which is the case that must not stage a
            // second mutation for a row it never inserted.
            guard conn.changesCount > 0 else { return }
            // A revive keeps the tombstone's id, so the id that survived — not
            // the one just minted — is what the staged mutation must address.
            let id = try String.fetchOne(
                conn,
                sql: """
                    SELECT id FROM category_edges
                    WHERE ecosystem_id = ? AND parent_id = ? AND child_id = ?
                    """,
                arguments: [ecosystemID, parent, child]) ?? newID
            var data: [String: JSONValue] = [
                "parent_id": .string(parent), "child_id": .string(child),
                "sort_order": .number(Double(sortOrder))
            ]
            // Only on a revive: a plain insert has no `deleted_at` to clear,
            // and naming the column anyway would push a write adh has no
            // reason to receive.
            if id != newID { data["deleted_at"] = .null }
            try syncStore.stage(LocalMutation(
                resource: "content.category_edges", rowId: id, type: .upsert,
                data: data), in: conn)
        }
    }

    public func assignCategory(
        _ categoryID: String, toDocument documentID: String, sortOrder: Int = 0, now: Date = Date()
    ) throws {
        try assignItem(
            table: "category_items", resource: "content.category_items",
            column: "category_id", ownerID: categoryID,
            documentID: documentID, sortOrder: sortOrder, now: now)
    }

    public func categories(forDocument documentID: String) throws -> [MarkdownCategory] {
        try database.read { conn in
            try Row.fetchAll(
                conn,
                sql: """
                    SELECT c.* FROM categories c
                    JOIN category_items i ON i.category_id = c.id AND i.deleted_at IS NULL
                    WHERE i.target_kind = ? AND i.target_id = ? AND c.deleted_at IS NULL
                    ORDER BY i.sort_order, c.name
                    """,
                arguments: [Self.documentTargetKind, documentID]
            ).map {
                MarkdownCategory(
                    id: $0["id"], name: $0["name"], description: $0["description"],
                    color: $0["color"], icon: $0["icon"], sortOrder: $0["sort_order"])
            }
        }
    }

    /// Renames a live category, throwing `MarkdownStoreError.notFound(id)` when
    /// no live row matches — the same typed error `assignItem` raises for a
    /// missing owner, so a caller sees one error shape for "that id is not
    /// there" everywhere in this file.
    public func renameCategory(_ id: String, to name: String, now: Date = Date()) throws {
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            try conn.execute(
                sql: """
                    UPDATE categories SET name = ?, updated_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [name, stamp, id])
            guard conn.changesCount > 0 else {
                throw MarkdownStoreError.notFound(id)
            }
            try syncStore.stage(LocalMutation(
                resource: "content.categories", rowId: id, type: .upsert,
                data: ["name": .string(name)]), in: conn)
        }
    }

    /// Tombstones a category and everything that names it — the row itself,
    /// then every `category_edges` row where it is a parent or a child, then
    /// every `category_items` row that files a document under it — each with
    /// its own staged mutation, per spec §6.1.
    ///
    /// Documents are rows in `markdown` and are never touched: this deletes
    /// the folder, not the notes inside it. A no-op edge or item tombstone
    /// (nothing left naming this category) simply stages nothing for that
    /// statement — the same "changed nothing, stage nothing" rule as every
    /// other writer here.
    ///
    /// Every staged payload here also carries the columns `categories`,
    /// `category_edges` and `category_items` declare `NOT NULL` with no
    /// `DEFAULT` (`name`; `parent_id`/`child_id`; `category_id`/
    /// `target_kind`/`target_id`). `GRDBSyncStore.stage(_:in:)` routes a
    /// known resource through `MarkdownProjection.upsert(isFullRow: false)`,
    /// which binds only the columns a payload names (plus `created_at`/
    /// `updated_at`, its one hard-coded exception) — a payload that omits a
    /// column with no schema default makes the `INSERT` half of that
    /// method's `ON CONFLICT` fail its `NOT NULL` check before the conflict
    /// ever resolves, even though the row already exists. `createKeyword`'s
    /// revive carries `label` for the identical reason.
    public func deleteCategory(_ id: String, now: Date = Date()) throws {
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            let name = try String.fetchOne(
                conn, sql: "SELECT name FROM categories WHERE id = ? AND deleted_at IS NULL",
                arguments: [id])
            guard let name else {
                throw MarkdownStoreError.notFound(id)
            }
            try conn.execute(
                sql: """
                    UPDATE categories SET deleted_at = ?, updated_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [stamp, stamp, id])
            try syncStore.stage(LocalMutation(
                resource: "content.categories", rowId: id, type: .upsert,
                data: ["name": .string(name), "deleted_at": .string(stamp)]), in: conn)

            // Every edge naming this category as parent or child. Fetched
            // before the `UPDATE` hides them, so there is something to stage
            // for — `changesCount` alone would say how many, never which.
            let edges = try Row.fetchAll(
                conn,
                sql: """
                    SELECT id, parent_id, child_id FROM category_edges
                    WHERE (parent_id = ? OR child_id = ?) AND deleted_at IS NULL
                    """,
                arguments: [id, id])
            if !edges.isEmpty {
                try conn.execute(
                    sql: """
                        UPDATE category_edges SET deleted_at = ?, updated_at = ?
                        WHERE (parent_id = ? OR child_id = ?) AND deleted_at IS NULL
                        """,
                    arguments: [stamp, stamp, id, id])
                for edge in edges {
                    try syncStore.stage(LocalMutation(
                        resource: "content.category_edges", rowId: edge["id"], type: .upsert,
                        data: [
                            "parent_id": .string(edge["parent_id"]), "child_id": .string(edge["child_id"]),
                            "deleted_at": .string(stamp)
                        ]), in: conn)
                }
            }

            // Every filing of a document under this category.
            let items = try Row.fetchAll(
                conn,
                sql: """
                    SELECT id, target_kind, target_id FROM category_items
                    WHERE category_id = ? AND deleted_at IS NULL
                    """,
                arguments: [id])
            if !items.isEmpty {
                try conn.execute(
                    sql: """
                        UPDATE category_items SET deleted_at = ?, updated_at = ?
                        WHERE category_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [stamp, stamp, id])
                for item in items {
                    try syncStore.stage(LocalMutation(
                        resource: "content.category_items", rowId: item["id"], type: .upsert,
                        data: [
                            "category_id": .string(id), "target_kind": .string(item["target_kind"]),
                            "target_id": .string(item["target_id"]), "deleted_at": .string(stamp)
                        ]), in: conn)
                }
            }
        }
    }

    /// Removes one `parent → child` edge. Idempotent: a caller cannot always
    /// know whether the edge is already gone, so "remove a link that isn't
    /// there" throws nothing and stages nothing. `parent`/`child` are already
    /// on hand, so no extra read is needed to carry them in the staged
    /// payload the way `deleteCategory` must (see its doc comment).
    public func removeCategoryEdge(parent: String, child: String, now: Date = Date()) throws {
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            let id = try String.fetchOne(
                conn,
                sql: """
                    SELECT id FROM category_edges
                    WHERE parent_id = ? AND child_id = ? AND deleted_at IS NULL
                    """,
                arguments: [parent, child])
            try conn.execute(
                sql: """
                    UPDATE category_edges SET deleted_at = ?, updated_at = ?
                    WHERE parent_id = ? AND child_id = ? AND deleted_at IS NULL
                    """,
                arguments: [stamp, stamp, parent, child])
            guard conn.changesCount > 0, let edgeID = id else { return }
            try syncStore.stage(LocalMutation(
                resource: "content.category_edges", rowId: edgeID, type: .upsert,
                data: [
                    "parent_id": .string(parent), "child_id": .string(child),
                    "deleted_at": .string(stamp)
                ]), in: conn)
        }
    }

    /// Unfiles a document from a category, leaving both the document and the
    /// category alone. Idempotent, like `removeCategoryEdge`: removing an
    /// assignment that is already gone throws nothing and stages nothing.
    /// `id`, the target kind and `documentID` are already on hand for the
    /// same reason `removeCategoryEdge` needs no extra read.
    public func unassignCategory(_ id: String, fromDocument documentID: String, now: Date = Date()) throws {
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            let itemID = try String.fetchOne(
                conn,
                sql: """
                    SELECT id FROM category_items
                    WHERE category_id = ? AND target_kind = ? AND target_id = ? AND deleted_at IS NULL
                    """,
                arguments: [id, Self.documentTargetKind, documentID])
            try conn.execute(
                sql: """
                    UPDATE category_items SET deleted_at = ?, updated_at = ?
                    WHERE category_id = ? AND target_kind = ? AND target_id = ? AND deleted_at IS NULL
                    """,
                arguments: [stamp, stamp, id, Self.documentTargetKind, documentID])
            guard conn.changesCount > 0, let rowID = itemID else { return }
            try syncStore.stage(LocalMutation(
                resource: "content.category_items", rowId: rowID, type: .upsert,
                data: [
                    "category_id": .string(id), "target_kind": .string(Self.documentTargetKind),
                    "target_id": .string(documentID), "deleted_at": .string(stamp)
                ]), in: conn)
        }
    }

    // MARK: - Keywords

    /// Throws `MarkdownStoreError.duplicateKeyword` when a *live* keyword
    /// already carries `label`; **revives** the existing row when the clash is
    /// with a tombstone, and returns it under its original id.
    ///
    /// The tombstone half is the interesting half, and reviving is the answer
    /// because of what adh's own constraint is. `UNIQUE (customer_id,
    /// ecosystem_id, label)` there is unconditional, not partial — a
    /// soft-deleted row keeps occupying its label. So minting a second row for
    /// the same label would produce a local state the server would reject on
    /// push, which is the one thing a mirror must never do; and refusing
    /// outright would leave the user permanently unable to re-add a keyword
    /// they once deleted, with no UI anywhere to explain why. Revive is the
    /// only option that is both pushable and honest, and it is also what the
    /// user means: "make this keyword exist again". Keeping the original id is
    /// not a detail — `keyword_items` rows point at it, so a revived keyword
    /// comes back already attached to whatever it was attached to, which is
    /// again what an undelete should mean.
    ///
    /// The conflict clause and the typed error match the siblings
    /// (`addCategoryEdge`, `assignItem`): the bare `INSERT` this replaces threw
    /// a raw `SQLITE_CONSTRAINT`, indistinguishable at the call site from a
    /// disk error.
    public func createKeyword(
        label: String, color: String = "", description: String = "", now: Date = Date()
    ) throws -> MarkdownKeyword {
        let newID = UUID().uuidString.lowercased()
        let stamp = MarkdownTimestamp.string(now)
        let id = try database.write { conn -> String in
            try conn.execute(
                sql: """
                    INSERT INTO keywords
                        (id, customer_id, ecosystem_id, label, color, description,
                         created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (customer_id, ecosystem_id, label) DO UPDATE SET
                        deleted_at = NULL,
                        color = excluded.color,
                        description = excluded.description,
                        updated_at = excluded.updated_at
                    WHERE keywords.deleted_at IS NOT NULL
                    """,
                arguments: [newID, customerID, ecosystemID, label, color,
                            description, stamp, stamp])
            // The `WHERE` makes the UPDATE branch a no-op for a live row, and a
            // no-op `DO UPDATE` changes nothing — so zero here means precisely
            // "the label is taken by a keyword that still exists".
            guard conn.changesCount > 0 else {
                throw MarkdownStoreError.duplicateKeyword(label: label)
            }
            // A revive keeps the tombstone's id, so the id that survived — not
            // the one just minted — is what the caller and the staged mutation
            // must both use.
            let id = try String.fetchOne(
                conn,
                sql: """
                    SELECT id FROM keywords
                    WHERE customer_id = ? AND ecosystem_id = ? AND label = ?
                    """,
                arguments: [customerID, ecosystemID, label]) ?? newID
            var data: [String: JSONValue] = [
                "label": .string(label), "color": .string(color),
                "description": .string(description)
            ]
            // Only on a revive, and only then: a plain create has no `deleted_at`
            // to clear, and a partial upsert that named the column anyway would
            // push a write the server has no reason to receive.
            if id != newID { data["deleted_at"] = .null }
            try syncStore.stage(LocalMutation(
                resource: "content.keywords", rowId: id, type: .upsert,
                data: data), in: conn)
            return id
        }
        return MarkdownKeyword(id: id, label: label, color: color, description: description)
    }

    public func keywords() throws -> [MarkdownKeyword] {
        try database.read { conn in
            try Row.fetchAll(
                conn, sql: "SELECT * FROM keywords WHERE deleted_at IS NULL ORDER BY label"
            ).map {
                MarkdownKeyword(
                    id: $0["id"], label: $0["label"],
                    color: $0["color"], description: $0["description"])
            }
        }
    }

    public func assignKeyword(
        _ keywordID: String, toDocument documentID: String, sortOrder: Int = 0, now: Date = Date()
    ) throws {
        try assignItem(
            table: "keyword_items", resource: "content.keyword_items",
            column: "keyword_id", ownerID: keywordID,
            documentID: documentID, sortOrder: sortOrder, now: now)
    }

    public func keywords(forDocument documentID: String) throws -> [MarkdownKeyword] {
        try database.read { conn in
            try Row.fetchAll(
                conn,
                sql: """
                    SELECT k.* FROM keywords k
                    JOIN keyword_items i ON i.keyword_id = k.id AND i.deleted_at IS NULL
                    WHERE i.target_kind = ? AND i.target_id = ? AND k.deleted_at IS NULL
                    ORDER BY i.sort_order, k.label
                    """,
                arguments: [Self.documentTargetKind, documentID]
            ).map {
                MarkdownKeyword(
                    id: $0["id"], label: $0["label"],
                    color: $0["color"], description: $0["description"])
            }
        }
    }

    // MARK: - The two join tables, which differ only in their name

    /// Both link tables address their target polymorphically — `(target_kind,
    /// target_id)`, with no foreign key, because `target_id` may name a row in
    /// any of several tables. That is what makes the two existence checks
    /// below necessary rather than redundant: nothing in the schema stops a
    /// row filing a nonexistent document under a nonexistent category, and
    /// once written it is invisible (every read joins through
    /// `categories`/`keywords` and filters on `target_id`) yet still pushes
    /// itself to adh, where the same insert fails against real foreign keys.
    /// The owner side *is* foreign-keyed, but its violation would surface as
    /// an opaque SQLite constraint error rather than a `notFound` naming the
    /// id, so it is checked here too.
    private func assignItem(
        table: String, resource: String, column: String, ownerID: String,
        documentID: String, sortOrder: Int, now: Date
    ) throws {
        let ownerTable = column == "category_id" ? "categories" : "keywords"
        let newID = UUID().uuidString.lowercased()
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            let documentExists = try Bool.fetchOne(
                conn, sql: "SELECT EXISTS(SELECT 1 FROM markdown WHERE id = ? AND is_deleted = 0)",
                arguments: [documentID]) ?? false
            guard documentExists else { throw MarkdownStoreError.notFound(documentID) }

            let ownerExists = try Bool.fetchOne(
                conn,
                sql: "SELECT EXISTS(SELECT 1 FROM \(ownerTable) WHERE id = ? AND deleted_at IS NULL)",
                arguments: [ownerID]) ?? false
            guard ownerExists else { throw MarkdownStoreError.notFound(ownerID) }

            try conn.execute(
                sql: """
                    INSERT INTO \(table)
                        (id, customer_id, ecosystem_id, \(column), target_kind, target_id,
                         sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(ecosystem_id, \(column), target_kind, target_id) DO UPDATE SET
                        deleted_at = NULL,
                        sort_order = excluded.sort_order,
                        updated_at = excluded.updated_at
                    WHERE \(table).deleted_at IS NOT NULL
                    """,
                arguments: [newID, customerID, ecosystemID, ownerID,
                            Self.documentTargetKind, documentID, sortOrder, stamp, stamp])
            // The unique this conflicts on is unconditional — deliberately,
            // because adh's is — and `unassignCategory` only *tombstones* the
            // row, so it keeps occupying the key forever. A plain
            // `DO NOTHING` therefore turned "file this note back into the
            // folder you took it out of" into a permanent silent no-op:
            // nothing written, nothing staged, and a *successful* return, with
            // no way for the caller to tell. Reviving is what `createKeyword`
            // does against the same shape of constraint, and for the same
            // reason — minting a second row for a key adh already holds is a
            // local state the server would reject on push.
            //
            // The `WHERE` makes the UPDATE branch a no-op for a live row, so
            // zero changes still means precisely "this assignment already
            // exists and is live" — the case that must not stage a second
            // mutation for a row it never inserted.
            guard conn.changesCount > 0 else { return }
            // A revive keeps the tombstone's id, so the id that survived — not
            // the one just minted — is what the staged mutation must address.
            let rowID = try String.fetchOne(
                conn,
                sql: """
                    SELECT id FROM \(table)
                    WHERE ecosystem_id = ? AND \(column) = ?
                      AND target_kind = ? AND target_id = ?
                    """,
                arguments: [ecosystemID, ownerID, Self.documentTargetKind, documentID]) ?? newID
            var data: [String: JSONValue] = [
                column: .string(ownerID),
                "target_kind": .string(Self.documentTargetKind),
                "target_id": .string(documentID),
                "sort_order": .number(Double(sortOrder))
            ]
            // Only on a revive: a plain insert has no `deleted_at` to clear,
            // and naming the column anyway would push a write adh has no
            // reason to receive.
            if rowID != newID { data["deleted_at"] = .null }
            try syncStore.stage(LocalMutation(
                resource: resource, rowId: rowID, type: .upsert,
                data: data), in: conn)
        }
    }
}
