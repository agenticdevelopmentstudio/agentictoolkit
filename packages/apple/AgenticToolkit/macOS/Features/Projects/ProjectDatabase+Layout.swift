import Foundation
import SQLite3

/// The window layout half of the project database: the tab groups a project
/// opens with, the split tree inside each tab, and the extra directories its
/// file browser shows. Everything here is scoped to one `git_repo.id`, so two
/// projects open at once cannot overwrite each other's arrangement.
extension ProjectDatabase {

    // MARK: - Tabs

    /// Every persisted tab for `repoID` in display order, the active tab's id,
    /// and the enabled edges — or `([], nil, [.top])` for a project that has
    /// never been opened.
    public func loadTabs(repoID: UUID) throws -> (tabs: [TabRecord], activeTabID: UUID?, enabledEdges: [Edge]) {
        let allRows = try fetchNodeRows(repoID: repoID)
        let sql = """
            SELECT id, title, root_node_id, focused_node_id, edge, group_id, working_directory
            FROM project_tabs WHERE repo_id = ? ORDER BY position
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bindText(stmt, 1, repoID.uuidString)

        var tabs: [TabRecord] = []
        try forEachRow(stmt) {
            guard let idText = columnText(stmt, 0),
                  let id = UUID(uuidString: idText),
                  let rootText = columnText(stmt, 2),
                  let rootID = UUID(uuidString: rootText) else { return }
            let edge = columnText(stmt, 4).flatMap { Edge(rawValue: $0) } ?? .top
            tabs.append(TabRecord(
                id: id,
                groupID: columnText(stmt, 5).flatMap { UUID(uuidString: $0) },
                edge: edge,
                title: columnText(stmt, 1) ?? "",
                root: try buildTree(id: rootID, rows: allRows),
                focusedNodeID: columnText(stmt, 3).flatMap { UUID(uuidString: $0) },
                workingDirectory: columnText(stmt, 6).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ))
        }

        let stateSQL = "SELECT active_tab_id, enabled_edges FROM project_state WHERE repo_id = ?"
        var stateStmt: OpaquePointer?
        defer { sqlite3_finalize(stateStmt) }
        guard sqlite3_prepare_v2(database, stateSQL, -1, &stateStmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bindText(stateStmt, 1, repoID.uuidString)
        var activeTabID: UUID?
        var enabledEdges: [Edge] = [.top]
        if try stepRow(stateStmt) {
            activeTabID = columnText(stateStmt, 0).flatMap { UUID(uuidString: $0) }
            // An empty or unparseable column keeps the default rather than
            // becoming an empty list: a window with no enabled edge has no tab
            // bar, so it has nowhere to put the control that would bring one
            // back (`principle-of-least-astonishment`).
            let stored = columnText(stateStmt, 1)?
                .split(separator: ",")
                .compactMap { Edge(rawValue: String($0)) } ?? []
            if !stored.isEmpty { enabledEdges = stored }
        }
        return (tabs, activeTabID, enabledEdges)
    }

    /// Replaces this project's whole arrangement in one transaction. The window
    /// controller always holds every tab on every edge, so a diff would be a
    /// second representation of the same knowledge (`dry`).
    public func saveTabs(
        _ tabs: [TabRecord],
        activeTabID: UUID?,
        enabledEdges: [Edge] = [.top],
        repoID: UUID
    ) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let repoKey = repoID.uuidString
            try executeBound("DELETE FROM project_state WHERE repo_id = ?") { stmt in
                bindText(stmt, 1, repoKey)
            }
            try executeBound("DELETE FROM project_tabs WHERE repo_id = ?") { stmt in
                bindText(stmt, 1, repoKey)
            }
            try executeBound("DELETE FROM layout_nodes WHERE repo_id = ?") { stmt in
                bindText(stmt, 1, repoKey)
            }

            for (index, tab) in tabs.enumerated() {
                try insertNode(tab.root, parentID: nil, position: 0, repoID: repoID)
                try executeBound("""
                    INSERT INTO project_tabs
                        (id, repo_id, position, title, edge, group_id, root_node_id, focused_node_id,
                         working_directory)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """) { stmt in
                    bindText(stmt, 1, tab.id.uuidString)
                    bindText(stmt, 2, repoKey)
                    sqlite3_bind_int(stmt, 3, Int32(index))
                    bindText(stmt, 4, tab.title)
                    bindText(stmt, 5, tab.edge.rawValue)
                    bindText(stmt, 6, tab.groupID.uuidString)
                    bindText(stmt, 7, tab.root.id.uuidString)
                    bindOptionalText(stmt, 8, tab.focusedNodeID?.uuidString)
                    bindOptionalText(stmt, 9, tab.workingDirectory?.path)
                }
            }

            // A pane that is gone takes its remembered state with it. Run after
            // the inserts above, when `layout_nodes` again holds exactly the
            // panes that exist — which is why this needs no id list of its own
            // (`dry`).
            try executeBound("""
                DELETE FROM pane_state
                WHERE repo_id = ?
                  AND node_id NOT IN (SELECT id FROM layout_nodes WHERE repo_id = ?)
            """) { stmt in
                bindText(stmt, 1, repoKey)
                bindText(stmt, 2, repoKey)
            }

            // The state row is always written so enabled edges survive even
            // when no valid active tab exists.
            let validActive = activeTabID.flatMap { id in tabs.contains(where: { $0.id == id }) ? id : nil }
            let edgesJoined = Edge.allCases.filter(enabledEdges.contains).map(\.rawValue).joined(separator: ",")
            try executeBound("""
                INSERT INTO project_state (repo_id, active_tab_id, enabled_edges) VALUES (?, ?, ?)
            """) { stmt in
                bindText(stmt, 1, repoKey)
                bindOptionalText(stmt, 2, validActive?.uuidString)
                bindText(stmt, 3, edgesJoined)
            }
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private func insertNode(_ node: LayoutNode, parentID: UUID?, position: Int, repoID: UUID) throws {
        try executeBound("""
            INSERT INTO layout_nodes
                (id, repo_id, parent_id, position, kind, orientation, content_type, pane_label,
                 thickness_fraction)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """) { stmt in
            bindText(stmt, 1, node.id.uuidString)
            bindText(stmt, 2, repoID.uuidString)
            bindOptionalText(stmt, 3, parentID?.uuidString)
            sqlite3_bind_int(stmt, 4, Int32(position))
            switch node.kind {
            case .split(let orientation, _, _):
                bindText(stmt, 5, "split")
                bindText(stmt, 6, orientation.rawValue)
                sqlite3_bind_null(stmt, 7)
                sqlite3_bind_null(stmt, 8)
            case .leaf(let contentType, let paneLabel):
                bindText(stmt, 5, "leaf")
                sqlite3_bind_null(stmt, 6)
                bindText(stmt, 7, contentType.rawValue)
                bindOptionalText(stmt, 8, paneLabel)
            }
            if let fraction = node.thicknessFraction {
                sqlite3_bind_double(stmt, 9, fraction)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
        }
        if case .split(_, let first, let second) = node.kind {
            try insertNode(first, parentID: node.id, position: 0, repoID: repoID)
            try insertNode(second, parentID: node.id, position: 1, repoID: repoID)
        }
    }

    // MARK: - Tree reconstruction

    private struct NodeRow {
        let id: UUID
        let parentID: UUID?
        let position: Int
        let kind: String
        let orientation: String?
        let contentType: String?
        let paneLabel: String?
        let thicknessFraction: Double?
    }

    private func fetchNodeRows(repoID: UUID) throws -> [UUID: NodeRow] {
        let sql = """
            SELECT id, parent_id, position, kind, orientation, content_type, pane_label,
                   thickness_fraction
            FROM layout_nodes WHERE repo_id = ?
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bindText(stmt, 1, repoID.uuidString)
        var rows: [UUID: NodeRow] = [:]
        try forEachRow(stmt) {
            guard let idText = columnText(stmt, 0), let id = UUID(uuidString: idText) else { return }
            rows[id] = NodeRow(
                id: id,
                parentID: columnText(stmt, 1).flatMap { UUID(uuidString: $0) },
                position: Int(sqlite3_column_int(stmt, 2)),
                kind: columnText(stmt, 3) ?? "",
                orientation: columnText(stmt, 4),
                contentType: columnText(stmt, 5),
                paneLabel: columnText(stmt, 6),
                thicknessFraction: sqlite3_column_type(stmt, 7) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_double(stmt, 7)
            )
        }
        return rows
    }

