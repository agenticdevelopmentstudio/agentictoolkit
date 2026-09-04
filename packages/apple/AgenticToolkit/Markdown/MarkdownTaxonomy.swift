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

            let id = UUID().uuidString.lowercased()
            let stamp = MarkdownTimestamp.string(now)
            try conn.execute(
                sql: """
                    INSERT INTO category_edges
                        (id, customer_id, ecosystem_id, parent_id, child_id, sort_order,
                         created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(ecosystem_id, parent_id, child_id) DO NOTHING
                    """,
                arguments: [id, customerID, ecosystemID, parent, child, sortOrder, stamp, stamp])
            // `ON CONFLICT DO NOTHING` means this edge already existed — the
            // first call already staged its mutation, so a duplicate call
            // must not queue a second one for a row that was never inserted
            // (it has no local `id` behind it, and adh's own unique
            // constraint would reject or duplicate the push).
            guard conn.changesCount > 0 else { return }
            try syncStore.stage(LocalMutation(
                resource: "content.category_edges", rowId: id, type: .upsert,
                data: [
                    "parent_id": .string(parent), "child_id": .string(child),
                    "sort_order": .number(Double(sortOrder))
                ]), in: conn)
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

    // MARK: - Keywords

    public func createKeyword(
        label: String, color: String = "", description: String = "", now: Date = Date()
    ) throws -> MarkdownKeyword {
        let keyword = MarkdownKeyword(
            id: UUID().uuidString.lowercased(), label: label,
            color: color, description: description)
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO keywords
                        (id, customer_id, ecosystem_id, label, color, description,
                         created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [keyword.id, customerID, ecosystemID, label, color,
                            description, stamp, stamp])
            try syncStore.stage(LocalMutation(
                resource: "content.keywords", rowId: keyword.id, type: .upsert,
                data: [
                    "label": .string(label), "color": .string(color),
                    "description": .string(description)
                ]), in: conn)
        }
        return keyword
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

    private func assignItem(
        table: String, resource: String, column: String, ownerID: String,
        documentID: String, sortOrder: Int, now: Date
    ) throws {
        let id = UUID().uuidString.lowercased()
        let stamp = MarkdownTimestamp.string(now)
        try database.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO \(table)
                        (id, customer_id, ecosystem_id, \(column), target_kind, target_id,
                         sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(ecosystem_id, \(column), target_kind, target_id) DO NOTHING
                    """,
                arguments: [id, customerID, ecosystemID, ownerID,
                            Self.documentTargetKind, documentID, sortOrder, stamp, stamp])
            // `ON CONFLICT DO NOTHING` means this assignment already existed
            // — the first call already staged its mutation, so a duplicate
            // must not queue a second one for a row that was never inserted.
            guard conn.changesCount > 0 else { return }
            try syncStore.stage(LocalMutation(
                resource: resource, rowId: id, type: .upsert,
                data: [
                    column: .string(ownerID),
                    "target_kind": .string(Self.documentTargetKind),
                    "target_id": .string(documentID),
                    "sort_order": .number(Double(sortOrder))
                ]), in: conn)
        }
    }
}
