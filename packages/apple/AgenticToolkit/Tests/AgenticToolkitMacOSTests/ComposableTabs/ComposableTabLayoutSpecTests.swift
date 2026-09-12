import XCTest
import AppKit
import AgenticToolkitMacOS

/// The layout contract: which arrangements a spec declares legal, which moves
/// it offers from a given pane, and what it does with a stored tree that no
/// longer obeys it.
@MainActor
final class ComposableTabLayoutSpecTests: XCTestCase {

    private let list = ComposableTabsViewID("test.spec.list")
    private let editor = ComposableTabsViewID("test.spec.editor")
    private let terminal = ComposableTabsViewID("test.spec.terminal")
    private let unregistered = ComposableTabsViewID("test.spec.nobody-vends-this")

    private func makeRegistry() -> ComposableTabsViewRegistry {
        let registry = ComposableTabsViewRegistry()
        for (viewID, axis) in [(list, ComposableTabsAxis.horizontal),
                               (editor, .horizontal),
                               (terminal, .vertical)] {
            registry.register(
                viewID,
                descriptor: .init(displayName: viewID.rawValue, preferredAxis: axis)
            ) { PlaceholderPaneViewController(paneNumber: $0.paneNumber) }
        }
        return registry
    }

    /// A pinned list on the left, an editor above a terminal on the right —
    /// the shape most of these assertions are about.
    private var spec: ComposableTabLayoutSpec {
        .split(
            axis: .horizontal,
            children: [
                .pane(list, isFixed: true),
                .split(axis: .vertical, children: [.pane(editor), .pane(terminal)])
            ],
            allows: [
                .init(list, min: 1, max: 1),
                .init(editor, min: 0, max: 1),
                .unbounded(terminal)
            ]
        )
    }

    // MARK: - Validation

    func testASpecNamingAnUnregisteredViewIsRejected() {
        XCTAssertThrowsError(
            try ComposableTabLayoutSpec
                .pane(unregistered, allows: [.init(unregistered)])
                .validate(against: makeRegistry())
        ) { error in
            XCTAssertEqual(
                error as? ComposableTabLayoutSpecError, .unregisteredView(unregistered))
        }
    }

    func testAPaneThatAllowsNothingIsRejected() {
        XCTAssertThrowsError(
            try ComposableTabLayoutSpec.pane().validate(against: makeRegistry())
        ) { error in
            XCTAssertEqual(error as? ComposableTabLayoutSpecError, .nodeAllowsNothing)
        }
    }

    func testAPaneStartingWithAViewItDoesNotAllowIsRejected() {
        XCTAssertThrowsError(
            try ComposableTabLayoutSpec
                .split(axis: .horizontal,
                       children: [.pane(terminal)],
                       allows: [.init(editor)])
                .validate(against: makeRegistry())
        ) { error in
            XCTAssertEqual(
                error as? ComposableTabLayoutSpecError, .initialViewNotAllowed(terminal))
        }
    }

    func testAnImpossibleCardinalityIsRejected() {
        XCTAssertThrowsError(
            try ComposableTabLayoutSpec
                .pane(editor, allows: [.init(editor, min: 2, max: 1)])
                .validate(against: makeRegistry())
        ) { error in
            XCTAssertEqual(
                error as? ComposableTabLayoutSpecError,
                .invalidCardinality(editor, min: 2, max: 1))
        }
    }

    func testAWellFormedSpecValidates() throws {
        XCTAssertNoThrow(try spec.validate(against: makeRegistry()))
    }

    /// Inheritance is the point of the tree: a child pane that restates nothing
    /// is still governed by what its ancestors allow.
    func testAChildPaneInheritsItsAncestorsAllowances() {
        XCTAssertNoThrow(
            try ComposableTabLayoutSpec
                .split(axis: .horizontal,
                       children: [.pane(editor), .pane(terminal)],
                       allows: [.init(editor), .unbounded(terminal)])
                .validate(against: makeRegistry())
        )
    }

    // MARK: - Blueprint

    func testBlueprintMatchesTheDeclaredShape() {
        let tree = spec.blueprint()
        XCTAssertEqual(leafViewIDs(in: tree), [list, editor, terminal])
        guard case .split(let axis, _, let second) = tree.kind else {
            return XCTFail("the root spec is a split, so the blueprint must be one")
        }
        XCTAssertEqual(axis, .horizontal)
        guard case .split(let innerAxis, _, _) = second.kind else {
            return XCTFail("the right-hand child spec is a split too")
        }
        XCTAssertEqual(innerAxis, .vertical)
    }

