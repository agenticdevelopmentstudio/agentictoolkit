import Foundation

/// The rows an extension tree pane has drawn, and how they are related.
///
/// Split out of `ExtensionTreeOutlineViewController` because it is the half
/// with no view in it: a handle graph, a row per handle, and the rule for what
/// leaves when a parent stops naming a child. The controller keeps the outline
/// view, the reload bookkeeping and the selection; this keeps the answer to
/// "what is under this handle, and what is gone".
///
/// Worth its own type for one reason beyond tidiness: the walk in `forget` has
/// a termination condition that depends on data an extension supplies, and that
/// is a thing to test directly rather than through a loaded view.
@MainActor
struct ExtensionTreeRowTable {

    /// Every row currently drawn, by handle. Kept across a refresh so the
    /// outline sees the same objects and keeps its disclosure; pruned in
    /// `adopt` when a parent stops naming a child, which is the only way a
    /// handle can leave.
    private(set) var rows: [String: ExtensionTreeRow] = [:]

    /// The children of each handle the pane has actually asked for, keyed by
    /// the parent's handle and `""` for the roots. Its key set is exactly the
    /// set of branches a refresh has to re-ask, which is what keeps a
    /// whole-tree refresh from walking a tree nobody has opened.
    private(set) var childrenByHandle: [String: [ExtensionTreeRow]] = [:]

    /// Rows whose `collapsibleState` was `.expanded` and which have therefore
    /// been opened once. Once only: a default is what fills in for an answer,
    /// never what overrules one, so a branch the user has closed stays closed
    /// through every later refresh.
    private(set) var autoExpandedHandles: Set<String> = []

    // MARK: - Reading

    var isEmpty: Bool { childrenByHandle.isEmpty }

    func row(for handle: String) -> ExtensionTreeRow? { rows[handle] }

    func children(of handle: String) -> [ExtensionTreeRow]? { childrenByHandle[handle] }

    func hasLoaded(_ handle: String) -> Bool { childrenByHandle[handle] != nil }

    var loadedBranches: [String] { Array(childrenByHandle.keys) }

    // MARK: - Writing

    /// Puts a freshly read list of children in place, reusing the row object
    /// for every handle that survived and forgetting the subtrees of those that
    /// did not.
    ///
    /// Reuse is what keeps the user's disclosure across a refresh: the outline
    /// view tracks expansion by object identity, so a row that comes back as a
    /// new object comes back closed.
    ///
    /// - Returns: The rows now under `handle`, in the order the extension gave.
    @discardableResult
    mutating func adopt(_ items: [ContributedTreeItem], under handle: String) -> [ExtensionTreeRow] {
        let previous = childrenByHandle[handle] ?? []
        var next: [ExtensionTreeRow] = []
        for item in items {
            if let existing = rows[item.id] {
                existing.item = item
                next.append(existing)
            } else {
                let row = ExtensionTreeRow(item: item)
                rows[item.id] = row
                next.append(row)
            }
        }
        childrenByHandle[handle] = next
        let survivors = Set(next.map(\.handle))
        for gone in previous where !survivors.contains(gone.handle) {
            forget(gone.handle)
        }
        return next
    }

    /// Drops a handle and everything under it.
    ///
    /// The walk is what keeps `rows` from accumulating every branch an
    /// extension has ever shown: a parent that stops naming a child is the only
    /// news that a whole subtree is gone, and nothing else will report it.
    ///
    /// **Iterative, and it refuses to visit a handle twice.** A handle is an
    /// extension's declared `TreeItem.id` whenever it declares one, and nothing
    /// stops an extension declaring the same id for a row and for one of that
    /// row's own descendants. That makes `childrenByHandle` a graph with a
    /// cycle in it rather than a tree, and the recursive form of this walked
    /// the cycle until the stack ran out — an extension's typo crashing the
    /// app. The `seen` set is the whole fix; it costs one insert per handle on
    /// every tree that does not have the problem.
    mutating func forget(_ handle: String) {
        var doomed = [handle]
        var seen: Set<String> = []
        while let next = doomed.popLast() {
            guard seen.insert(next).inserted else { continue }
            doomed.append(contentsOf: (childrenByHandle[next] ?? []).map(\.handle))
            childrenByHandle[next] = nil
            rows[next] = nil
            autoExpandedHandles.remove(next)
        }
    }

    /// Records that `handle` has had its one automatic expansion.
    ///
    /// - Returns: `true` if this is the first time, which is the caller's cue
    ///   to actually open the branch.
    mutating func markAutoExpanded(_ handle: String) -> Bool {
        autoExpandedHandles.insert(handle).inserted
    }
}
