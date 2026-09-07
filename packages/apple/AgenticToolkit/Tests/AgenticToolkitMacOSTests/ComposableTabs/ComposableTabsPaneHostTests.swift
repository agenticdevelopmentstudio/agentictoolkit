import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// What a split view does when a pane asks it for something.
@MainActor
final class ComposableTabsPaneHostTests: XCTestCase {

    private let alpha = ComposableTabsViewID("test.alpha")
    private let beta = ComposableTabsViewID("test.beta")

    private let leftID = UUID()
    private let rightID = UUID()
    private let topID = UUID()
    private let bottomID = UUID()

    private lazy var project = Self.makeWorkspace()

    @MainActor
    private static func makeWorkspace() -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaneHostTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        // A failure here is a broken test environment, not a case to handle.
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        return ProjectWorkspace(
            repo: GitRepo(path: NSTemporaryDirectory(), name: "Test"),
            database: database
        )
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    /// Two unbounded view types, so nothing in these tests is refused by the
    /// spec — removal rules are `ComposableTabsViewControllerTests`' subject,
    /// not this suite's.
    private func installLayout() throws {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { _ in
            NSViewController()
        }
        registry.register(beta, descriptor: .init(displayName: "Beta", minimumThickness: 150)) { _ in
            NSViewController()
        }
        ComposableTabsLayout.install(try ComposableTabsLayout(
            registry: registry,
            spec: .split(
                axis: .horizontal,
                children: [.pane(alpha), .pane(beta)],
                allows: [.unbounded(alpha), .unbounded(beta)]
            )
        ))
    }

    /// A root split holding `first` beside `second`, fully loaded — a split
    /// item does not exist until the view does.
    private func makeTree(_ node: LayoutNode) throws -> ComposableTabsViewController {
        try installLayout()
        let root = ComposableTabsViewController.make(from: node, project: project, isRoot: true)
        root.loadViewIfNeeded()
        for leaf in root.allLeaves() { leaf.loadViewIfNeeded() }
        return root
    }