    private func buildTree(id: UUID, rows: [UUID: NodeRow]) throws -> LayoutNode {
        guard let row = rows[id] else {
            throw ProjectDatabaseError.invalidSchema("missing node \(id)")
        }
        switch row.kind {
        case "leaf":
            let contentType = row.contentType.map { ComposableTabsViewID($0) } ?? .placeholder
            return LayoutNode(
                id: row.id,
                kind: .leaf(contentType: contentType, paneLabel: row.paneLabel),
                thicknessFraction: row.thicknessFraction
            )
        case "split":
            let children = rows.values
                .filter { $0.parentID == id }
                .sorted { $0.position < $1.position }
            guard children.count == 2 else {
                throw ProjectDatabaseError.invalidSchema("split \(id) has \(children.count) children")
            }
            let orientation = row.orientation.flatMap(ComposableTabsAxis.init(rawValue:)) ?? .horizontal
            return LayoutNode(
                id: row.id,
                kind: .split(
                    orientation: orientation,
                    first: try buildTree(id: children[0].id, rows: rows),
                    second: try buildTree(id: children[1].id, rows: rows)
                ),
                thicknessFraction: row.thicknessFraction
            )
        default:
            throw ProjectDatabaseError.invalidSchema("unknown kind \(row.kind)")
        }
    }

