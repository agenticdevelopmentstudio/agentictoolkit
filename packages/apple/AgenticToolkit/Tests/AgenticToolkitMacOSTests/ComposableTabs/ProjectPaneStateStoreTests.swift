import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// The store, and the round trip a pane makes through it.
@MainActor
final class ProjectPaneStateStoreTests: XCTestCase {

    private let alpha = ComposableTabsViewID("test.alpha")
    private let beta = ComposableTabsViewID("test.beta")
    private let leftID = UUID()
    private let rightID = UUID()

    private lazy var project = Self.makeWorkspace()

    /// A workspace whose repository is *registered*. `pane_state.repo_id`
    /// references `git_repo(id)` and the database runs with
    /// `PRAGMA foreign_keys=ON`, so a project the database has never heard of
    /// cannot hold a row — every write would be refused and logged, and every
    /// read would come back empty. The window manager only ever opens a repo
    /// the scan already inserted, so registering it here is what makes the
    /// fixture the situation these tests are about.
    @MainActor
    private static func makeWorkspace() -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaneStateStoreTests-\(UUID().uuidString)")
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

    // MARK: - The store on its own

    func testAValueWrittenComesBack() {
        let store = ProjectPaneStateStore(project: project, nodeID: leftID)
        store.setPaneStateValue("leading", forKey: PaneStateKey.minimizeEdge)

        XCTAssertEqual(store.paneStateValue(forKey: PaneStateKey.minimizeEdge), "leading")
    }