    /// Storage and the split-view controller are both binary, so a three-way
    /// spec has to become a chain rather than being silently truncated.
    func testASplitWithThreeChildrenBecomesARightLeaningChain() {
        let tree = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(editor), .pane(terminal)],
            allows: [.init(list), .init(editor), .unbounded(terminal)]
        ).blueprint()

        XCTAssertEqual(leafViewIDs(in: tree), [list, editor, terminal])
        guard case .split(_, let first, let second) = tree.kind else {
            return XCTFail("expected a split at the root")
        }
        guard case .leaf = first.kind, case .split = second.kind else {
            return XCTFail("a three-way split must lean right: leaf, then a nested split")
        }
    }

    /// A pane with no `initial` gets the first view its region requires, so a
    /// `min: 1` view is present from the start rather than after a user gesture.
    func testAPaneWithNoInitialViewTakesTheFirstRequiredOne() {
        let tree = ComposableTabLayoutSpec.pane(
            allows: [.init(editor, min: 0, max: 1), .init(list, min: 1, max: 1)]
        ).blueprint()
        XCTAssertEqual(leafViewIDs(in: tree), [list])
    }

    // MARK: - Legal moves

    func testAViewAtItsMaximumIsNotOfferedAgain() {
        let registry = makeRegistry()
        let tree = spec.blueprint()
        guard let editorLeaf = leaf(holding: editor, in: tree) else {
            return XCTFail("the blueprint must contain the editor")
        }
        let insertions = spec.allowedInsertions(
            at: editorLeaf.id, in: tree, registry: registry)

        // One editor and one list are already placed and both cap at 1;
        // terminal is unbounded, so it is the only thing left to add.
        XCTAssertEqual(insertions.map(\.viewID), [terminal])
    }

    func testAnUnusedOptionalViewIsOffered() {
        let registry = makeRegistry()
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(terminal)],
            allows: [.init(list, min: 1, max: 1), .init(editor), .unbounded(terminal)]
        )
        let tree = spec.blueprint()
        let terminalLeaf = leaf(holding: terminal, in: tree)
        let insertions = spec.allowedInsertions(
            at: terminalLeaf?.id ?? UUID(), in: tree, registry: registry)

        XCTAssertEqual(insertions.map(\.viewID), [editor, terminal])
    }

    /// An allowance's `preferredAxis` beats the registry descriptor's, because
    /// it is the more specific statement about this region.
    func testAnAllowanceOverridesTheDescriptorsPreferredAxis() {
        let registry = makeRegistry()
        let spec = ComposableTabLayoutSpec.pane(
            editor,
            allows: [.init(editor, min: 0, max: nil, preferredAxis: .vertical)]
        )
        let tree = spec.blueprint()
        let insertions = spec.allowedInsertions(
            at: tree.id, in: tree, registry: registry)

        XCTAssertEqual(insertions.first?.preferredAxis, .vertical,
                       "the descriptor prefers horizontal; the allowance says otherwise")
    }

    func testAFixedRegionOffersNothingAndRefusesBothMoves() {
        let tree = spec.blueprint()
        guard let listLeaf = leaf(holding: list, in: tree) else {
            return XCTFail("the blueprint must contain the pinned list")
        }

        XCTAssertTrue(spec.isFixed(listLeaf.id, in: tree))
        XCTAssertTrue(spec.allowedInsertions(
            at: listLeaf.id, in: tree, registry: makeRegistry()).isEmpty)
        XCTAssertFalse(spec.canSplit(listLeaf.id, in: tree))
        XCTAssertFalse(spec.canRemove(listLeaf.id, from: tree))
    }

    // MARK: - Removal

    func testTheLastPaneInATabCannotBeRemoved() {
        let spec = ComposableTabLayoutSpec.pane(terminal, allows: [.unbounded(terminal)])
        let tree = spec.blueprint()
        XCTAssertFalse(spec.canRemove(tree.id, from: tree))
    }

    func testRemovingWouldNotBeAllowedToDropAViewBelowItsMinimum() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(terminal)],
            allows: [.init(list, min: 1, max: 1), .unbounded(terminal)]
        )
        let tree = spec.blueprint()
        guard let listLeaf = leaf(holding: list, in: tree),
              let terminalLeaf = leaf(holding: terminal, in: tree) else {
            return XCTFail("the blueprint must contain both panes")
        }

        XCTAssertFalse(spec.canRemove(listLeaf.id, from: tree),
                       "the only required list may not be removed")
        XCTAssertTrue(spec.canRemove(terminalLeaf.id, from: tree),
                      "an optional, unbounded pane may be")
    }

    // MARK: - Reconciliation

    func testALeafHoldingAViewTheSpecNoLongerAllowsBecomesAPlaceholder() {
        let stored = LayoutNode.split(
            orientation: .horizontal,
            first: LayoutNode.leaf(contentType: terminal),
            second: LayoutNode.leaf(contentType: editor)
        )
        let spec = ComposableTabLayoutSpec.pane(terminal, allows: [.unbounded(terminal)])

        XCTAssertEqual(leafViewIDs(in: spec.reconcile(stored)), [terminal, .placeholder])
    }

    func testLeavesBeyondAViewsMaximumAreDemotedAndTheOthersKept() {
        let stored = LayoutNode.split(
            orientation: .horizontal,
            first: LayoutNode.leaf(contentType: editor),
            second: LayoutNode.leaf(contentType: editor)
        )
        let spec = ComposableTabLayoutSpec.pane(editor, allows: [.init(editor, min: 0, max: 1)])

        XCTAssertEqual(leafViewIDs(in: spec.reconcile(stored)), [editor, .placeholder])
    }

    /// Reconciliation repairs content, never shape: the user arranged the
    /// panes, so a demoted leaf stays a leaf in the same place.
    func testReconciliationKeepsTheTreeShapeAndNodeIdentities() {
        let firstID = UUID(), secondID = UUID()
        let stored = LayoutNode.split(
            orientation: .vertical,
            first: LayoutNode.leaf(id: firstID, contentType: editor),
            second: LayoutNode.leaf(id: secondID, contentType: editor)
        )
        let spec = ComposableTabLayoutSpec.pane(editor, allows: [.init(editor, min: 0, max: 1)])
        let repaired = spec.reconcile(stored)

        XCTAssertEqual(leafIDs(in: repaired), [firstID, secondID])
        guard case .split(let axis, _, _) = repaired.kind else {
            return XCTFail("the stored split must survive reconciliation")
        }
        XCTAssertEqual(axis, .vertical)
    }

    func testAConformingTreeIsReturnedUnchanged() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(terminal)],
            allows: [.init(list, min: 1, max: 1), .unbounded(terminal)]
        )
        let tree = spec.blueprint()
        XCTAssertEqual(leafIDs(in: spec.reconcile(tree)), leafIDs(in: tree))
        XCTAssertEqual(leafViewIDs(in: spec.reconcile(tree)), [list, terminal])
    }

    // MARK: - Reconciliation: a view the spec requires

    /// The repair that carries a window across a release making a pane
    /// mandatory: the pane arrives *beside* what was stored, and where the
    /// blueprint would have put it.
    func testAViewTheSpecRequiresAndTheTreeLacksIsAddedWhereTheBlueprintPutsIt() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(editor), .pane(terminal)],
            allows: [.init(list, min: 1, max: 1),
                     .init(editor, min: 1, max: 1),
                     .unbounded(terminal)]
        )
        let stored = LayoutNode.split(
            orientation: .horizontal,
            first: LayoutNode.leaf(contentType: list),
            second: LayoutNode.leaf(contentType: terminal)
        )

        XCTAssertEqual(leafViewIDs(in: spec.reconcile(stored)), [list, editor, terminal])
    }

    /// Nothing precedes it in the blueprint, so it goes to the front rather
    /// than the end — a sidebar stays a sidebar.
    func testARequiredViewTheBlueprintPutsFirstIsAddedAtTheFront() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(terminal)],
            allows: [.init(list, min: 1, max: 1), .unbounded(terminal)]
        )

        let repaired = spec.reconcile(LayoutNode.leaf(contentType: terminal))

        XCTAssertEqual(leafViewIDs(in: repaired), [list, terminal])
    }

    /// The panes the user arranged are the same panes afterwards — only the
    /// missing one is new, so nothing they had sized or scrolled is rebuilt.
    func testTheRepairKeepsTheStoredLeavesAndAddsOnlyTheMissingOne() {
        let listID = UUID(), terminalID = UUID()
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(editor), .pane(terminal)],
            allows: [.init(list, min: 1, max: 1),
                     .init(editor, min: 1, max: 1),
                     .unbounded(terminal)]
        )
        let stored = LayoutNode.split(
            orientation: .horizontal,
            first: LayoutNode.leaf(id: listID, contentType: list),
            second: LayoutNode.leaf(id: terminalID, contentType: terminal)
        )

        let ids = leafIDs(in: spec.reconcile(stored))

        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual([ids.first, ids.last], [listID, terminalID])
        XCTAssertFalse([listID, terminalID].contains(ids[1]), "the added pane is a new node")
    }

    /// A `min` on one side of a split says how many *that side* must hold, and
    /// nothing in the spec says which of the live tree's nodes below the root
    /// should be the one to gain a pane. Inventing an answer would move panes
    /// the user arranged, so the repair stays at the root.
    func testAMinimumDeclaredBelowTheRootIsNotRepaired() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [
                .pane(list),
                .split(
                    axis: .vertical,
                    children: [.pane(editor), .pane(terminal)],
                    allows: [.init(editor, min: 1, max: 1)])
            ],
            allows: [.init(list, min: 1, max: 1), .unbounded(terminal)]
        )
        let stored = LayoutNode.split(
            orientation: .horizontal,
            first: LayoutNode.leaf(contentType: list),
            second: LayoutNode.leaf(contentType: terminal)
        )

        XCTAssertEqual(leafViewIDs(in: spec.reconcile(stored)), [list, terminal])
    }

    func testAMinimumOfTwoAddsAsManyPanesAsAreMissing() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(terminal), .pane(terminal)],
            allows: [.unbounded(terminal, min: 2)]
        )

        let repaired = spec.reconcile(LayoutNode.leaf(contentType: terminal))

        XCTAssertEqual(leafViewIDs(in: repaired), [terminal, terminal])
    }

    /// The root's axis is the row the repair inserts into. A stored tree that
    /// leans the other way is one segment of that row, not two, so the added
    /// pane arrives beside the whole of it rather than inside it.
    func testATreeOnTheOtherAxisGainsTheRequiredPaneBesideItWhole() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [
                .pane(list),
                .split(axis: .vertical, children: [.pane(editor), .pane(terminal)])
            ],
            allows: [.init(list, min: 1, max: 1),
                     .init(editor, min: 0, max: 1),
                     .unbounded(terminal)]
        )
        let stored = LayoutNode.split(
            orientation: .vertical,
            first: LayoutNode.leaf(contentType: editor),
            second: LayoutNode.leaf(contentType: terminal)
        )

        let repaired = spec.reconcile(stored)

        XCTAssertEqual(leafViewIDs(in: repaired), [list, editor, terminal])
        guard case .split(let axis, _, let second) = repaired.kind else {
            return XCTFail("the repair rebuilds the row along the root's axis")
        }
        XCTAssertEqual(axis, .horizontal)
        guard case .split(let storedAxis, _, _) = second.kind else {
            return XCTFail("the stored split survives whole, as one segment of that row")
        }
        XCTAssertEqual(storedAxis, .vertical)
    }

    /// Reconciliation runs on every load, including the load after the one that
    /// repaired the tree — so a second pass must add nothing.
    func testASecondReconciliationAddsNothingMore() {
        let spec = ComposableTabLayoutSpec.split(
            axis: .horizontal,
            children: [.pane(list), .pane(editor), .pane(terminal)],
            allows: [.init(list, min: 1, max: 1),
                     .init(editor, min: 1, max: 1),
                     .unbounded(terminal)]
        )
        let stored = LayoutNode.split(
            orientation: .horizontal,
            first: LayoutNode.leaf(contentType: list),
            second: LayoutNode.leaf(contentType: terminal)
        )

        let once = spec.reconcile(stored)

        XCTAssertEqual(leafIDs(in: spec.reconcile(once)), leafIDs(in: once))
    }

    // MARK: - Helpers

    private func leafViewIDs(in node: LayoutNode) -> [ComposableTabsViewID] {
        switch node.kind {
        case .leaf(let viewID, _):
            return [viewID]
        case .split(_, let first, let second):
            return leafViewIDs(in: first) + leafViewIDs(in: second)
        }
    }

    private func leafIDs(in node: LayoutNode) -> [UUID] {
        switch node.kind {
        case .leaf:
            return [node.id]
        case .split(_, let first, let second):
            return leafIDs(in: first) + leafIDs(in: second)
        }
    }

    private func leaf(holding viewID: ComposableTabsViewID, in node: LayoutNode) -> LayoutNode? {
        switch node.kind {
        case .leaf(let held, _):
            return held == viewID ? node : nil
        case .split(_, let first, let second):
            return leaf(holding: viewID, in: first) ?? leaf(holding: viewID, in: second)
        }
    }
}