    private func sideBySide() throws -> ComposableTabsViewController {
        try makeTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .leaf(id: rightID, contentType: beta)
        ))
    }

    private func stacked() throws -> ComposableTabsViewController {
        try makeTree(.split(
            orientation: .vertical,
            first: .leaf(id: topID, contentType: alpha),
            second: .leaf(id: bottomID, contentType: beta)
        ))
    }

    private func leaf(_ id: UUID, in root: ComposableTabsViewController)
        throws -> ComposableTabsPaneViewController {
        try XCTUnwrap(root.allLeaves().first { $0.nodeID == id })
    }

    private func item(for pane: ComposableTabsPaneViewController) throws -> NSSplitViewItem {
        let owner = try XCTUnwrap(pane.parent as? ComposableTabsViewController)
        return try XCTUnwrap(owner.splitViewItem(for: pane))
    }

    // MARK: - Wiring

    func testASplitMakesItselfTheHostOfEveryLeafItShows() throws {
        let root = try sideBySide()
        for pane in root.allLeaves() {
            XCTAssertTrue(pane.host === root, "the split that built the item is the host")
        }
    }

    // MARK: - Close

    func testCloseRemovesThePaneFromTheTree() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)

        root.paneDidRequestClose(left)

        XCTAssertEqual(root.allLeaves().map(\.nodeID), [rightID])
    }

    /// The host is free to refuse. A tab reduced to one pane has nothing to
    /// give the space to, and `remove` already says so.
    func testCloseIsRefusedForTheLastPaneInATab() throws {
        let onlyID = UUID()
        let root = try makeTree(.leaf(id: onlyID, contentType: alpha))
        let only = try leaf(onlyID, in: root)

        root.paneDidRequestClose(only)

        XCTAssertEqual(root.allLeaves().map(\.nodeID), [onlyID])
    }

    // MARK: - Which edges are offered

    func testASideBySidePaneIsOfferedTheHorizontalEdges() throws {
        let root = try sideBySide()
        XCTAssertEqual(root.availableMinimizeEdges(for: try leaf(leftID, in: root)),
                       [.leading, .trailing])
    }

    func testAStackedPaneIsOfferedTheVerticalEdges() throws {
        let root = try stacked()
        XCTAssertEqual(root.availableMinimizeEdges(for: try leaf(topID, in: root)),
                       [.top, .bottom])
    }

    func testASoloPaneIsOfferedNothing() throws {
        let onlyID = UUID()
        let root = try makeTree(.leaf(id: onlyID, contentType: alpha))
        XCTAssertEqual(root.availableMinimizeEdges(for: try leaf(onlyID, in: root)), [])
    }

    // MARK: - Minimizing

    func testMinimizingPinsTheItemToTheStripWidth() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)

        root.paneDidRequestMinimize(left, to: .leading)

        let pinned = try item(for: left)
        XCTAssertEqual(pinned.minimumThickness, left.minimizedThickness(for: .leading))
        XCTAssertEqual(pinned.maximumThickness, left.minimizedThickness(for: .leading))
        XCTAssertEqual(pinned.holdingPriority, .defaultHigh)
    }

    /// The arrow picks the axis; the tree picks the side. Both horizontal
    /// arrows land a left-hand pane on its leading edge.
    func testTheTreeDecidesWhichSideThePaneDocksTo() throws {
        let root = try sideBySide()
        let right = try leaf(rightID, in: root)

        root.paneDidRequestMinimize(right, to: .leading)

        XCTAssertEqual(right.minimizedEdge, .trailing)
    }

    func testMinimizingAcrossTheWrongAxisIsIgnored() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)

        root.paneDidRequestMinimize(left, to: .top)

        XCTAssertNil(left.minimizedEdge)
        XCTAssertEqual(try item(for: left).maximumThickness,
                       NSSplitViewItem.unspecifiedDimension)
    }

    func testAStackedPaneMinimizesToTheTitleBarHeight() throws {
        let root = try stacked()
        let top = try leaf(topID, in: root)

        root.paneDidRequestMinimize(top, to: .top)

        XCTAssertEqual(try item(for: top).minimumThickness, top.minimizedThickness(for: .top))
        XCTAssertLessThan(top.minimizedThickness(for: .top), top.minimizedThickness(for: .leading))
    }

    // MARK: - Restoring

    func testRestoringPutsTheRegistrysSizingBack() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestMinimize(left, to: .leading)

        root.paneDidRequestRestore(left)

        let restored = try item(for: left)
        XCTAssertNil(left.minimizedEdge)
        XCTAssertEqual(restored.minimumThickness, 150, "the descriptor's minimum, not the strip's")
        XCTAssertEqual(restored.maximumThickness, NSSplitViewItem.unspecifiedDimension)
        XCTAssertEqual(restored.holdingPriority, .defaultLow)
    }

    // MARK: - Zooming

    func testZoomingCollapsesTheSibling() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)

        root.paneDidRequestZoom(left)

        XCTAssertTrue(left.isZoomed)
        XCTAssertFalse(try item(for: left).isCollapsed)
        XCTAssertTrue(try item(for: try leaf(rightID, in: root)).isCollapsed)
    }

    func testZoomingAgainRestoresEveryPane() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestZoom(left)

        root.paneDidRequestZoom(left)

        XCTAssertFalse(left.isZoomed)
        XCTAssertNil(root.zoomedLeaf)
        XCTAssertFalse(try item(for: try leaf(rightID, in: root)).isCollapsed)
    }

    func testZoomingASecondPaneMovesTheZoom() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        let right = try leaf(rightID, in: root)
        root.paneDidRequestZoom(left)

        root.paneDidRequestZoom(right)

        XCTAssertFalse(left.isZoomed)
        XCTAssertTrue(right.isZoomed)
        XCTAssertTrue(try item(for: left).isCollapsed)
        XCTAssertFalse(try item(for: right).isCollapsed)
    }

    /// A zoom in a nested tree has to collapse the *ancestor* chain too, or the
    /// pane only takes over the half of the tab it happens to live in.
    func testZoomingCollapsesEverythingOffThePathToTheRoot() throws {
        let root = try makeTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .split(
                orientation: .vertical,
                first: .leaf(id: topID, contentType: beta),
                second: .leaf(id: bottomID, contentType: alpha)
            )
        ))
        let top = try leaf(topID, in: root)

        root.paneDidRequestZoom(top)

        XCTAssertTrue(try item(for: try leaf(leftID, in: root)).isCollapsed,
                      "the other half of the tab")
        XCTAssertTrue(try item(for: try leaf(bottomID, in: root)).isCollapsed,
                      "the sibling inside the nested split")
        XCTAssertFalse(try item(for: top).isCollapsed)
    }

    func testAZoomIsInvisibleToTheSavedLayout() throws {
        let root = try sideBySide()
        let before = root.snapshotNode()
        root.paneDidRequestZoom(try leaf(leftID, in: root))

        XCTAssertEqual(describe(root.snapshotNode()), describe(before),
                       "collapsing changed the screen, not the tree")
    }

    /// A stable rendering of a tree, so two snapshots can be compared without
    /// `LayoutNode` having to be `Equatable`.
    private func describe(_ node: LayoutNode) -> String {
        switch node.kind {
        case .leaf(let contentType, _):
            return "\(node.id):\(contentType.rawValue)"
        case .split(let orientation, let first, let second):
            return "\(node.id):\(orientation.rawValue)(\(describe(first)),\(describe(second)))"
        }
    }

    // MARK: - The two states are exclusive

    func testZoomingAMinimizedPaneRestoresItFirst() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestMinimize(left, to: .leading)

        root.paneDidRequestZoom(left)

        XCTAssertNil(left.minimizedEdge)
        XCTAssertTrue(left.isZoomed)
        XCTAssertEqual(try item(for: left).maximumThickness,
                       NSSplitViewItem.unspecifiedDimension)
    }

    func testMinimizingWhileZoomedUnzoomsFirst() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        let right = try leaf(rightID, in: root)
        root.paneDidRequestZoom(right)

        root.paneDidRequestMinimize(left, to: .leading)

        XCTAssertFalse(right.isZoomed)
        XCTAssertNil(root.zoomedLeaf)
        XCTAssertEqual(left.minimizedEdge, .leading)
        XCTAssertFalse(try item(for: right).isCollapsed)
    }

    func testClosingTheZoomedPaneClearsTheZoom() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestZoom(left)

        root.paneDidRequestClose(left)

        XCTAssertNil(root.zoomedLeaf)
        XCTAssertFalse(try item(for: try leaf(rightID, in: root)).isCollapsed)
    }

    // MARK: - Re-applying what was persisted

    func testTheHostAppliesAPersistedMinimizeToTheTree() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        left.stateStore.setPaneStateValue(PaneEdge.leading.rawValue,
                                          forKey: PaneStateKey.minimizeEdge)

        root.applyPersistedPaneState()

        XCTAssertEqual(left.minimizedEdge, .leading)
        XCTAssertEqual(try item(for: left).maximumThickness,
                       left.minimizedThickness(for: .leading))
    }

    func testTheHostAppliesAPersistedZoomToTheTree() throws {
        let root = try sideBySide()
        let right = try leaf(rightID, in: root)
        right.stateStore.setPaneStateValue("1", forKey: PaneStateKey.zoomed)

        root.applyPersistedPaneState()

        XCTAssertTrue(right.isZoomed)
        XCTAssertTrue(try item(for: try leaf(leftID, in: root)).isCollapsed)
    }
}
