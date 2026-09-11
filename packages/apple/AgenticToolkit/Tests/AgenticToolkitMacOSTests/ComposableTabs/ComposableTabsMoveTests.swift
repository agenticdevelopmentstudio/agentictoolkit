import XCTest
import AgenticToolkitMacOS

/// The arrange-mode move rules, as trees rather than as pixels.
///
/// `ComposableTabsMove` answers both "which arrows are lit" and "what does this
/// arrow do", so every case here is really two assertions about the same rule —
/// an arrow that produces a tree is an arrow the overlay offers.
@MainActor
final class ComposableTabsMoveTests: XCTestCase {

    private let editor = ComposableTabsViewID("test.move.editor")

    // MARK: - Building and reading trees

    private func pane(_ label: String) -> LayoutNode {
        .leaf(contentType: editor, paneLabel: label)
    }

    /// `V(a, b)` reads top-to-bottom, `H(a, b)` left-to-right — the same order
    /// the split stores them in.
    private func shape(_ node: LayoutNode) -> String {
        switch node.kind {
        case .leaf(_, let label):
            return label ?? "?"
        case .split(let axis, let first, let second):
            return "\(axis == .horizontal ? "H" : "V")(\(shape(first)), \(shape(second)))"
        }
    }

    private func moved(
        _ node: LayoutNode,
        _ direction: ComposableTabsViewController.Direction,
        in root: LayoutNode
    ) throws -> String {
        shape(try XCTUnwrap(ComposableTabsMove.moving(node.id, direction, in: root)))
    }

    // MARK: - Up and down out of a row

    /// The rule in one line: a pane with anything beside it can always travel
    /// above or below it. Before, `up` and `down` were offered only to a pane
    /// that already had a neighbour stacked with it, so a plain side-by-side
    /// pair had no way to become a stack without going through a third pane.
    func testAPaneWithSomethingBesideItCanAlwaysGoUpAndDown() {
        let left = pane("A")
        let root = LayoutNode.split(orientation: .horizontal, first: left, second: pane("B"))

        let available = ComposableTabsMove.availableDirections(for: left.id, in: root)

        XCTAssertTrue(available.isSuperset(of: [.above, .below]),
                      "a pane in a row has an up and a down: out of the row, over or under it")
        XCTAssertTrue(available.contains(.right), "and the neighbour it can still step across")
        XCTAssertFalse(available.contains(.left), "but nothing to its left to step into")
    }

    func testGoingUpLiftsThePaneAboveTheRowItWasIn() throws {
        let left = pane("A")
        let root = LayoutNode.split(orientation: .horizontal, first: left, second: pane("B"))

        XCTAssertEqual(try moved(left, .above, in: root), "V(A, B)")
        XCTAssertEqual(try moved(left, .below, in: root), "V(B, A)")
    }

    /// The same lift from inside a column: the pane leaves the whole row it was
    /// nested in, and what it leaves behind closes up.
    func testGoingUpFromInsideAColumnClearsEverythingBesideIt() throws {
        let stacked = pane("A")
        let root = LayoutNode.split(
            orientation: .horizontal,
            first: .split(orientation: .vertical, first: stacked, second: pane("B")),
            second: pane("C")
        )

        XCTAssertEqual(try moved(stacked, .above, in: root), "V(A, H(B, C))")
    }

    /// The mirror of the rule that was already there for `left`/`right`, and the
    /// reason it is phrased as "across the direction" rather than per-axis: a
    /// pane stacked in a column keeps its sideways moves.
    func testAPaneInAColumnStillHasALeftAndARight() throws {
        let bottom = pane("B")
        let root = LayoutNode.split(orientation: .vertical, first: pane("A"), second: bottom)

        XCTAssertEqual(try moved(bottom, .left, in: root), "H(B, A)")
        XCTAssertEqual(try moved(bottom, .right, in: root), "H(A, B)")
    }

    // MARK: - Expanding into the band above or below

    /// The rule in its simplest shape: the pane grows into the band above it,
    /// and what was there moves to the right. Up used to swap the two, which
    /// left the pane exactly the size it started.
    func testGoingUpExpandsIntoTheBandAboveAndPushesItsOccupantRight() throws {
        let bottom = pane("B")
        let root = LayoutNode.split(orientation: .vertical, first: pane("A"), second: bottom)

        XCTAssertEqual(try moved(bottom, .above, in: root), "H(B, A)")
    }

    func testGoingDownExpandsTheSameWay() throws {
        let top = pane("A")
        let root = LayoutNode.split(orientation: .vertical, first: top, second: pane("B"))

        XCTAssertEqual(try moved(top, .below, in: root), "H(A, B)")
    }

    /// Where "expand" earns the name: B keeps its own half of the bottom row
    /// *and* takes the band above, so it spans the full height of the left
    /// column. A was wider than B, so A is what reduces in width; C was already
    /// B's width, so C only moves to the right.
    func testExpandingUpwardSpansBothBandsAndNarrowsTheWiderPane() throws {
        let mover = pane("B")
        let root = LayoutNode.split(
            orientation: .vertical,
            first: pane("A"),
            second: .split(orientation: .horizontal, first: mover, second: pane("C"))
        )

        XCTAssertEqual(try moved(mover, .above, in: root), "H(B, V(A, C))")
    }

    /// And downward, where the two displaced panes keep the order they were
    /// already stacked in rather than being reshuffled by the move.
    func testExpandingDownwardKeepsTheDisplacedPanesInTheirOriginalOrder() throws {
        let mover = pane("B")
        let root = LayoutNode.split(
            orientation: .vertical,
            first: .split(orientation: .horizontal, first: mover, second: pane("C")),
            second: pane("A")
        )

        XCTAssertEqual(try moved(mover, .below, in: root), "H(B, V(C, A))")
    }

    /// One band, not all the way to the top: the pane expands into the band
    /// immediately above it and the rest of the column is left alone.
    func testExpandingUpwardTakesOneBandRatherThanTheWholeColumn() throws {
        let bottom = pane("C")
        let root = LayoutNode.split(
            orientation: .vertical,
            first: pane("A"),
            second: .split(orientation: .vertical, first: pane("B"), second: bottom)
        )

        XCTAssertEqual(try moved(bottom, .above, in: root), "V(A, H(C, B))")
    }

    func testTheOnlyPaneInATabHasNowhereToGo() {
        let only = pane("A")

        XCTAssertTrue(ComposableTabsMove.availableDirections(for: only.id, in: only).isEmpty)
    }
}