    // MARK: - Pane state

    /// What one pane remembers about itself — the folders its file browser had
    /// disclosed, the file it had selected, whatever a later pane needs.
    ///
    /// Keyed by the pane's `layout_nodes.id`, so a pane dragged to the other
    /// side of the window keeps what it knew: the node id travels with the pane
    /// through every rearrangement, while its position does not.
    public func paneState(repoID: UUID, nodeID: UUID, key: String) throws -> String? {
        try queryScalarString(
            "SELECT value FROM pane_state WHERE repo_id = ? AND node_id = ? AND key = ?"
        ) { stmt in
            self.bindText(stmt, 1, repoID.uuidString)
            self.bindText(stmt, 2, nodeID.uuidString)
            self.bindText(stmt, 3, key)
        }
    }

    /// Writes one pane's remembered value; `nil` forgets it.
    public func setPaneState(repoID: UUID, nodeID: UUID, key: String, value: String?) throws {
        guard let value else {
            try executeBound(
                "DELETE FROM pane_state WHERE repo_id = ? AND node_id = ? AND key = ?"
            ) { stmt in
                bindText(stmt, 1, repoID.uuidString)
                bindText(stmt, 2, nodeID.uuidString)
                bindText(stmt, 3, key)
            }
            return
        }
        try executeBound("""
            INSERT INTO pane_state (repo_id, node_id, key, value) VALUES (?, ?, ?, ?)
            ON CONFLICT(repo_id, node_id, key) DO UPDATE SET value = excluded.value
        """) { stmt in
            bindText(stmt, 1, repoID.uuidString)
            bindText(stmt, 2, nodeID.uuidString)
            bindText(stmt, 3, key)
            bindText(stmt, 4, value)
        }
    }

    // MARK: - Project directories

    /// The extra directories this project's file browser shows, in display
    /// order. Only the *additional* ones are stored: the repository's own
    /// folder comes from `git_repo.path`, so it cannot go stale, and an empty
    /// table means "no extras" rather than "not seeded yet".
    public func loadProjectDirectories(repoID: UUID) throws -> [String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT path FROM project_directories WHERE repo_id = ? ORDER BY position"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bindText(stmt, 1, repoID.uuidString)
        var paths: [String] = []
        try forEachRow(stmt) {
            guard let path = columnText(stmt, 0) else { return }
            paths.append(path)
        }
        return paths
    }

    public func saveProjectDirectories(_ paths: [String], repoID: UUID) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try executeBound("DELETE FROM project_directories WHERE repo_id = ?") { stmt in
                bindText(stmt, 1, repoID.uuidString)
            }
            for (index, path) in paths.enumerated() {
                try executeBound("""
                    INSERT INTO project_directories (repo_id, position, path) VALUES (?, ?, ?)
                """) { stmt in
                    bindText(stmt, 1, repoID.uuidString)
                    sqlite3_bind_int(stmt, 2, Int32(index))
                    bindText(stmt, 3, path)
                }
            }
            try execute("COMMIT")
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }
}
