import XCTest
import AgenticToolkitMacOS

/// One arrangement, worn by every tab in the project — each in its own ids.
///
/// The shape is the project's and travels between tabs; the ids are the tab's
/// and never leave it. `layout_nodes.id` is a primary key, so two tabs holding
/// one id cannot both be saved, and a pane is reused across a rebuild by its
/// node id, so a tab handed another tab's ids throws away every live pane it
/// had.
@MainActor
final class LayoutNodeReshapeTests: XCTestCase {

    private let editor = ComposableTabsViewID("test.reshape.editor")
    private let terminal = ComposableTabsViewID("test.reshape.terminal")
    private let browser = ComposableTabsViewID("test.reshape.browser")

    /// Every id in a tree, in reading order.
    private func ids(of node: LayoutNode) -> [UUID] {
        switch node.kind {
        case .split(_, let first, let second):
            return [node.id] + ids(of: first) + ids(of: second)
        case .leaf:
            return [node.id]
        }
    }

    /// What a tree *is*, with the ids left out — the half that is shared.
    private func shape(of node: LayoutNode) -> String {
        switch node.kind {
        case .split(let orientation, let first, let second):
            return "(\(orientation) \(shape(of: first)) \(shape(of: second)))"
        case .leaf(let contentType, let paneLabel):
            return "\(contentType.rawValue)[\(paneLabel ?? "")]"
        }
    }

