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
        let first = table.adopt([item("a"), item("b")], under: "")
        let second = table.adopt([item("a"), item("b")], under: "")
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
}
