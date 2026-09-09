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

    /// The repository is registered because a pane's store is the project's
    /// now: `pane_state.repo_id` references `git_repo(id)` under
    /// `PRAGMA foreign_keys=ON`, so a project the database has never heard of
    /// silently drops everything a pane remembers about itself.
    @MainActor
    private static func makeWorkspace() -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaneHostTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        let repo = GitRepo(path: NSTemporaryDirectory(), name: "Test")
        // A failure here is a broken test environment, not a case to handle.
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        // swiftlint:disable:next force_try
        try! database.insert(repo)
        return ProjectWorkspace(repo: repo, database: database)
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    /// Two unbounded view types, so nothing in these tests is refused by the
    /// spec — removal rules are `ComposableTabsViewControllerTests`' subject,
    /// not this suite's.
    private func installLayout(preferredFraction: CGFloat? = nil) throws {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(
            displayName: "Alpha",
            minimumThickness: 150,
            preferredThicknessFraction: preferredFraction
        )) { _ in
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
    private func makeTree(_ node: LayoutNode, preferredFraction: CGFloat? = nil)
        throws -> ComposableTabsViewController {
        try installLayout(preferredFraction: preferredFraction)
        let root = ComposableTabsViewController.make(from: node, project: project, isRoot: true)
        root.loadViewIfNeeded()
        for leaf in root.allLeaves() { leaf.loadViewIfNeeded() }
        return root
    }

    private func sideBySide(preferredFraction: CGFloat? = nil)
        throws -> ComposableTabsViewController {
        try makeTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .leaf(id: rightID, contentType: beta)
        ), preferredFraction: preferredFraction)
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

    /// The concrete numbers rather than `minimizedThickness(for:)` read back at
    /// itself: 28pt of strip plus the 2pt border on each side is what has to be
    /// left showing, and comparing the constant to itself would pass whatever
    /// it became.
    func testMinimizingPinsTheItemToTheStripWidth() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)

        root.paneDidRequestMinimize(left, to: .leading)

        let pinned = try item(for: left)
        XCTAssertEqual(pinned.minimumThickness, 32, "28pt strip + 2pt border either side")
        XCTAssertEqual(pinned.maximumThickness, 32)
        XCTAssertEqual(pinned.holdingPriority, .defaultHigh)
    }

    /// Minimize has to be non-destructive: `preferredThicknessFraction` is the
    /// share of the tab the pane gets back when it is restored, so pinning must
    /// leave it exactly as the registry set it.
    func testMinimizingLeavesThePreferredThicknessFractionAlone() throws {
        let root = try sideBySide(preferredFraction: 0.3)
        let left = try leaf(leftID, in: root)
        XCTAssertEqual(try item(for: left).preferredThicknessFraction, 0.3, accuracy: 0.0001,
                       "the descriptor's share, before anything has happened to it")

        root.paneDidRequestMinimize(left, to: .leading)

        XCTAssertEqual(try item(for: left).preferredThicknessFraction, 0.3, accuracy: 0.0001,
                       "pinning must not overwrite what restore gives back")

        root.paneDidRequestRestore(left)

        XCTAssertEqual(try item(for: left).preferredThicknessFraction, 0.3, accuracy: 0.0001,
                       "and it is still there to be given back")
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

        XCTAssertEqual(try item(for: top).minimumThickness, 30, "26pt title bar + 2pt border either side")
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

    /// The brief's central promise: a layout saved while zoomed restores
    /// unzoomed *and correct*. That is not a claim about the tree's shape —
    /// which a collapse never touches — but about the sizes travelling with it,
    /// so the tree is laid out for real and the capture is driven the way
    /// `splitViewDidResizeSubviews` drives it.
    func testAZoomIsInvisibleToTheSavedLayout() throws {
        let root = try sideBySide()
        layOut(root)
        root.captureThicknessFractions()
        let before = root.snapshotNode()
        // Without this the assertion below could pass on two rows of "-" and
        // prove nothing — which is exactly how the first version of this test
        // missed a zoom writing 1.0 into the saved layout.
        XCTAssertFalse(fractions(of: before).contains { $0.hasSuffix(":-") },
                       "the capture must have produced real fractions to compare")

        root.paneDidRequestZoom(try leaf(leftID, in: root))
        layOut(root)
        root.captureThicknessFractions()

        let after = root.snapshotNode()
        XCTAssertEqual(describe(after), describe(before),
                       "collapsing changed the screen, not the tree")
        XCTAssertEqual(fractions(of: after), fractions(of: before),
                       "a zoom must not write the collapsed arrangement into the saved sizes")
    }

    /// The other half of the same guard. A divider dragged in the last 300ms is
    /// still sitting in the debounce when the user hits zoom, and once
    /// `zoomedLeaf` is set the capture refuses to run at all — so unless the
    /// zoom takes the reading on its way in, the drag is silently lost.
    /// `paneDidRequestMinimize` already captures first; this is the same
    /// obligation on the other entry point.
    func testZoomingCapturesADragTheDebounceHasNotWrittenYet() throws {
        let root = try sideBySide()
        layOut(root)
        // What a drag leaves behind, without waiting out the 300ms.
        root.splitView.setPosition(200, ofDividerAt: 0)
        root.view.layoutSubtreeIfNeeded()

        root.paneDidRequestZoom(try leaf(leftID, in: root))

        let captured = try XCTUnwrap(fraction(of: leftID, in: root.snapshotNode()),
                                     "nothing was captured, so the drag was dropped")
        XCTAssertEqual(captured, 0.25, accuracy: 0.02,
                       "the dragged position, not the even split it started at")
    }

    /// The capture walks the *whole* tree, so declining to run it costs every
    /// split and not only the one showing a rail. A divider dragged elsewhere is
    /// still sitting in the 300ms debounce when the user zooms a minimized pane;
    /// a zoom that refuses to capture drops it — the very loss the test above
    /// exists to prevent, reached by a different door.
    ///
    /// Nothing has to be guarded by hand for the minimized pane itself:
    /// `captureThicknessFractions` skips a split that is showing a rail, so the
    /// stale frames the restore has not laid out yet are declined at source and
    /// every other split is still read.
    func testZoomingAMinimizedPaneStillCapturesADragInAnotherSplit() throws {
        let root = try makeTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .split(
                orientation: .vertical,
                first: .leaf(id: topID, contentType: beta),
                second: .leaf(id: bottomID, contentType: alpha)
            )
        ))
        layOut(root)
        let left = try leaf(leftID, in: root)
        root.paneDidRequestMinimize(left, to: .leading)
        root.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(left.minimizedEdge, .leading, "the setup has to actually minimize")

        // A drag in the nested split, which the debounce has not written yet.
        let top = try leaf(topID, in: root)
        let inner = try XCTUnwrap(top.parent as? ComposableTabsViewController)
        let total = inner.splitView.bounds.height
        inner.splitView.setPosition(200, ofDividerAt: 0)
        root.view.layoutSubtreeIfNeeded()
        // Read what the drag actually produced rather than assuming which edge
        // `setPosition` measures from; the assertion is that the capture agrees
        // with the screen, not that the screen holds a particular number.
        let onScreen = top.view.frame.height / total
        XCTAssertNotEqual(onScreen, 0.5, accuracy: 0.05, "the drag moved nothing")

        root.paneDidRequestZoom(left)

        XCTAssertEqual(try XCTUnwrap(fraction(of: topID, in: root.snapshotNode())),
                       onScreen, accuracy: 0.01,
                       "the drag in the unrelated split was dropped by the zoom")
    }

    /// A capture may only read geometry the user actually arranged. A pane
    /// showing its rail is not arranged — it is 32pt of chrome — and the 300ms
    /// debounce fires on any window resize while a pane is minimized, so the
    /// rail gets written as the pane's desired size without an unusual gesture.
    ///
    /// This has to survive a rebuild to be visible at all: in the same session
    /// AppKit's untouched `preferredThicknessFraction` still gives back the
    /// dragged size, so a test that only restores in-session cannot fail.
    func testMinimizingDoesNotOverwriteTheSizeTheUserDraggedTo() throws {
        let root = try sideBySide()
        layOut(root)
        // The user drags to 200 of 800; the debounce writes that.
        root.splitView.setPosition(200, ofDividerAt: 0)
        root.view.layoutSubtreeIfNeeded()
        root.captureThicknessFractions()
        XCTAssertEqual(try XCTUnwrap(fraction(of: leftID, in: root.snapshotNode())),
                       0.25, accuracy: 0.02, "the drag itself must land first")
        let dragged = fractions(of: root.snapshotNode())

        root.paneDidRequestMinimize(try leaf(leftID, in: root), to: .leading)
        root.view.layoutSubtreeIfNeeded()
        // The next debounce — a window resize, a tab appearing — while the pane
        // is still a rail.
        root.captureThicknessFractions()

        XCTAssertEqual(try XCTUnwrap(fraction(of: leftID, in: root.snapshotNode())),
                       0.25, accuracy: 0.02,
                       "the rail's own thickness was recorded as what the pane wants")
        // And not the pane's own fraction alone: the 32pt the rail gave up went
        // to its sibling, so the sibling's reading is just as false a record of
        // what the user chose. Here it is only latent — the divider is placed
        // from the *first* child, so the sibling's number is never consulted —
        // but it is the same wrong reading that ruins the trailing case below.
        XCTAssertEqual(fractions(of: root.snapshotNode()), dragged,
                       "a split showing a rail must record no new sizes at all")
        // What the user sees after a relaunch, before restoring anything.
        let rebuilt = try rebuild(root.snapshotNode())
        XCTAssertEqual(try width(of: leftID, in: rebuilt), 200, accuracy: 4,
                       "the pane reopened at its floor instead of the size it was dragged to")
    }

    /// The same gesture on the other side of the divider, and the one the user
    /// actually loses their layout to. Minimizing the *second* slot leaves the
    /// rail's own fraction intact — but `applyPreferredThicknessesIfNeeded`
    /// positions the divider from the non-last children and gives the last one
    /// whatever is left, so it is the *sibling's* fraction that decides where
    /// the minimized pane comes back to. The sibling swallowed the 32pt the
    /// rail freed; recording that hands it 767 of 800 on the next rebuild and
    /// the minimized pane reopens at its floor.
    ///
    /// Like the test above this only bites across a rebuild, and unlike the
    /// zoom test below it goes through the plain debounce — no unusual gesture,
    /// just a window resize while a pane is minimized.
    func testMinimizingTheTrailingPaneDoesNotOverwriteTheSizeTheUserDraggedTo() throws {
        let root = try sideBySide()
        layOut(root)
        // The user drags until the *right* pane is 200 of 800.
        let total = root.splitView.bounds.width
        root.splitView.setPosition(total - 200 - root.splitView.dividerThickness, ofDividerAt: 0)
        root.view.layoutSubtreeIfNeeded()
        root.captureThicknessFractions()
        XCTAssertEqual(try width(of: rightID, in: root), 200, accuracy: 4,
                       "the drag itself must land first")
        let dragged = fractions(of: root.snapshotNode())

        root.paneDidRequestMinimize(try leaf(rightID, in: root), to: .trailing)
        root.view.layoutSubtreeIfNeeded()
        // The next debounce, while the pane is still a rail.
        root.captureThicknessFractions()

        XCTAssertEqual(fractions(of: root.snapshotNode()), dragged,
                       "the space the rail freed was recorded as the sibling's desired size")
        // What the user sees after a relaunch, before restoring anything.
        let rebuilt = try rebuild(root.snapshotNode())
        XCTAssertEqual(try width(of: rightID, in: rebuilt), 200, accuracy: 4,
                       "the pane reopened at its floor instead of the size it was dragged to")
    }

    /// The same rule on the other stale-frame path. `paneDidRequestMinimize`
    /// clears a zoom and captures with no layout pass in between, so the frames
    /// it would read still describe the zoomed arrangement — every pane but one
    /// collapsed. The fractions captured on the way *into* the zoom are the
    /// truth and are still in the tree, so the capture must be skipped.
    func testMinimizingAfterAZoomKeepsTheSizesFromBeforeTheZoom() throws {
        let root = try sideBySide()
        layOut(root)
        root.splitView.setPosition(200, ofDividerAt: 0)
        root.view.layoutSubtreeIfNeeded()
        root.captureThicknessFractions()

        root.paneDidRequestZoom(try leaf(leftID, in: root))
        root.view.layoutSubtreeIfNeeded()
        root.paneDidRequestMinimize(try leaf(rightID, in: root), to: .trailing)

        XCTAssertEqual(try XCTUnwrap(fraction(of: leftID, in: root.snapshotNode())),
                       0.25, accuracy: 0.02,
                       "the zoomed arrangement was written over the size the user dragged to")
        let rebuilt = try rebuild(root.snapshotNode())
        XCTAssertEqual(try width(of: leftID, in: rebuilt), 200, accuracy: 4,
                       "and it is what the pane comes back at")
    }

    /// What a relaunch does: a fresh tree built from the snapshot that would
    /// have been persisted, with nothing but the stored fractions to go on.
    private func rebuild(_ node: LayoutNode) throws -> ComposableTabsViewController {
        let rebuilt = ComposableTabsViewController.make(from: node, project: project, isRoot: true)
        rebuilt.loadViewIfNeeded()
        for leaf in rebuilt.allLeaves() { leaf.loadViewIfNeeded() }
        layOut(rebuilt)
        return rebuilt
    }

    /// One pane's thickness along its parent's axis, on screen.
    private func width(of id: UUID, in root: ComposableTabsViewController) throws -> CGFloat {
        try item(for: leaf(id, in: root)).viewController.view.frame.width
    }

    /// One leaf's serialised fraction, or `nil` if it has none.
    private func fraction(of id: UUID, in node: LayoutNode) -> Double? {
        let prefix = "\(id):"
        guard let row = fractions(of: node).first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return Double(row.dropFirst(prefix.count))
    }

    /// Gives a tree a real size and lets AppKit lay it out, so the divider
    /// positions `captureThicknessFractions()` reads actually exist.
    private func layOut(_ root: ComposableTabsViewController) {
        root.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        root.view.layoutSubtreeIfNeeded()
    }

    /// The leaf thickness fractions a snapshot would be persisted with, in tree
    /// order — the part of the layout `describe(_:)` deliberately drops.
    private func fractions(of node: LayoutNode) -> [String] {
        switch node.kind {
        case .leaf:
            let value = node.thicknessFraction.map { String(format: "%.3f", $0) } ?? "-"
            return ["\(node.id):\(value)"]
        case .split(_, let first, let second):
            return fractions(of: first) + fractions(of: second)
        }
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
        // `left`, not `right`: `right` was the *zoomed* pane and was never
        // collapsed, so asserting on it would hold whether or not the unzoom
        // happened. `left` is the pane the zoom collapsed.
        XCTAssertFalse(try item(for: left).isCollapsed)
    }

    func testClosingTheZoomedPaneClearsTheZoom() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestZoom(left)

        root.paneDidRequestClose(left)

        XCTAssertNil(root.zoomedLeaf)
        XCTAssertFalse(try item(for: try leaf(rightID, in: root)).isCollapsed)
    }

    /// The other half of the rule above. `setZoomedLeaf(nil)` is not free — it
    /// calls `setZoomed(false)` on the pane, which *deletes* the row that
    /// remembers the zoom — so clearing it before asking whether the close is
    /// allowed made every refused click cost the pane its zoom. A refused close
    /// has to leave the pane exactly as it found it.
    func testARefusedCloseKeepsTheZoomItWouldOtherwiseThrowAway() throws {
        let root = try boundedSideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestZoom(left)
        XCTAssertTrue(root.zoomedLeaf === left)

        root.paneDidRequestClose(left)

        XCTAssertEqual(root.allLeaves().map(\.nodeID), [leftID, rightID],
                       "the spec's floor still refuses the close")
        XCTAssertTrue(root.zoomedLeaf === left, "and the refusal changed nothing else")
        XCTAssertTrue(left.isZoomed)
        XCTAssertEqual(left.stateStore.paneStateValue(forKey: PaneStateKey.zoomed), "1",
                       "including the row the pane comes back zoomed from")
    }

    /// The same tree as `sideBySide()`, under the floored spec — so every close
    /// in it is refused. `boundedNested()` is the unloaded equivalent; zooming
    /// needs split items, which do not exist until the view does.
    private func boundedSideBySide() throws -> ComposableTabsViewController {
        try installBoundedLayout()
        let root = ComposableTabsViewController.make(
            from: .split(
                orientation: .horizontal,
                first: .leaf(id: leftID, contentType: alpha),
                second: .leaf(id: rightID, contentType: beta)
            ),
            project: project,
            isRoot: true)
        root.loadViewIfNeeded()
        for pane in root.allLeaves() { pane.loadViewIfNeeded() }
        return root
    }

    // MARK: - Surviving a rebuild of the split items

    /// Every structural mutation re-creates split items through
    /// `makeItem(for:)`, which vends them unpinned. The minimize lives on the
    /// pane, so the tree has to put it back or `minimizedEdge` describes a pane
    /// that is visibly full size.
    func testAMinimizedPaneStaysPinnedThroughASplit() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestMinimize(left, to: .leading)

        root.split(left, adding: beta, direction: .right)

        XCTAssertEqual(left.minimizedEdge, .leading)
        XCTAssertEqual(try item(for: left).maximumThickness, 32,
                       "the rebuilt item has to come back pinned")
    }

    /// The same again through the other rebuild: closing a pane collapses the
    /// degenerate split that is left, and the survivor is re-inserted into its
    /// grandparent with a brand-new item.
    func testAMinimizedPaneStaysPinnedWhenACloseElsewherePromotesIt() throws {
        let root = try makeTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .split(
                orientation: .horizontal,
                first: .leaf(id: topID, contentType: beta),
                second: .leaf(id: bottomID, contentType: alpha)
            )
        ))
        let top = try leaf(topID, in: root)
        root.paneDidRequestMinimize(top, to: .leading)

        // Through the pane's own host, which is the split that built its item —
        // asking the root to close a grandchild is a no-op, and a test that did
        // that would assert nothing.
        let bottom = try leaf(bottomID, in: root)
        try XCTUnwrap(bottom.host).paneDidRequestClose(bottom)

        // The side is re-asked, not carried over: `top` was the *first* child of
        // the inner split and is promoted into the root's *second* slot, so the
        // tree re-docks it trailing. Same rule as
        // `testTheTreeDecidesWhichSideThePaneDocksTo`, applied to a pane that
        // moved rather than to one being minimized.
        XCTAssertEqual(top.minimizedEdge, .trailing)
        XCTAssertEqual(try item(for: top).maximumThickness, 32,
                       "promotion into the parent must not quietly un-minimize it")
    }

    /// The same promotion across a *change of axis*, which is where re-applying
    /// the stored edge stops being safe: `top` is minimized on a vertical edge
    /// inside a vertical split, and the close promotes it into a horizontal one
    /// where `.top` means nothing. Pinning it there freezes the pane at the
    /// vertical thickness on the horizontal axis, and the title-bar controls it
    /// would be restored from lay out at nothing — an unrecoverable pane, with
    /// no constraint warning to say so.
    func testACrossAxisPromotionNeverLeavesAPaneStuckOnADeadEdge() throws {
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
        root.paneDidRequestMinimize(top, to: .top)
        XCTAssertEqual(top.minimizedEdge, .top, "minimized along the axis it was living on")

        let bottom = try leaf(bottomID, in: root)
        try XCTUnwrap(bottom.host).paneDidRequestClose(bottom)

        // Either outcome is defensible — adopt an edge the new axis offers, or
        // give up and restore — but the pane has to be usable afterwards.
        let offered = root.availableMinimizeEdges(for: top)
        let pinned = try item(for: top)
        if let edge = top.minimizedEdge {
            XCTAssertTrue(offered.contains(edge),
                          "a pane cannot stay minimized toward an edge the tree no longer offers")
            XCTAssertEqual(pinned.maximumThickness, 32,
                           "pinned on a horizontal axis, so the horizontal thickness")
        } else {
            XCTAssertEqual(pinned.maximumThickness, NSSplitViewItem.unspecifiedDimension,
                           "the minimize was given up, so the pinning has to go with it")
        }
        XCTAssertGreaterThanOrEqual(pinned.minimumThickness, 32,
                                    "narrower than its own title-bar controls is a pane the user cannot get back")
    }

    /// `paneDidRequestClose` clears the zoom on the way in, but it is not the
    /// only door: the pane's own confirm-and-close and a drag that moves a pane
    /// both call `remove` directly. A zoom left pointing at a pane that is gone
    /// cannot be undone by clicking anything, and every survivor stays
    /// collapsed.
    func testRemovingTheZoomedPaneDirectlyClearsTheZoom() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestZoom(left)

        root.remove(left)

        XCTAssertNil(root.zoomedLeaf)
        XCTAssertFalse(left.isZoomed)
        XCTAssertFalse(try item(for: try leaf(rightID, in: root)).isCollapsed,
                       "the survivor has to come back on screen")
    }

    // MARK: - Re-applying what was persisted

    func testTheHostAppliesAPersistedMinimizeToTheTree() throws {
        let root = try sideBySide()
        let left = try leaf(leftID, in: root)
        left.stateStore.setPaneStateValue(PaneEdge.leading.rawValue,
                                          forKey: PaneStateKey.minimizeEdge)

        root.applyPersistedPaneState()

        XCTAssertEqual(left.minimizedEdge, .leading)
        XCTAssertEqual(try item(for: left).maximumThickness, 32)
    }

    func testTheHostAppliesAPersistedZoomToTheTree() throws {
        let root = try sideBySide()
        let right = try leaf(rightID, in: root)
        right.stateStore.setPaneStateValue("1", forKey: PaneStateKey.zoomed)

        root.applyPersistedPaneState()

        XCTAssertTrue(right.isZoomed)
        XCTAssertTrue(try item(for: try leaf(leftID, in: root)).isCollapsed)
    }

    // MARK: - A tab that has never been displayed

    /// A restored tab loads no view until the user switches to it. Nothing in
    /// this section calls `loadViewIfNeeded()`, so throughout it there are no
    /// split view items and no `parent` on any pane — which is the state a
    /// scripted request finds when it names a pane on a background tab.
    private func unloadedTree(_ node: LayoutNode) throws -> ComposableTabsViewController {
        try installLayout()
        let root = ComposableTabsViewController.make(from: node, project: project, isRoot: true)
        XCTAssertFalse(root.isViewLoaded, "the fixture stops being the fixture once anything loads")
        return root
    }

    private func unloadedSideBySide() throws -> ComposableTabsViewController {
        try unloadedTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .leaf(id: rightID, contentType: beta)
        ))
    }

    /// The nested shape the never-displayed fixtures use: `left` beside a
    /// vertical pair — the shallowest tree where the split holding a pane is
    /// not the root of the tab, which is the whole subject of this section.
    private func nestedNode(innerID: UUID) -> LayoutNode {
        .split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .split(
                id: innerID,
                orientation: .vertical,
                first: .leaf(id: topID, contentType: alpha),
                second: .leaf(id: bottomID, contentType: beta)
            )
        )
    }

    private func unloadedNested(innerID: UUID) throws -> ComposableTabsViewController {
        try unloadedTree(nestedNode(innerID: innerID))
    }

    /// `installLayout()` with a floor of one instance per view, which is the
    /// smallest spec that refuses a close.
    private func installBoundedLayout() throws {
        let registry = ComposableTabsViewRegistry()
        registry.register(
            alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)
        ) { _ in
            NSViewController()
        }
        registry.register(
            beta, descriptor: .init(displayName: "Beta", minimumThickness: 150)
        ) { _ in
            NSViewController()
        }
        ComposableTabsLayout.install(try ComposableTabsLayout(
            registry: registry,
            spec: .split(
                axis: .horizontal,
                children: [.pane(alpha), .pane(beta)],
                allows: [.unbounded(alpha, min: 1), .unbounded(beta, min: 1)]
            )
        ))
    }

    /// The same tree under a spec that floors both views at one instance.
    /// `installLayout()` is unbounded on purpose — what the spec *answers* is
    /// `ComposableTabLayoutSpecTests`' subject. A floor is needed here for the
    /// question one level up, which is this suite's: which tree the controller
    /// hands the spec. The tab holds two alphas and the inner split holds one,
    /// so a floor of one is the smallest spec the two trees disagree about.
    private func boundedNested() throws -> ComposableTabsViewController {
        try installBoundedLayout()
        let root = ComposableTabsViewController.make(
            from: nestedNode(innerID: UUID()), project: project, isRoot: true)
        XCTAssertFalse(root.isViewLoaded, "the fixture stops being the fixture once anything loads")
        return root
    }

    /// Every leaf id in a snapshot, so a persisted tree can be compared by what
    /// is in it rather than by its shape.
    private func leafIDs(of node: LayoutNode) -> [UUID] {
        switch node.kind {
        case .leaf: return [node.id]
        case .split(_, let first, let second):
            return leafIDs(of: first) + leafIDs(of: second)
        }
    }

    /// `host` is a fact about which split holds the pane, so it has to be true
    /// of a tree nobody has looked at. It used to be stamped in
    /// `makeItem(for:)`, which only ever runs on the load path.
    func testAPaneOnANeverDisplayedTabAlreadyKnowsItsHost() throws {
        let root = try unloadedSideBySide()
        for pane in root.allLeaves() {
            XCTAssertTrue(pane.host === root, "the split holding the pane is its host, loaded or not")
        }
    }

    /// The whole point of the host being right: every scripted action goes
    /// through it, and a nil host is a silent no-op.
    func testClosingAPaneOnANeverDisplayedTabRemovesIt() throws {
        let root = try unloadedSideBySide()
        let left = try leaf(leftID, in: root)

        left.host?.paneDidRequestClose(left)

        XCTAssertEqual(root.allLeaves().map(\.nodeID), [rightID])
    }

    /// And it removes it without building anything. The removal path asks each
    /// pane whether it holds the first responder, and reading `view` to answer
    /// would construct the whole content graph — a terminal, a file browser —
    /// purely to throw it away a line later. A pane with no view cannot hold
    /// the responder anyway, so the answer is already known.
    func testClosingAPaneOnANeverDisplayedTabBuildsNoViewToDoIt() throws {
        let root = try unloadedSideBySide()
        let left = try leaf(leftID, in: root)

        XCTAssertFalse(left.containsFirstResponder, "no view, so no responder inside one")
        XCTAssertFalse(left.isViewLoaded, "and asking did not build one")

        left.host?.paneDidRequestClose(left)

        XCTAssertEqual(root.allLeaves().map(\.nodeID), [rightID])
        XCTAssertFalse(left.isViewLoaded, "nor did closing it")
        XCTAssertFalse(root.isViewLoaded, "the tab is still one nobody has opened")
    }

    /// The other entry point. `init` assigns `layoutChildren` before
    /// `super.init`, where Swift runs no property observer, so the two paths
    /// are stamped by different code and each needs its own proof.
    func testARebuiltNeverDisplayedTabRehostsItsPanes() throws {
        let root = try unloadedTree(.leaf(id: leftID, contentType: alpha))

        root.rebuild(from: .split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .leaf(id: rightID, contentType: beta)
        ))

        XCTAssertFalse(root.isViewLoaded)
        XCTAssertEqual(root.allLeaves().count, 2)
        for pane in root.allLeaves() {
            XCTAssertNotNil(pane.host, "a rebuild re-homes every pane, on screen or not")
        }
    }

    /// A nested split is built by its own `init`, so the stamping has to reach
    /// down the tree rather than only across the root's direct children.
    func testANestedPaneOnANeverDisplayedTabKnowsItsOwnSplit() throws {
        let innerID = UUID()
        let root = try unloadedTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .split(
                id: innerID,
                orientation: .vertical,
                first: .leaf(id: topID, contentType: alpha),
                second: .leaf(id: bottomID, contentType: beta)
            )
        ))
        let inner = try XCTUnwrap(
            root.layoutChildren.compactMap { $0 as? ComposableTabsViewController }.first)

        XCTAssertTrue(try leaf(leftID, in: root).host === root)
        XCTAssertTrue(try leaf(topID, in: root).host === inner,
                      "a nested pane's host is the split that can actually remove it")
        XCTAssertTrue(try leaf(bottomID, in: root).host === inner)
    }

    /// The state half of a minimize does not need a split item, and refusing to
    /// do it because the geometry half cannot run yet is how a scripted
    /// minimize on a background tab used to evaporate.
    func testMinimizingAPaneOnANeverDisplayedTabRecordsTheEdge() throws {
        let root = try unloadedSideBySide()
        let left = try leaf(leftID, in: root)

        left.host?.paneDidRequestMinimize(left, to: .leading)

        XCTAssertEqual(left.minimizedEdge, .leading)
        XCTAssertEqual(left.persistedMinimizeEdge, .leading,
                       "and it survives to the store, which is what displays the tab reads")
    }

    /// The geometry half, arriving late. `viewDidAppear` is where the root
    /// restores what the panes remember, and it has never fired for a tab
    /// nobody has switched to.
    func testAMinimizeRequestedWhileUnloadedPinsTheItemOnFirstDisplay() throws {
        let root = try unloadedSideBySide()
        let left = try leaf(leftID, in: root)
        left.host?.paneDidRequestMinimize(left, to: .leading)

        root.loadViewIfNeeded()
        for pane in root.allLeaves() { pane.loadViewIfNeeded() }
        root.viewDidAppear()

        XCTAssertEqual(try item(for: left).maximumThickness, 32,
                       "28pt strip + 2pt border either side, applied when the tab first appeared")
        XCTAssertEqual(try item(for: left).holdingPriority, .defaultHigh)
    }

    func testRestoringAPaneOnANeverDisplayedTabClearsTheEdge() throws {
        let root = try unloadedSideBySide()
        let left = try leaf(leftID, in: root)
        left.host?.paneDidRequestMinimize(left, to: .leading)
        XCTAssertEqual(left.minimizedEdge, .leading, "there is nothing to restore otherwise")

        left.host?.paneDidRequestRestore(left)

        XCTAssertNil(left.minimizedEdge)
        XCTAssertNil(left.persistedMinimizeEdge,
                     "a restore has to clear the row, or the next display re-minimizes")
    }

    /// The refusal is not collateral damage of the fix. A vertical split has no
    /// leading edge to dock to, and that is a real answer whether or not
    /// anything has been laid out.
    func testARefusedEdgeIsStillRefusedOnANeverDisplayedTab() throws {
        let root = try unloadedTree(.split(
            orientation: .vertical,
            first: .leaf(id: topID, contentType: alpha),
            second: .leaf(id: bottomID, contentType: beta)
        ))
        let top = try leaf(topID, in: root)

        top.host?.paneDidRequestMinimize(top, to: .leading)

        XCTAssertNil(top.minimizedEdge, "the tree refuses an edge its axis does not have")
        XCTAssertNil(top.persistedMinimizeEdge)
    }

    /// `captureThicknessFractions()` runs on the way into a minimize, and on an
    /// unloaded tree it must write nothing: the fractions sitting in the tree
    /// are the persisted ones, and overwriting them from geometry that does not
    /// exist yet is how a restore forgets every divider position in the tab.
    func testMinimizingOnANeverDisplayedTabDoesNotClobberTheStoredFractions() throws {
        let root = try unloadedTree(.split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha, thicknessFraction: 0.25),
            second: .leaf(id: rightID, contentType: beta, thicknessFraction: 0.75)
        ))
        let left = try leaf(leftID, in: root)

        left.host?.paneDidRequestMinimize(left, to: .leading)

        XCTAssertEqual(fraction(of: leftID, in: root.snapshotNode()) ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(fraction(of: rightID, in: root.snapshotNode()) ?? 0, 0.75, accuracy: 0.0001)
    }

    // MARK: - A nested tab that has never been displayed

    /// `rootSplit()` walked `parent`, which AppKit sets in `addSplitViewItem`
    /// and nowhere else — so on a tab nobody has switched to it stopped at
    /// whichever split it was asked and called that the root of the tab.
    func testANestedSplitOnANeverDisplayedTabKnowsWhichSplitHoldsIt() throws {
        let innerID = UUID()
        let root = try unloadedNested(innerID: innerID)
        let inner = try XCTUnwrap(
            root.layoutChildren.compactMap { $0 as? ComposableTabsViewController }.first)

        XCTAssertTrue(inner.layoutParent === root)
        XCTAssertNil(root.layoutParent, "the root is held by the tab, not by a split")
        XCTAssertTrue(inner.rootSplit() === root,
                      "and asking any split for the root has to reach the tab's root")
    }

    /// `persistTreeToDocument()` opens with `guard isRoot`, so a `rootSplit()`
    /// that stops at the inner split does not write a wrong tree — it writes
    /// nothing at all, and the pane a script just closed is back next launch.
    func testClosingANestedPaneOnANeverDisplayedTabPersistsTheTab() throws {
        let root = try unloadedNested(innerID: UUID())
        var persisted: [LayoutNode] = []
        root.onLayoutDidChange = { persisted.append($0) }
        let top = try leaf(topID, in: root)

        top.host?.paneDidRequestClose(top)

        let last = try XCTUnwrap(persisted.last, "a close the document never hears about")
        XCTAssertEqual(Set(leafIDs(of: last)), [leftID, bottomID])
    }

    /// A non-root split left holding one child collapses into its parent. That
    /// promotion was gated on `parent`, so on a tab nobody had displayed the
    /// one-child split just stayed in the tree.
    func testAnInnerSplitOnANeverDisplayedTabCollapsesWhenItIsDownToOnePane() throws {
        let root = try unloadedNested(innerID: UUID())
        let top = try leaf(topID, in: root)

        top.host?.paneDidRequestClose(top)

        XCTAssertEqual(root.allLeaves().map(\.nodeID), [leftID, bottomID])
        XCTAssertTrue(
            root.layoutChildren.allSatisfy { $0 is ComposableTabsPaneViewController },
            "the survivor is promoted into the slot the inner split held")
        XCTAssertTrue(try leaf(bottomID, in: root).host === root,
                      "and the promotion re-homes it, so its next close reaches the root")
    }

    /// A zoom is a fact about the tab. Stored on the inner split it is
    /// invisible to the root that applies it, and to the next pane that zooms.
    func testZoomingANestedPaneOnANeverDisplayedTabRecordsItOnTheTabsRoot() throws {
        let innerID = UUID()
        let root = try unloadedNested(innerID: innerID)
        let inner = try XCTUnwrap(
            root.layoutChildren.compactMap { $0 as? ComposableTabsViewController }.first)
        let top = try leaf(topID, in: root)

        top.host?.paneDidRequestZoom(top)

        XCTAssertTrue(root.zoomedLeaf === top)
        XCTAssertNil(inner.zoomedLeaf)
        XCTAssertTrue(top.isZoomed)
    }

    /// The promotion changes the axis under a minimized pane: `.bottom` off a
    /// vertical split, into a horizontal one that has no bottom.
    /// `reapplyPaneState` re-asks the tree and hands the pane back — and it has
    /// to do that on a tab with no split items, or the tab's first display
    /// draws a rail on a side the pane is not docked to.
    func testAPromotionOnANeverDisplayedTabClearsAnEdgeTheNewSplitDoesNotHave() throws {
        let root = try unloadedNested(innerID: UUID())
        let top = try leaf(topID, in: root)
        let bottom = try leaf(bottomID, in: root)
        bottom.host?.paneDidRequestMinimize(bottom, to: .bottom)
        XCTAssertEqual(bottom.minimizedEdge, .bottom, "nothing to correct otherwise")

        top.host?.paneDidRequestClose(top)

        XCTAssertNil(bottom.minimizedEdge,
                     "a horizontal split has no bottom to dock to")
        XCTAssertNil(bottom.persistedMinimizeEdge,
                     "and the row goes with it, or the next launch re-minimizes")
    }

    /// `layoutChildren`'s `didSet` re-stamps the panes that remain and says
    /// nothing about the one that left, so a removed pane went on naming the
    /// split that no longer holds it as the split that can remove it.
    func testAClosedPaneStopsNamingTheSplitThatUsedToHoldIt() throws {
        let root = try unloadedSideBySide()
        let left = try leaf(leftID, in: root)

        left.host?.paneDidRequestClose(left)

        XCTAssertNil(left.host, "nothing holds it, so nothing can be asked to remove it again")
    }

    /// `canRemoveLeaf` asks the spec about a tree, and *which* tree it asks
    /// about is the whole question. The tab holds two alphas and the inner
    /// split holds one, so a floor of one alpha is met by the tab and violated
    /// by the subtree: before `rootSplit()` learned to walk `layoutParent`, a
    /// close the spec permits was silently refused on a tab nobody had
    /// displayed.
    func testTheRemovalVetoOnANeverDisplayedTabIsAskedAboutTheTabNotTheSubtree() throws {
        let root = try boundedNested()
        let top = try leaf(topID, in: root)
        let bottom = try leaf(bottomID, in: root)
        let inner = try XCTUnwrap(top.host as? ComposableTabsViewController)

        XCTAssertTrue(inner.canRemoveLeaf(top),
                      "the tab still holds another alpha, so the floor is met")
        // The same floor, genuinely enforced. `bottom` is the tab's only beta
        // and both trees agree about that, so this is the line that stops the
        // one above from passing against a floor that never refuses anything.
        XCTAssertFalse(inner.canRemoveLeaf(bottom),
                       "the tab's only beta is what the floor is protecting")

        // The refused close first: the permitted one collapses the inner split,
        // and `bottom` would no longer be a child of `inner` to refuse.
        bottom.host?.paneDidRequestClose(bottom)
        XCTAssertEqual(root.allLeaves().map(\.nodeID), [leftID, topID, bottomID],
                       "a refused close leaves the tree exactly as it was")

        top.host?.paneDidRequestClose(top)
        XCTAssertEqual(root.allLeaves().map(\.nodeID), [leftID, bottomID],
                       "and the veto is what `remove(_:)` gates on, so a wrong answer keeps the pane")
    }

    /// A collapse detaches the inner split from the tab. `layoutChildren`'s
    /// `didSet` re-stamps what remains and says nothing about what left, so
    /// without clearing it the detached split goes on naming a parent that no
    /// longer holds it — and `rootSplit()`, which now trusts that pointer,
    /// answers for a tab the split is no longer part of.
    func testACollapsedSplitStopsNamingTheSplitThatUsedToHoldIt() throws {
        let root = try unloadedNested(innerID: UUID())
        let inner = try XCTUnwrap(
            root.layoutChildren.compactMap { $0 as? ComposableTabsViewController }.first)
        let top = try leaf(topID, in: root)

        top.host?.paneDidRequestClose(top)

        XCTAssertNil(inner.layoutParent, "nothing holds it now")
        XCTAssertTrue(inner.rootSplit() === inner,
                      "so it answers for itself rather than for a tab it has left")
    }

    /// The negative of `testARebuiltNeverDisplayedTabRehostsItsPanes`: a rebuild
    /// re-homes the panes it keeps, and `layoutChildren`'s `didSet` reaches only
    /// those. A pane the new shape leaves out is held by nothing, and `host` is
    /// what `ScriptablePane` and `ComposableTabsPaneHost` navigate by — so a
    /// dropped pane still naming the split that dropped it is a pointer that
    /// answers wrongly rather than one that refuses.
    func testARebuildLeavesADroppedPaneNamingNoHost() throws {
        let root = try unloadedSideBySide()
        let dropped = try leaf(rightID, in: root)
        XCTAssertTrue(dropped.host === root, "the fixture starts with the pane hosted")

        root.rebuild(from: .leaf(id: leftID, contentType: alpha))

        XCTAssertEqual(root.allLeaves().map(\.nodeID), [leftID],
                       "the rebuild kept one pane")
        XCTAssertNil(dropped.host, "and the one it dropped is held by nothing")
        XCTAssertNotNil(try leaf(leftID, in: root).host,
                        "while the one it kept is still hosted — the clear is not a scrub")
    }

    /// The same for a split. `rootSplit()` walks `layoutParent`, so a discarded
    /// inner split still naming its old parent walks a reader back into a tree
    /// that is no longer the tab's.
    func testARebuildLeavesADiscardedInnerSplitNamingNoParent() throws {
        let root = try unloadedNested(innerID: UUID())
        let inner = try XCTUnwrap(
            root.layoutChildren.compactMap { $0 as? ComposableTabsViewController }.first)
        XCTAssertTrue(inner.layoutParent === root, "the fixture starts with it parented")

        root.rebuild(from: .split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .leaf(id: rightID, contentType: beta)
        ))

        XCTAssertNil(inner.layoutParent, "nothing holds the discarded split now")
        XCTAssertTrue(inner.rootSplit() === inner,
                      "so it answers for itself rather than for a tab it has left")
    }
}
