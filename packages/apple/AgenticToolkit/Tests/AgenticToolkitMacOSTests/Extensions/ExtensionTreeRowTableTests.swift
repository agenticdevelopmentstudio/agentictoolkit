import Testing
@testable import AgenticToolkitMacOS

/// The row graph behind a contributed tree pane.
///
/// Tested away from the outline view on purpose: what is interesting here is
/// which handles survive a refresh and which leave, and none of that needs a
/// window. The view's own job — drawing them, keeping disclosure, restoring
/// selection — is what stayed in the controller.
@MainActor
struct ExtensionTreeRowTableTests {

    private func item(
        _ id: String, expanded: Bool = false, children: Bool = false
    ) -> ContributedTreeItem {
        ContributedTreeItem(
            id: id,
            label: id,
            description: nil,
            tooltip: nil,
            collapsibleState: expanded ? .expanded : (children ? .collapsed : .none),
            symbolName: nil,
            commandID: nil)
    }

    // MARK: - Reuse

    /// The outline view tracks expansion by object identity, so a row that
    /// comes back from a refresh as a new object comes back closed. Reuse is
    /// what keeps the user's disclosure across an extension's `refresh()`.
    @Test("a row that survives a refresh is the same object")
    func aSurvivingRowKeepsItsIdentity() {
        var table = ExtensionTreeRowTable()
        let first = table.adopt([item("a"), item("b")], under: "").rows
        let second = table.adopt([item("a"), item("b")], under: "").rows
        #expect(first[0] === second[0])
        #expect(first[1] === second[1])
    }