    func testWritingNilForgetsTheValue() {
        let store = ProjectPaneStateStore(project: project, nodeID: leftID)
        store.setPaneStateValue("leading", forKey: PaneStateKey.minimizeEdge)

        store.setPaneStateValue(nil, forKey: PaneStateKey.minimizeEdge)

        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.minimizeEdge))
    }

    /// The same bag holds what the *content* remembers. A chrome key and a
    /// content key that happened to match would be a bug visible in exactly one
    /// pane type, so chrome keys are namespaced.
    func testChromeKeysCannotCollideWithContentKeys() {
        let store = ProjectPaneStateStore(project: project, nodeID: leftID)
        project.setPaneState(nodeID: leftID, key: PaneStateKey.zoomed, value: "content wrote this")

        store.setPaneStateValue("1", forKey: PaneStateKey.zoomed)

        XCTAssertEqual(store.paneStateValue(forKey: PaneStateKey.zoomed), "1")
        XCTAssertEqual(project.paneState(nodeID: leftID, key: PaneStateKey.zoomed),
                       "content wrote this", "the content's row is untouched")
        XCTAssertEqual(store.storageKey(for: PaneStateKey.zoomed), "chrome.zoomed")
    }

    func testEachPaneHasItsOwnState() {
        let left = ProjectPaneStateStore(project: project, nodeID: leftID)
        let right = ProjectPaneStateStore(project: project, nodeID: rightID)

        left.setPaneStateValue("leading", forKey: PaneStateKey.minimizeEdge)

        XCTAssertNil(right.paneStateValue(forKey: PaneStateKey.minimizeEdge))
    }

    /// A pane outlives its project only while the window is tearing down. The
    /// store holds the project weakly, so that window is quiet rather than
    /// fatal.
    func testAStoreWithNoProjectIsInertRatherThanFatal() {
        let store = ProjectPaneStateStore(project: nil, nodeID: leftID)

        store.setPaneStateValue("leading", forKey: PaneStateKey.minimizeEdge)

        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.minimizeEdge))
    }

    // MARK: - The round trip a pane makes

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

    private var node: LayoutNode {
        .split(
            orientation: .horizontal,
            first: .leaf(id: leftID, contentType: alpha),
            second: .leaf(id: rightID, contentType: beta)
        )
    }

    /// A fresh tree over the same project and the same node ids — which is what
    /// a relaunch is, minus the process boundary.
    private func makeTree() throws -> ComposableTabsViewController {
        try installLayout()
        let root = ComposableTabsViewController.make(from: node, project: project, isRoot: true)
        root.loadViewIfNeeded()
        for leaf in root.allLeaves() { leaf.loadViewIfNeeded() }
        return root
    }

    private func leaf(_ id: UUID, in root: ComposableTabsViewController)
        throws -> ComposableTabsPaneViewController {
        try XCTUnwrap(root.allLeaves().first { $0.nodeID == id })
    }

    func testATreeBuiltPaneStoresThroughItsProject() throws {
        let root = try makeTree()
        let left = try leaf(leftID, in: root)

        left.stateStore.setPaneStateValue("leading", forKey: PaneStateKey.minimizeEdge)

        XCTAssertEqual(project.paneState(nodeID: leftID, key: "chrome.minimize.edge"), "leading")
    }

    func testAMinimizedPaneComesBackMinimized() throws {
        let first = try makeTree()
        first.paneDidRequestMinimize(try leaf(leftID, in: first), to: .leading)

        let second = try makeTree()
        let restored = try leaf(leftID, in: second)

        XCTAssertEqual(restored.minimizedEdge, .leading, "the pane's own chrome")

        second.applyPersistedPaneState()
        let owner = try XCTUnwrap(restored.parent as? ComposableTabsViewController)
        let item = try XCTUnwrap(owner.splitViewItem(for: restored))
        XCTAssertEqual(item.maximumThickness, restored.minimizedThickness(for: .leading),
                       "and the tree's half of it")
    }

    func testRestoringAPaneForgetsThatItWasMinimized() throws {
        let first = try makeTree()
        let left = try leaf(leftID, in: first)
        first.paneDidRequestMinimize(left, to: .leading)

        first.paneDidRequestRestore(left)

        XCTAssertNil(project.paneState(nodeID: leftID, key: "chrome.minimize.edge"))
        XCTAssertNil(try leaf(leftID, in: try makeTree()).minimizedEdge)
    }

    func testAZoomedPaneComesBackZoomed() throws {
        let first = try makeTree()
        first.paneDidRequestZoom(try leaf(rightID, in: first))

        let second = try makeTree()
        second.applyPersistedPaneState()

        XCTAssertTrue(try leaf(rightID, in: second).isZoomed)
        let left = try leaf(leftID, in: second)
        let owner = try XCTUnwrap(left.parent as? ComposableTabsViewController)
        XCTAssertTrue(try XCTUnwrap(owner.splitViewItem(for: left)).isCollapsed)
    }

    func testUnzoomingForgetsIt() throws {
        let first = try makeTree()
        let right = try leaf(rightID, in: first)
        first.paneDidRequestZoom(right)

        first.paneDidRequestZoom(right)

        XCTAssertNil(project.paneState(nodeID: rightID, key: "chrome.zoomed"))
        XCTAssertFalse(try leaf(rightID, in: try makeTree()).isZoomed)
    }

    /// The four edges only. The two gutters belong to the grid rather than to
    /// one pane and are never stored — see
    /// `PaneSpacingOverrideTests.testGuttersAreNotPartOfAPanesOverride`, which
    /// is where that rule is pinned. This test is about the trip through the
    /// project, so it overrides what a pane may actually own.
    func testAPanesOwnFrameSpacingSurvives() throws {
        let spacing = Spacing(top: 12, leading: 12, bottom: 12, trailing: 12)
        let first = try makeTree()
        try leaf(leftID, in: first).spacingOverride.setOverride(spacing)

        let restored = try leaf(leftID, in: try makeTree())

        XCTAssertTrue(restored.spacingOverride.isOverridden)
        XCTAssertEqual(restored.spacingOverride.resolved, spacing)
    }

    func testUsingTheDefaultAgainForgetsTheOverride() throws {
        let first = try makeTree()
        let left = try leaf(leftID, in: first)
        left.spacingOverride.setOverride(Spacing(uniform: 12))

        left.spacingOverride.reset()

        XCTAssertNil(project.paneState(nodeID: leftID, key: "chrome.spacing.override"))
        XCTAssertFalse(try leaf(leftID, in: try makeTree()).spacingOverride.isOverridden)
    }

    /// Closing a pane must not leave its rows behind. The database already
    /// prunes on save; this is the test that says so from up here.
    func testAClosedPaneTakesItsStateWithIt() throws {
        let root = try makeTree()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestMinimize(left, to: .leading)

        root.paneDidRequestClose(left)
        project.persistTabs(
            [TabRecord(title: "Tab 1", root: root.snapshotNode())],
            activeTabID: nil,
            enabledEdges: [.top]
        )

        XCTAssertNil(project.paneState(nodeID: leftID, key: "chrome.minimize.edge"))
    }
}
