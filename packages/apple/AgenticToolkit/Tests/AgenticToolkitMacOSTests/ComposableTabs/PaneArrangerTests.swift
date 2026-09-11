import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class PaneArrangerTests: XCTestCase {

    private func leaf() -> LayoutNode { .leaf(contentType: .placeholder) }

    func testInheritedSlotArrangerChangesNothing() {
        let tree = LayoutNode.split(
            orientation: .horizontal,
            first: leaf(),
            second: LayoutNode.split(orientation: .horizontal, first: leaf(), second: leaf())
        )

        let arranged = InheritedSlotArranger().arrange(tree, along: .horizontal)

        XCTAssertNil(arranged.thicknessFraction)
        guard case .split(_, let first, let second) = arranged.kind else { return XCTFail("expected a split") }
        XCTAssertNil(first.thicknessFraction)
        XCTAssertNil(second.thicknessFraction)
    }

    func testProportionalArrangerGivesThreePanesEqualThirds() throws {
        let tree = LayoutNode.split(
            orientation: .horizontal,
            first: leaf(),
            second: LayoutNode.split(orientation: .horizontal, first: leaf(), second: leaf())
        )

        let arranged = ProportionalArranger().arrange(tree, along: .horizontal)

        guard case .split(_, let first, let second) = arranged.kind else { return XCTFail("expected a split") }
        XCTAssertEqual(try XCTUnwrap(first.thicknessFraction), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(second.thicknessFraction), 2.0 / 3.0, accuracy: 0.0001)

        guard case .split(_, let paneB, let paneC) = second.kind else { return XCTFail("expected a nested split") }
        XCTAssertEqual(try XCTUnwrap(paneB.thicknessFraction), 0.5, accuracy: 0.0001,
                       "half of the two-thirds it was given is one third of the whole")
        XCTAssertEqual(try XCTUnwrap(paneC.thicknessFraction), 0.5, accuracy: 0.0001)
    }

    func testProportionalArrangerGivesTwoPanesHalves() throws {
        let tree = LayoutNode.split(orientation: .horizontal, first: leaf(), second: leaf())

        let arranged = ProportionalArranger().arrange(tree, along: .horizontal)

        guard case .split(_, let first, let second) = arranged.kind else { return XCTFail("expected a split") }
        XCTAssertEqual(try XCTUnwrap(first.thicknessFraction), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(second.thicknessFraction), 0.5, accuracy: 0.0001)
    }

    func testASingleLeafIsLeftAlone() {
        let arranged = ProportionalArranger().arrange(leaf(), along: .horizontal)
        XCTAssertNil(arranged.thicknessFraction, "one pane fills its tab; there is nothing to divide")
    }

    func testNodeIdentitiesSurviveArrangement() throws {
        let paneA = LayoutNode.leaf(contentType: .placeholder)
        let paneB = LayoutNode.leaf(contentType: .placeholder)
        let tree = LayoutNode.split(orientation: .horizontal, first: paneA, second: paneB)

        let arranged = ProportionalArranger().arrange(tree, along: .horizontal)

        guard case .split(_, let first, let second) = arranged.kind else { return XCTFail("expected a split") }
        XCTAssertEqual(first.id, paneA.id, "the live pane is matched back by id, so ids must not be reminted")
        XCTAssertEqual(second.id, paneB.id)
    }

    func testASplitOnTheOtherAxisIsNotRedistributed() throws {
        let tree = LayoutNode.split(orientation: .vertical, first: leaf(), second: leaf())

        let arranged = ProportionalArranger().arrange(tree, along: .horizontal)

        guard case .split(_, let first, _) = arranged.kind else { return XCTFail("expected a split") }
        XCTAssertNil(first.thicknessFraction, "only the arrangement axis is this arranger's business")
    }
}