    /// And its `item` is rewritten in place, or the row would draw the label it
    /// had before the refresh.
    @Test("a reused row takes the new item")
    func aReusedRowTakesTheNewItem() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a")], under: "")
        _ = table.adopt(
            [ContributedTreeItem(
                id: "a", label: "renamed", description: nil, tooltip: nil,
                collapsibleState: .none, symbolName: nil, commandID: nil)],
            under: "")
        #expect(table.row(for: "a")?.item.label == "renamed")
    }

    // MARK: - Leaving

    /// A parent that stops naming a child is the only news that the child is
    /// gone — there is no removal event in the protocol.
    @Test("a child a parent stops naming is forgotten")
    func aDroppedChildIsForgotten() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a"), item("b")], under: "")
        _ = table.adopt([item("a")], under: "")
        #expect(table.row(for: "a") != nil)
        #expect(table.row(for: "b") == nil)
    }

    /// And so is everything beneath it, at any depth: nothing else will report
    /// that a whole subtree left.
    @Test("a dropped child takes its whole subtree")
    func aDroppedChildTakesItsDescendants() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a", children: true)], under: "")
        _ = table.adopt([item("a-1", children: true)], under: "a")
        _ = table.adopt([item("a-1-1")], under: "a-1")

        _ = table.adopt([], under: "")
        #expect(table.row(for: "a") == nil)
        #expect(table.row(for: "a-1") == nil)
        #expect(table.row(for: "a-1-1") == nil)
        #expect(table.children(of: "a-1") == nil)
    }

    /// The crash. A handle is the extension's declared `TreeItem.id` whenever
    /// it declares one, and nothing stops an extension using the same id for a
    /// row and for one of that row's own descendants — a copy-paste in a
    /// provider is enough. That makes the child table a graph with a cycle in
    /// it, and the walk that drops a subtree used to recurse straight round it
    /// until the stack ran out, taking the app with it.
    ///
    /// Reaching the assertion at all is the test: the old form never returned.
    @Test("a tree that declares itself its own descendant is still forgettable")
    func aCycleDoesNotRunForever() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a", children: true)], under: "")
        _ = table.adopt([item("b", children: true)], under: "a")
        // `b`'s child is `a` again — the extension reused the id.
        _ = table.adopt([item("a", children: true)], under: "b")

        table.forget("a")
        #expect(table.row(for: "a") == nil)
        #expect(table.row(for: "b") == nil)
    }

    // MARK: - Opening once

    /// A default is what fills in for an answer, never what overrules one, so a
    /// branch the user has closed stays closed through every later refresh.
    @Test("a branch is auto-expanded once and never again")
    func autoExpansionHappensOnce() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a", expanded: true)], under: "")
        // Bound to locals because `#expect` captures its expression in a
        // closure, which cannot call a `mutating` member.
        let first = table.markAutoExpanded("a")
        let second = table.markAutoExpanded("a")
        #expect(first)
        #expect(!second)
    }

    /// But a branch that left the tree and came back is a new branch, and gets
    /// the extension's stated default again.
    @Test("a branch that left and came back is auto-expanded again")
    func autoExpansionResetsWhenARowLeaves() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a", expanded: true)], under: "")
        let onFirstAppearance = table.markAutoExpanded("a")
        _ = table.adopt([], under: "")
        _ = table.adopt([item("a", expanded: true)], under: "")
        let onReturn = table.markAutoExpanded("a")
        #expect(onFirstAppearance)
        #expect(onReturn)
    }

    // MARK: - One row, one place

    /// **`NSOutlineView` requires an item to appear exactly once.** Handing it
    /// the same object twice under one parent is not a cosmetic duplicate: the
    /// view identifies rows by object, so `row(forItem:)` answers one index for
    /// two rows, expansion state is shared between them, and the reload that
    /// follows walks a structure the view and this table disagree about.
    ///
    /// Nothing stops an extension returning the same `id` twice from one
    /// `getChildren` — a `map` over a list with a repeat in it is all it takes
    /// — so the rule is enforced where the list arrives.
    @Test("a duplicate id within one list is taken once")
    func aDuplicateIdInOneListIsTakenOnce() {
        var table = ExtensionTreeRowTable()
        let children = table.adopt([item("a"), item("b"), item("a")], under: "").rows
        #expect(children.map(\.handle) == ["a", "b"])
        #expect(table.children(of: "")?.count == 2)
    }

    /// The same rule across parents. An id under two branches at once is the
    /// same object in two places, which is the same impossibility for the
    /// outline view — and worse for this table, because the `forget` that
    /// follows either parent dropping it takes the row out from under the
    /// other one.
    ///
    /// The newest claim wins, because it is the one the extension has just
    /// made: the row moves, and the branch it left is reported so its
    /// caller can redraw it rather than keep drawing a row that has gone.
    @Test("an id claimed by a second parent moves, and the first is told")
    func anIdClaimedByASecondParentMoves() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true), item("parent-b", children: true)],
                        under: "")
        _ = table.adopt([item("shared")], under: "parent-a")

        let displaced = table.adopt([item("shared")], under: "parent-b").displacedParents

        #expect(displaced == ["parent-a"])
        #expect(table.children(of: "parent-a")?.map(\.handle) == [])
        #expect(table.children(of: "parent-b")?.map(\.handle) == ["shared"])
        // Still one row object, still present — a move, not a delete.
        #expect(table.row(for: "shared") != nil)
    }

    /// And the row survives the move as the *same* object, or the branch it
    /// moved into would draw it collapsed and the outline would lose whatever
    /// was open underneath it.
    @Test("a moved row keeps its identity")
    func aMovedRowKeepsItsIdentity() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true), item("parent-b", children: true)],
                        under: "")
        let before = table.adopt([item("shared")], under: "parent-a").rows
        let after = table.adopt([item("shared")], under: "parent-b").rows
        #expect(before[0] === after[0])
    }

    /// Re-adopting the same list under the same parent is not a move, and must
    /// not report one — a refresh of one branch would otherwise ask its caller
    /// to redraw that same branch a second time, every time.
    @Test("re-adopting a branch displaces nothing")
    func reAdoptingABranchDisplacesNothing() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a"), item("b")], under: "")
        let displaced = table.adopt([item("a"), item("b")], under: "").displacedParents
        #expect(displaced.isEmpty)
    }

    // MARK: - A move whose two halves arrive in either order

    /// **The order the extension answers in is not ours to choose.** A refresh
    /// asks every loaded branch at once, and a row that moved from A to B is
    /// dropped by A and claimed by B in whichever order `getChildren` happens
    /// to finish. `aMovedRowKeepsItsIdentity` above is the lucky order — B
    /// first — and it passed while the unlucky one destroyed the row.
    ///
    /// Destroyed is not an overstatement: a new object comes back closed,
    /// because `NSOutlineView` tracks disclosure by identity, and its loaded
    /// children are gone with it.
    @Test("a row moved between branches survives the old branch answering first")
    func aMovedRowSurvivesTheOldBranchAnsweringFirst() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true), item("parent-b", children: true)],
                        under: "")
        let before = table.adopt([item("shared")], under: "parent-a").rows

        // A answers first, and no longer names the row.
        _ = table.adopt([], under: "parent-a")
        // Then B does.
        let after = table.adopt([item("shared")], under: "parent-b").rows

        #expect(before[0] === after[0])
        #expect(table.row(for: "shared") != nil)
    }

    /// And the subtree under it comes back too — which is what makes the row's
    /// identity worth keeping. A row that returns as the same object with its
    /// children thrown away still collapses everything below it.
    @Test("a moved row brings its loaded subtree back with it")
    func aMovedRowKeepsItsSubtree() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true), item("parent-b", children: true)],
                        under: "")
        _ = table.adopt([item("shared", children: true)], under: "parent-a")
        let grandchild = table.adopt([item("leaf")], under: "shared").rows

        _ = table.adopt([], under: "parent-a")
        _ = table.adopt([item("shared", children: true)], under: "parent-b")

        #expect(table.children(of: "shared")?.count == 1)
        #expect(table.row(for: "leaf") === grandchild[0])
    }

    /// While it is in between, it is *gone* as far as anyone outside this type
    /// is concerned. Holding the object is an implementation detail of the
    /// reclaim; a pane that drew a row no branch lists would be drawing a row
    /// the extension has removed.
    @Test("a dropped row is invisible while it is held")
    func aDroppedRowIsInvisibleWhileHeld() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true)], under: "")
        _ = table.adopt([item("shared", children: true)], under: "parent-a")
        _ = table.adopt([item("leaf")], under: "shared")

        _ = table.adopt([], under: "parent-a")

        #expect(table.row(for: "shared") == nil)
        #expect(table.row(for: "leaf") == nil)
        #expect(table.children(of: "parent-a")?.isEmpty == true)
        #expect(!table.loadedBranches.contains("shared"))
    }

    /// And when the refresh settles with nobody having claimed it, it really
    /// does leave — holding it forever would be a leak of one row per deleted
    /// item, growing for as long as the pane is open.
    @Test("an orphan nobody claimed is forgotten when the refresh settles")
    func anUnclaimedOrphanIsForgottenOnPrune() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true)], under: "")
        _ = table.adopt([item("shared", children: true)], under: "parent-a")
        _ = table.adopt([item("leaf")], under: "shared")

        _ = table.adopt([], under: "parent-a")
        table.pruneOrphans()

        #expect(table.row(for: "shared") == nil)
        #expect(table.row(for: "leaf") == nil)
        // Not merely hidden: the branch's children are gone from the graph, so
        // a later row with the same id starts clean rather than inheriting a
        // stale subtree.
        #expect(table.children(of: "shared") == nil)
        #expect(table.children(of: "leaf") == nil)
    }

    /// A prune must not touch a row that was reclaimed in the same pass, which
    /// is the assertion that stops "forget everything at the end" from passing
    /// the tests above.
    @Test("a reclaimed row survives the prune that follows")
    func aReclaimedRowSurvivesThePrune() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true), item("parent-b", children: true)],
                        under: "")
        let before = table.adopt([item("shared")], under: "parent-a").rows

        _ = table.adopt([], under: "parent-a")
        _ = table.adopt([item("shared")], under: "parent-b")
        table.pruneOrphans()

        #expect(table.row(for: "shared") === before[0])
        #expect(table.children(of: "parent-b")?.count == 1)
    }

    /// Pruning twice is pruning once — the sweep runs after every settled
    /// refresh, so most of its calls have nothing to do.
    @Test("pruning with nothing orphaned changes nothing")
    func pruningNothingChangesNothing() {
        var table = ExtensionTreeRowTable()
        let rows = table.adopt([item("a"), item("b")], under: "").rows

        table.pruneOrphans()
        table.pruneOrphans()

        #expect(table.row(for: "a") === rows[0])
        #expect(table.row(for: "b") === rows[1])
    }

    /// **A branch that drops an item and later names it again has not moved
    /// anything.** One branch is asked once per refresh, so those two answers
    /// came from two refreshes with the item genuinely absent in between —
    /// which is an item that left and a different one that arrived, not the
    /// interleaving this deferral exists for.
    ///
    /// The distinction is not academic: the row it gets is what decides
    /// whether the extension's stated default expansion applies again, and
    /// rescuing here would silently repeal
    /// `autoExpansionResetsWhenARowLeaves`.
    @Test("a branch that names a dropped row again gets a new row, not the held one")
    func aReturnToTheSameBranchIsNotAReclaim() {
        var table = ExtensionTreeRowTable()
        let before = table.adopt([item("a", expanded: true)], under: "").rows

        _ = table.adopt([], under: "")
        let after = table.adopt([item("a", expanded: true)], under: "").rows

        #expect(before[0] !== after[0])
        // Bound to a local because `#expect` cannot call a `mutating` member.
        let expandsAgain = table.markAutoExpanded("a")
        #expect(expandsAgain)
    }

    /// And the subtree it had does not come back with it, for the same reason:
    /// this is a new item, and its children are whatever the extension answers
    /// for it now.
    @Test("a row that returns to the same branch does not inherit its old subtree")
    func aReturnToTheSameBranchStartsEmpty() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("a", children: true)], under: "")
        _ = table.adopt([item("stale")], under: "a")

        _ = table.adopt([], under: "")
        _ = table.adopt([item("a", children: true)], under: "")

        #expect(table.children(of: "a") == nil)
        #expect(table.row(for: "stale") == nil)
    }

    /// The other half of the same rule, stated where it can fail: a claim by a
    /// *different* branch keeps everything, auto-expansion included. A row that
    /// merely moved and came back wanting to re-open itself is the bug in the
    /// opposite direction.
    @Test("a row reclaimed by another branch keeps its one automatic expansion")
    func aReclaimByAnotherBranchKeepsItsExpansion() {
        var table = ExtensionTreeRowTable()
        _ = table.adopt([item("parent-a", children: true), item("parent-b", children: true)],
                        under: "")
        _ = table.adopt([item("shared", expanded: true)], under: "parent-a")
        let onFirstAppearance = table.markAutoExpanded("shared")

        _ = table.adopt([], under: "parent-a")
        _ = table.adopt([item("shared", expanded: true)], under: "parent-b")
        let onReclaim = table.markAutoExpanded("shared")

        #expect(onFirstAppearance)
        #expect(!onReclaim)
    }
}