    func testATabTakesTheArrangementsShape() {
        let tab = LayoutNode.leaf(contentType: editor)
        let template = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: browser),
            second: .leaf(contentType: editor)
        )

        XCTAssertEqual(shape(of: tab.reshaped(toMatch: template)), shape(of: template))
    }

    func testATabKeepsItsOwnIDs() {
        let tab = LayoutNode.split(
            orientation: .vertical,
            first: .leaf(contentType: editor),
            second: .leaf(contentType: terminal)
        )
        let template = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: terminal),
            second: .leaf(contentType: editor)
        )

        let reshaped = tab.reshaped(toMatch: template)
        XCTAssertEqual(Set(ids(of: reshaped)), Set(ids(of: tab)))
        XCTAssertTrue(Set(ids(of: reshaped)).isDisjoint(with: Set(ids(of: template))))
    }

    /// The mirror runs on every tab whenever any one of them changes, so the
    /// overwhelmingly common case is a tab that already matches. It has to be
    /// a no-op, or every pane in every other tab is rebuilt each time the user
    /// drags a divider.
    func testATabAlreadyInThatShapeIsLeftExactlyAsItWas() {
        let tab = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: browser, thicknessFraction: 0.25),
            second: .split(
                orientation: .vertical,
                first: .leaf(contentType: editor),
                second: .leaf(contentType: terminal),
                thicknessFraction: 0.75
            )
        )

        let reshaped = tab.reshaped(toMatch: tab)
        XCTAssertEqual(ids(of: reshaped), ids(of: tab))
        XCTAssertEqual(shape(of: reshaped), shape(of: tab))
    }

    /// A pane that moved is still that pane: it is recognised by what it
    /// shows, so it keeps its id and with it everything the pane remembered.
    func testAPaneThatMovedKeepsItsID() {
        let movedTerminal = UUID()
        let tab = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor),
            second: .leaf(id: movedTerminal, contentType: terminal)
        )
        let template = LayoutNode.split(
            orientation: .vertical,
            first: .leaf(contentType: terminal),
            second: .leaf(contentType: editor)
        )

        let reshaped = tab.reshaped(toMatch: template)
        guard case .split(_, let first, _) = reshaped.kind else { return XCTFail("expected a split") }
        XCTAssertEqual(first.id, movedTerminal)
    }

    /// Two panes showing the same thing are told apart by where they stand, so
    /// a tab holding two terminals does not shuffle them on every mirror.
    func testTwoPanesShowingTheSameThingKeepTheirOwnPlaces() {
        let upper = UUID()
        let lower = UUID()
        let tab = LayoutNode.split(
            orientation: .vertical,
            first: .leaf(id: upper, contentType: terminal),
            second: .leaf(id: lower, contentType: terminal)
        )

        let reshaped = tab.reshaped(toMatch: tab)
        guard case .split(_, let first, let second) = reshaped.kind else { return XCTFail("expected a split") }
        XCTAssertEqual(first.id, upper)
        XCTAssertEqual(second.id, lower)
    }

    /// The arrangement may hold more panes than the tab being dressed in it.
    /// A node with no id is not a node, so the extras are minted — and minted
    /// distinct, or the save that follows collides with itself.
    func testAnArrangementWithMorePanesThanTheTabHasMintsTheRest() {
        let tab = LayoutNode.leaf(contentType: editor)
        let template = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor),
            second: .split(
                orientation: .vertical,
                first: .leaf(contentType: terminal),
                second: .leaf(contentType: terminal)
            )
        )

        let reshaped = tab.reshaped(toMatch: template)
        let reshapedIDs = ids(of: reshaped)
        XCTAssertEqual(reshapedIDs.count, 5)
        XCTAssertEqual(Set(reshapedIDs).count, 5)
        XCTAssertTrue(Set(reshapedIDs).isDisjoint(with: Set(ids(of: template))))
    }

    // MARK: - A tab that does not exist yet

    /// A tab being made has no ids to keep, so it gets the arrangement in
    /// ones nobody is using.
    func testAFreshCopyWearsTheShapeInIDsNobodyHolds() {
        let arrangement = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: browser, thicknessFraction: 0.3),
            second: .leaf(contentType: editor, thicknessFraction: 0.7)
        )

        let copy = arrangement.inFreshIDs()
        XCTAssertEqual(shape(of: copy), shape(of: arrangement))
        XCTAssertTrue(Set(ids(of: copy)).isDisjoint(with: Set(ids(of: arrangement))))
        XCTAssertEqual(Set(ids(of: copy)).count, ids(of: copy).count)
    }

    /// Two tabs opened from one arrangement must not collide: `layout_nodes.id`
    /// is a primary key, and the second insert would take the whole save down.
    func testTwoFreshCopiesShareNoIDs() {
        let arrangement = LayoutNode.split(
            orientation: .vertical,
            first: .leaf(contentType: editor),
            second: .leaf(contentType: terminal)
        )

        XCTAssertTrue(
            Set(ids(of: arrangement.inFreshIDs())).isDisjoint(with: Set(ids(of: arrangement.inFreshIDs())))
        )
    }

    // MARK: - Telling a resize from a rearrangement

    /// What decides whether a following tab can take the change where it
    /// stands or has to be rebuilt around it.
    func testSizesAloneAreNotAStructuralDifference() {
        let tab = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor, thicknessFraction: 0.5),
            second: .leaf(contentType: terminal, thicknessFraction: 0.5)
        )
        let resized = tab.reshaped(toMatch: LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor, thicknessFraction: 0.1),
            second: .leaf(contentType: terminal, thicknessFraction: 0.9)
        ))

        XCTAssertTrue(tab.hasSameStructure(as: resized))
    }

    func testAMovedPaneIsAStructuralDifference() {
        let tab = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor),
            second: .leaf(contentType: terminal)
        )
        let swapped = tab.reshaped(toMatch: LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: terminal),
            second: .leaf(contentType: editor)
        ))

        XCTAssertFalse(tab.hasSameStructure(as: swapped))
    }

    /// Two trees of the same shape in different ids are different panes, and a
    /// tab told to wear another tab's ids loses everything it was showing.
    func testTheSameShapeInOtherIDsIsADifference() {
        let arrangement = LayoutNode.split(
            orientation: .vertical,
            first: .leaf(contentType: editor),
            second: .leaf(contentType: terminal)
        )

        XCTAssertFalse(arrangement.hasSameStructure(as: arrangement.inFreshIDs()))
    }

    /// The sizes are part of the arrangement: a divider dragged in one tab is
    /// that divider dragged in all of them.
    func testTheArrangementsSizesTravelWithItsShape() {
        let tab = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor, thicknessFraction: 0.5),
            second: .leaf(contentType: terminal, thicknessFraction: 0.5)
        )
        let template = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor, thicknessFraction: 0.2),
            second: .leaf(contentType: terminal, thicknessFraction: 0.8)
        )

        let reshaped = tab.reshaped(toMatch: template)
        guard case .split(_, let first, let second) = reshaped.kind else { return XCTFail("expected a split") }
        XCTAssertEqual(first.thicknessFraction, 0.2)
        XCTAssertEqual(second.thicknessFraction, 0.8)
    }
}
