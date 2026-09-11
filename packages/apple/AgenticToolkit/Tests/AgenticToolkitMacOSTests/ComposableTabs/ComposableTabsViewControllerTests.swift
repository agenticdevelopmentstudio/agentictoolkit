import XCTest
import AppKit
import AgenticToolkitMacOS

/// Removing a pane hands its space to the surviving sibling and never resizes
/// the enclosing tab. A non-root split left holding one child is degenerate and
/// collapses into its parent; the *root* may hold one child, which is a tab
/// reduced to a single full-size pane.
@MainActor
final class ComposableTabsViewControllerTests: XCTestCase {

    // `setUp`/`tearDown` are nonisolated, so the project is built lazily on
    // first use from the main-actor-isolated test body instead.
    private lazy var project = Self.makeWorkspace()

    /// A workspace backed by a throwaway database. The tests here never read a
    /// row back — they need a project only because panes are built from one.
    @MainActor
    private static func makeWorkspace() -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComposableTabsTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        // A failure here is a broken test environment, not a case to handle.
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        return ProjectWorkspace(
            repo: GitRepo(path: NSTemporaryDirectory(), name: "Test"),
            database: database
        )
    }

    /// Every leaf holds the placeholder view: these tests are about tree
    /// surgery, and panes are told apart by `nodeID`. The project's default
    /// layout allows the placeholder anywhere and unboundedly, so nothing here
    /// is refused for a reason the test did not ask about.
    private func makeLeaf(_ id: UUID) -> ComposableTabsPaneViewController {
        ComposableTabsPaneViewController(
            nodeID: id,
            paneNumber: project.allocatePaneNumber(),
            viewID: .placeholder,
            project: project,
            workingDirectory: project.directoryURL
        )
    }

    /// Loads the root's view so children are really parented — collapse walks
    /// `parent`, which only exists once the split view items are installed.
    private func makeLoadedRoot(
        first: any ComposableTabsChild,
        second: any ComposableTabsChild
    ) -> ComposableTabsViewController {
        let root = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            first: first,
            second: second,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        _ = root.view
        return root
    }

    private func leafIDs(in node: LayoutNode) -> [UUID] {
        switch node.kind {
        case .leaf:
            return [node.id]
        case .split(_, let first, let second):
            return leafIDs(in: first) + leafIDs(in: second)
        }
    }

    // MARK: - Collapse

    func testRemovingAPaneCollapsesTheDegenerateSplitIntoItsParent() {
        let idA = UUID(), idB = UUID(), idC = UUID()
        let leafA = makeLeaf(idA)
        let leafB = makeLeaf(idB)
        let leafC = makeLeaf(idC)
        let inner = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .vertical,
            first: leafB,
            second: leafC,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: false
        )
        let root = makeLoadedRoot(first: leafA, second: inner)

        inner.remove(leafC)

        XCTAssertEqual(root.leafCount(), 2,
            "removing one of the inner split's two leaves must leave two panes in the tab")
        XCTAssertEqual(leafIDs(in: root.snapshotNode()), [idA, idB],
            "the surviving sibling must be adopted by the grandparent, not left inside a one-child split")
        if case .split = root.snapshotNode().kind {} else {
            XCTFail("the root should still be a two-pane split")
        }
    }

    func testCollapseKeepsTheSurvivorAtTheRemovedSplitsPosition() {
        let idA = UUID(), idB = UUID(), idC = UUID()
        let leafA = makeLeaf(idA)
        let leafB = makeLeaf(idB)
        let leafC = makeLeaf(idC)
        // The nested split is the *first* child this time.
        let inner = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .vertical,
            first: leafB,
            second: leafC,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: false
        )
        let root = makeLoadedRoot(first: inner, second: leafA)

        inner.remove(leafB)

        XCTAssertEqual(leafIDs(in: root.snapshotNode()), [idC, idA],
            "the survivor must land where the collapsed split was, not at the end")
    }

    // MARK: - The root may hold one pane

    func testRemovingDownToOnePaneLeavesTheRootHoldingThatPane() {
        let idA = UUID(), idB = UUID()
        let leafA = makeLeaf(idA)
        let leafB = makeLeaf(idB)
        let root = makeLoadedRoot(first: leafA, second: leafB)

        root.remove(leafB)

        XCTAssertEqual(root.leafCount(), 1)
        let snapshot = root.snapshotNode()
        XCTAssertEqual(leafIDs(in: snapshot), [idA])
        guard case .leaf = snapshot.kind else {
            return XCTFail("a tab reduced to one pane must snapshot as a leaf, not a one-child split")
        }
    }

    func testMakeFromALeafHostsASinglePaneInsteadOfPaddingWithAPlaceholder() {
        let idA = UUID()
        let root = ComposableTabsViewController.make(
            from: LayoutNode.leaf(id: idA, contentType: .placeholder),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )

        XCTAssertEqual(root.leafCount(), 1,
            "a stored single-pane tab must not be re-inflated with a placeholder sibling")
        XCTAssertEqual(leafIDs(in: root.snapshotNode()), [idA])
    }

    func testASinglePaneTabRoundTripsThroughSnapshotAndMake() {
        let idA = UUID(), idB = UUID()
        let leafA = makeLeaf(idA)
        let leafB = makeLeaf(idB)
        let root = makeLoadedRoot(first: leafA, second: leafB)
        root.remove(leafB)

        let restored = ComposableTabsViewController.make(
            from: root.snapshotNode(),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )

        XCTAssertEqual(restored.leafCount(), 1)
        XCTAssertEqual(leafIDs(in: restored.snapshotNode()), [idA])
    }

    // MARK: - Guards and notification

    func testRemovingTheLastPaneIsRefused() {
        let idA = UUID(), idB = UUID()
        let leafA = makeLeaf(idA)
        let leafB = makeLeaf(idB)
        let root = makeLoadedRoot(first: leafA, second: leafB)
        root.remove(leafB)

        root.remove(leafA)

        XCTAssertEqual(root.leafCount(), 1,
            "the last pane in a tab must survive — nothing else can fill the space")
    }

    func testRemovingAPaneNotInThisSplitIsANoOp() {
        let leafA = makeLeaf(UUID())
        let leafB = makeLeaf(UUID())
        let stranger = makeLeaf(UUID())
        let root = makeLoadedRoot(first: leafA, second: leafB)

        root.remove(stranger)

        XCTAssertEqual(root.leafCount(), 2)
    }

    func testRemovalNotifiesTheRootWithTheFreshSnapshot() {
        let idA = UUID(), idB = UUID(), idC = UUID()
        let leafA = makeLeaf(idA)
        let leafB = makeLeaf(idB)
        let leafC = makeLeaf(idC)
        let inner = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .vertical,
            first: leafB,
            second: leafC,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: false
        )
        let root = makeLoadedRoot(first: leafA, second: inner)

        var received: [LayoutNode] = []
        root.onLayoutDidChange = { received.append($0) }

        inner.remove(leafC)

        XCTAssertEqual(received.count, 1,
            "a removal deep in the tree must reach the root exactly once")
        XCTAssertEqual(received.first.map(leafIDs(in:)), [idA, idB])
    }

    // MARK: - Splitting still works alongside removal

    func testSplitThenRemoveReturnsTheOriginalLayout() {
        let idA = UUID(), idB = UUID()
        let leafA = makeLeaf(idA)
        let leafB = makeLeaf(idB)
        let root = makeLoadedRoot(first: leafA, second: leafB)
        let before = leafIDs(in: root.snapshotNode())

        root.split(leafB, adding: .placeholder, direction: .below)
        XCTAssertEqual(root.leafCount(), 3)

        // The pane the split created is the one that is neither A nor B.
        guard let addedID = leafIDs(in: root.snapshotNode()).first(where: { $0 != idA && $0 != idB }),
              let addedLeaf = findLeaf(addedID, under: root),
              let owner = addedLeaf.parent as? ComposableTabsViewController else {
            return XCTFail("splitting must introduce exactly one new, locatable leaf")
        }

        owner.remove(addedLeaf)

        XCTAssertEqual(leafIDs(in: root.snapshotNode()), before,
            "splitting then removing the new pane must restore the original two-pane layout")
    }

    /// Depth-first search of the live controller containment tree. Touching
    /// `view` forces a split that was only just inserted to install its items,
    /// so its children exist before we look for them.
    private func findLeaf(_ id: UUID, under controller: NSViewController) -> ComposableTabsPaneViewController? {
        _ = controller.view
        for child in controller.children {
            if let leaf = child as? ComposableTabsPaneViewController, leaf.nodeID == id { return leaf }
            if let found = findLeaf(id, under: child) { return found }
        }
        return nil
    }
}
