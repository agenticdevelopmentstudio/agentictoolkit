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

    /// Where each drawn row currently sits, by handle, with `""` for a root.
    ///
    /// The inverse of `childrenByHandle`, kept because the question `adopt`
    /// has to answer is the one the forward map cannot: *does this id already
    /// belong to somebody else?* Searching every branch for it on every item
    /// of every refresh is the alternative.
    private(set) var parentByHandle: [String: String] = [:]

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

    /// What an `adopt` did, for a caller that has to redraw the result.
    struct Adoption {

        /// The rows now under the adopting handle, in the order the extension
        /// gave them.
        let rows: [ExtensionTreeRow]

        /// Other branches this adoption changed, because a row they were
        /// drawing has moved here. Empty in the ordinary case; a caller that
        /// ignores it leaves those branches drawing a row that is no longer
        /// theirs.
        let displacedParents: [String]
    }

    /// Puts a freshly read list of children in place, reusing the row object
    /// for every handle that survived and forgetting the subtrees of those that
    /// did not.
    ///
    /// Reuse is what keeps the user's disclosure across a refresh: the outline
    /// view tracks expansion by object identity, so a row that comes back as a
    /// new object comes back closed.
    ///
    /// **One row is in exactly one place, and this is where that is enforced.**
    /// `NSOutlineView` identifies rows by object, so the same row object at two
    /// positions is not a cosmetic duplicate — one `row(forItem:)` index stands
    /// for two rows, disclosure is shared between them, and the reload walks a
    /// structure the view and this table no longer agree on. Two ways in, both
    /// of them an ordinary provider bug rather than anything exotic:
    ///
    /// - **The same id twice in one list** — a `map` over a list with a repeat
    ///   in it. The first wins and the rest are dropped.
    /// - **The same id under two parents** — the newest claim wins, because it
    ///   is the one the extension has just made, and the branch the row left is
    ///   named in `displacedParents` so its caller can redraw it. Moving rather
    ///   than refusing matters: a refresh where an item genuinely moved reaches
    ///   the two branches in an order nobody controls, and a refusal in the
    ///   wrong order makes the item vanish from both.
    @discardableResult
    mutating func adopt(_ items: [ContributedTreeItem], under handle: String) -> Adoption {
        let previous = childrenByHandle[handle] ?? []
        var next: [ExtensionTreeRow] = []
        var taken: Set<String> = []
        var displaced: [String] = []
        for item in items {
            guard taken.insert(item.id).inserted else { continue }
            if let existing = rows[item.id] {
                existing.item = item
                next.append(existing)
                if let owner = parentByHandle[item.id], owner != handle {
                    childrenByHandle[owner]?.removeAll { $0.handle == item.id }
                    if !displaced.contains(owner) { displaced.append(owner) }
                }
            } else {
                let row = ExtensionTreeRow(item: item)
                rows[item.id] = row
                next.append(row)
            }
            parentByHandle[item.id] = handle
        }
        childrenByHandle[handle] = next
        let survivors = Set(next.map(\.handle))
        for gone in previous where !survivors.contains(gone.handle) {
            // Only what still belongs here. A row that has moved on is
            // somebody else's to keep, and forgetting it would take it out
            // from under the branch now drawing it.
            guard parentByHandle[gone.handle] == handle else { continue }
            forget(gone.handle)
        }
        return Adoption(rows: next, displacedParents: displaced)
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
            parentByHandle[next] = nil
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
