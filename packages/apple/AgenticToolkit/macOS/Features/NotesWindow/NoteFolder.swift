import Foundation
import AgenticToolkitMarkdown

/// A node in the folders pane's tree, built from the store's flat
/// `categories()` / `categoryEdges()` output by `tree(from:counts:edges:total:)`.
///
/// `id == ""` is reserved for the synthetic "All Notes" root, which is never
/// produced by `tree(from:counts:edges:total:)` itself — `createCategory`
/// mints a lowercased UUID, so a real category id is never empty, and the
/// caller (the folders pane) constructs "All Notes" directly from `total`.
public struct NoteFolder: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var noteCount: Int
    public var children: [NoteFolder]

    public init(id: String, name: String, noteCount: Int, children: [NoteFolder]) {
        self.id = id
        self.name = name
        self.noteCount = noteCount
        self.children = children
    }

    public var isAllNotes: Bool { id.isEmpty }

    /// Builds the folder tree from the store's flat reads.
    ///
    /// - `counts` and `edges` are direct, not transitive (see
    ///   `MarkdownStore.categoryNoteCounts()`'s doc comment) — a folder's
    ///   `noteCount` is its own count, and a parent's can be smaller than the
    ///   sum of its children's.
    /// - A category reachable from more than one parent (the schema allows a
    ///   diamond) is built once per parent and appears as a separate value
    ///   under each — `NoteFolder` has no identity beyond its fields, so two
    ///   equal-looking nodes in different branches are simply two values, not
    ///   a shared reference.
    /// - `total` is `store.documents(marker: .note).count`, not
    ///   `counts.values.reduce(0, +)`: a note filed under two categories would
    ///   be double-counted by the sum, and an uncategorised note would be
    ///   missed by it entirely. The caller uses `total` to build "All Notes";
    ///   `tree` itself never produces that node.
    /// - `addCategoryEdge` refuses a cycle at write time, so a live database
    ///   never has one — but a database written by adh, or by a future bug,
    ///   still could. `visited` bounds every downward walk to the categories
    ///   not already on the current path, so a cycle truncates the branch
    ///   instead of recursing forever. A category that is only reachable
    ///   through a cycle (every node on the cycle has an incoming edge, so
    ///   none of them qualifies as a root by the rule below) is still shown,
    ///   rather than silently dropped, by falling back to treating the whole
    ///   cycle as roots when no true root exists.
    public static func tree(
        from categories: [MarkdownCategory],
        counts: [String: Int],
        edges: [(parent: String, child: String)],
        total: Int
    ) -> [NoteFolder] {
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var childrenByParent: [String: [String]] = [:]
        var hasIncomingEdge: Set<String> = []
        for edge in edges where categoriesByID[edge.parent] != nil && categoriesByID[edge.child] != nil {
            childrenByParent[edge.parent, default: []].append(edge.child)
            hasIncomingEdge.insert(edge.child)
        }

        func node(for id: String, visited: Set<String>) -> NoteFolder? {
            guard let category = categoriesByID[id], !visited.contains(id) else { return nil }
            let visited = visited.union([id])
            let children = (childrenByParent[id] ?? [])
                .compactMap { node(for: $0, visited: visited) }
            return NoteFolder(
                id: category.id, name: category.name,
                noteCount: counts[category.id] ?? 0, children: children)
        }

        let rootIDs = categories.map(\.id).filter { !hasIncomingEdge.contains($0) }
        // Every category sits on a cycle with no true root: fall back to
        // treating all of them as roots rather than losing the whole graph.
        let effectiveRootIDs = rootIDs.isEmpty ? categories.map(\.id) : rootIDs
        return effectiveRootIDs.compactMap { node(for: $0, visited: []) }
    }
}
