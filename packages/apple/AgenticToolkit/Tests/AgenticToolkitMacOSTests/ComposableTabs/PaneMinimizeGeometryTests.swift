import Foundation
import XCTest
@testable import AgenticToolkitMacOS

/// The rules that fall out of a binary layout tree: which way a pane may
/// shrink, and which side it docks to when it does.
final class PaneMinimizeGeometryTests: XCTestCase {

    private let leftID = UUID()
    private let rightID = UUID()
    private let topID = UUID()
    private let bottomID = UUID()
    private let rootID = UUID()

    /// `left | right` — a side-by-side split.
    private func sideBySide() -> LayoutNode {
        .split(
            id: rootID,
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: .placeholder),
            second: .leaf(id: rightID, contentType: .placeholder)
        )
    }

    /// `top` over `bottom` — a stacked split.
    private func stacked() -> LayoutNode {
        .split(
            id: rootID,
            orientation: .vertical,
            first: .leaf(id: topID, contentType: .placeholder),
            second: .leaf(id: bottomID, contentType: .placeholder)
        )
    }

    /// A stacked pair in the trailing slot of a side-by-side split — the shape
    /// that proves the *nearest* split decides, not the root.
    private func nested() -> LayoutNode {
        .split(
            id: rootID,
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: .placeholder),
            second: .split(
                orientation: .vertical,
                first: .leaf(id: topID, contentType: .placeholder),
                second: .leaf(id: bottomID, contentType: .placeholder)
            )
        )
    }

    // MARK: - parentSplit

    func testParentSplitOfARootLeafIsNil() {
        let root = LayoutNode.leaf(id: leftID, contentType: .placeholder)
        XCTAssertNil(PaneMinimizeGeometry.parentSplit(of: leftID, in: root))
    }

    func testParentSplitReportsAxisAndSlot() {
        let root = sideBySide()
        let left = PaneMinimizeGeometry.parentSplit(of: leftID, in: root)
        XCTAssertEqual(left?.axis, .horizontal)
        XCTAssertEqual(left?.isFirst, true)

        let right = PaneMinimizeGeometry.parentSplit(of: rightID, in: root)
        XCTAssertEqual(right?.axis, .horizontal)
        XCTAssertEqual(right?.isFirst, false)
    }

    func testParentSplitIsTheNearestSplitNotTheRoot() {
        let root = nested()
        let top = PaneMinimizeGeometry.parentSplit(of: topID, in: root)
        XCTAssertEqual(top?.axis, .vertical, "the enclosing stacked split decides, not the root's horizontal one")
        XCTAssertEqual(top?.isFirst, true)
    }

    func testParentSplitOfAnIDNotInTheTreeIsNil() {
        XCTAssertNil(PaneMinimizeGeometry.parentSplit(of: UUID(), in: sideBySide()))
    }

    // MARK: - availableEdges

    func testARootLeafOffersNoEdges() {
        let root = LayoutNode.leaf(id: leftID, contentType: .placeholder)
        XCTAssertEqual(PaneMinimizeGeometry.availableEdges(forNode: leftID, in: root), [])
    }

    func testSideBySideOffersTheHorizontalPairToBothChildren() {
        let root = sideBySide()
        XCTAssertEqual(PaneMinimizeGeometry.availableEdges(forNode: leftID, in: root), [.leading, .trailing])
        XCTAssertEqual(PaneMinimizeGeometry.availableEdges(forNode: rightID, in: root), [.leading, .trailing])
    }

    func testStackedOffersTheVerticalPairToBothChildren() {
        let root = stacked()
        XCTAssertEqual(PaneMinimizeGeometry.availableEdges(forNode: topID, in: root), [.top, .bottom])
        XCTAssertEqual(PaneMinimizeGeometry.availableEdges(forNode: bottomID, in: root), [.top, .bottom])
    }

    // MARK: - resolvedEdge

    func testTheSlotPicksTheSideNotTheArrow() {
        let root = sideBySide()
        // The pane in the leading slot docks leading whichever arrow is clicked.
        XCTAssertEqual(PaneMinimizeGeometry.resolvedEdge(forNode: leftID, in: root, requested: .leading), .leading)
        XCTAssertEqual(PaneMinimizeGeometry.resolvedEdge(forNode: leftID, in: root, requested: .trailing), .leading)
        // And the pane in the trailing slot docks trailing.
        XCTAssertEqual(PaneMinimizeGeometry.resolvedEdge(forNode: rightID, in: root, requested: .leading), .trailing)
        XCTAssertEqual(PaneMinimizeGeometry.resolvedEdge(forNode: rightID, in: root, requested: .trailing), .trailing)
    }

    func testStackedResolvesToTopAndBottom() {
        let root = stacked()
        XCTAssertEqual(PaneMinimizeGeometry.resolvedEdge(forNode: topID, in: root, requested: .bottom), .top)
        XCTAssertEqual(PaneMinimizeGeometry.resolvedEdge(forNode: bottomID, in: root, requested: .top), .bottom)
    }

    func testAnEdgeOffTheLiveAxisResolvesToNil() {
        let root = sideBySide()
        XCTAssertNil(PaneMinimizeGeometry.resolvedEdge(forNode: leftID, in: root, requested: .top))
        XCTAssertNil(PaneMinimizeGeometry.resolvedEdge(forNode: leftID, in: root, requested: .bottom))
    }

    func testARootLeafResolvesToNilForEveryEdge() {
        let root = LayoutNode.leaf(id: leftID, contentType: .placeholder)
        for edge in PaneEdge.allCases {
            XCTAssertNil(PaneMinimizeGeometry.resolvedEdge(forNode: leftID, in: root, requested: edge))
        }
    }

    /// The invariant tying the two functions together: whatever
    /// `availableEdges` offers, `resolvedEdge` answers — never `nil`.
    func testEveryOfferedEdgeResolves() {
        for root in [sideBySide(), stacked(), nested()] {
            for id in [leftID, rightID, topID, bottomID] {
                for edge in PaneMinimizeGeometry.availableEdges(forNode: id, in: root) {
                    XCTAssertNotNil(
                        PaneMinimizeGeometry.resolvedEdge(forNode: id, in: root, requested: edge),
                        "offered \(edge) for \(id) but could not resolve it"
                    )
                }
            }
        }
    }
}
