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

    /// Windows the appearance tests put on screen. Ordered out here, the way
    /// `PaneViewControllerTests` and `NotesSplitViewControllerTests` do with
    /// theirs, so a test that leaves one keyed cannot bleed into the next.
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.orderOut(nil) }
        windows = []
        ComposableTabsLayout.install(nil)
        try await super.tearDown()
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
        // The precondition is the whole point. Without it a store that never
        // wrote anything — the shape a refused foreign key produces, silently
        // — would pass this test on the strength of the absence alone.
        XCTAssertEqual(store.paneStateValue(forKey: PaneStateKey.minimizeEdge), "leading",
                       "there has to be a row here for the delete to be about")

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

    /// Two nodes, two keys, four reads: each store sees its own write and
    /// neither sees the other's. The two positive reads are what stop an
    /// implementation that writes nothing and returns `nil` from satisfying
    /// the two negative ones.
    func testEachPaneHasItsOwnState() {
        let left = ProjectPaneStateStore(project: project, nodeID: leftID)
        let right = ProjectPaneStateStore(project: project, nodeID: rightID)

        left.setPaneStateValue("leading", forKey: PaneStateKey.minimizeEdge)
        right.setPaneStateValue("1", forKey: PaneStateKey.zoomed)

        XCTAssertEqual(left.paneStateValue(forKey: PaneStateKey.minimizeEdge), "leading",
                       "the left pane's own write")
        XCTAssertEqual(right.paneStateValue(forKey: PaneStateKey.zoomed), "1",
                       "the right pane's own write")
        XCTAssertNil(right.paneStateValue(forKey: PaneStateKey.minimizeEdge))
        XCTAssertNil(left.paneStateValue(forKey: PaneStateKey.zoomed))
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

    private func splitItem(for id: UUID, in root: ComposableTabsViewController)
        throws -> (ComposableTabsPaneViewController, ComposableTabsViewController, NSSplitViewItem) {
        let pane = try leaf(id, in: root)
        let owner = try XCTUnwrap(pane.parent as? ComposableTabsViewController)
        return (pane, owner, try XCTUnwrap(owner.splitViewItem(for: pane)))
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
        XCTAssertEqual(project.paneState(nodeID: leftID, key: "chrome.minimize.edge"), "leading",
                       "the row the restore has to remove")

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
        XCTAssertEqual(project.paneState(nodeID: rightID, key: "chrome.zoomed"), "1",
                       "the row the second zoom has to remove")

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
        let override = try leaf(leftID, in: first).spacingOverride
        override.setOverride(spacing)
        // The steppers are continuous, so the write waits for the pause a held
        // arrow key never takes. In the app the popover closing ends the
        // gesture; here the read below is what ends it.
        override.flushPendingPersist()

        let restored = try leaf(leftID, in: try makeTree())

        XCTAssertTrue(restored.spacingOverride.isOverridden)
        XCTAssertEqual(restored.spacingOverride.resolved, spacing)
    }

    func testUsingTheDefaultAgainForgetsTheOverride() throws {
        let first = try makeTree()
        let left = try leaf(leftID, in: first)
        left.spacingOverride.setOverride(Spacing(uniform: 12))
        left.spacingOverride.flushPendingPersist()
        XCTAssertNotNil(project.paneState(nodeID: leftID, key: "chrome.spacing.override"),
                        "the row the reset has to remove")

        left.spacingOverride.reset()

        XCTAssertNil(project.paneState(nodeID: leftID, key: "chrome.spacing.override"))
        XCTAssertFalse(try leaf(leftID, in: try makeTree()).spacingOverride.isOverridden)
    }

    /// A row whose edge the tree no longer admits. The layout spec can change
    /// the axis a pane sits on between launches, and the pane restores its own
    /// rail off the row before the host ever looks at it — so a host that just
    /// declined the minimize would leave a pane holding its full share of the
    /// split with nothing but a rail in it, and no control able to undo that.
    ///
    /// `.top` in a horizontal split is that case: `resolvedEdge` refuses an
    /// edge off the parent's axis outright.
    func testAPersistedEdgeTheTreeNoLongerAdmitsGivesThePaneBack() throws {
        project.setPaneState(nodeID: leftID, key: "chrome.minimize.edge", value: PaneEdge.top.rawValue)

        let root = try makeTree()
        let left = try leaf(leftID, in: root)
        XCTAssertEqual(left.minimizedEdge, .top, "the pane drew its rail off the row, as it always does")

        root.applyPersistedPaneState()

        XCTAssertNil(left.minimizedEdge, "the host gave the pane back rather than leaving a stranded rail")
        let (_, _, item) = try splitItem(for: leftID, in: root)
        XCTAssertEqual(item.maximumThickness, NSSplitViewItem.unspecifiedDimension,
                       "and un-pinned its split item with it")
    }

    // MARK: - The entry point the app actually uses

    // Every restore test above calls `applyPersistedPaneState()` by hand, and
    // none of them would notice if `viewDidAppear()` stopped calling it — so
    // the one thing that makes any of this reach a user on window open would
    // be covered by nothing. `loadViewIfNeeded()` does not deliver appearance
    // callbacks; only a window on screen does. These three drive the override.

    /// Mounts a root the way the window controller mounts a tab, and orders the
    /// window front — which is what makes AppKit send `viewWillAppear` /
    /// `viewDidLayout` / `viewDidAppear` down the tree.
    private func appear(_ root: ComposableTabsViewController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = root
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        windows.append(window)
    }

    /// The whole feature, through the door the app opens: a tree that is only
    /// put on screen restores the *tree's* half of the pane state. Nothing here
    /// calls `applyPersistedPaneState()`; deleting the `viewDidAppear()`
    /// override fails this test and nothing else in the suite.
    func testAppearingOnScreenIsWhatRestoresTheTreesHalf() throws {
        let first = try makeTree()
        first.paneDidRequestMinimize(try leaf(leftID, in: first), to: .leading)

        let second = try makeTree()
        appear(second)

        let (pane, _, item) = try splitItem(for: leftID, in: second)
        XCTAssertEqual(item.maximumThickness, pane.minimizedThickness(for: .leading),
                       "appearing pinned the split item, with no help from the test")
    }

    /// `MultiTabbedViewController` re-mounts a tab's root every time it is
    /// selected, so a root gets `viewDidAppear()` again on every tab switch.
    /// The latch is what keeps the restore a one-time event.
    func testAppearingASecondTimeRestoresNothingAgain() throws {
        let first = try makeTree()
        first.paneDidRequestMinimize(try leaf(leftID, in: first), to: .leading)

        let second = try makeTree()
        appear(second)
        let (pane, owner, item) = try splitItem(for: leftID, in: second)
        XCTAssertEqual(item.maximumThickness, pane.minimizedThickness(for: .leading),
                       "the first appearance applied it")

        // Un-pin the item without touching the pane's persisted row, so a
        // second restore would be visible. This is the only mutation between
        // the two appearances.
        owner.restoreSizing(of: item)
        second.viewDidAppear()

        XCTAssertEqual(item.maximumThickness, NSSplitViewItem.unspecifiedDimension,
                       "the latch held: a re-appearance re-applies nothing")
    }

    /// A nested split appears too, and it must sit still. Pinning is a decision
    /// about the whole tab — two splits both making it would race over the
    /// zoom's collapses.
    func testANestedSplitAppearingRestoresNothing() throws {
        let first = try makeTree()
        first.paneDidRequestMinimize(try leaf(leftID, in: first), to: .leading)

        try installLayout()
        let nested = ComposableTabsViewController.make(from: node, project: project, isRoot: false)
        nested.loadViewIfNeeded()
        for pane in nested.allLeaves() { pane.loadViewIfNeeded() }

        nested.viewDidAppear()

        let (_, _, item) = try splitItem(for: leftID, in: nested)
        XCTAssertEqual(item.maximumThickness, NSSplitViewItem.unspecifiedDimension,
                       "only the root restores the tree's half")
    }

    /// A tab can hold one pane minimized *and another* zoomed, and a restore has
    /// to survive both at once. `paneDidRequestZoom` restores only the pane
    /// being zoomed, so a zoom on the *other* pane leaves the minimize row
    /// standing and the database keeps both — which makes
    /// `applyPersistedPaneState()` pin an item and then collapse it.
    ///
    /// `testAZoomedPaneComesBackZoomed` covers the zoom half windowless, where
    /// no constraint engine ever runs. This one puts a real window around the
    /// pair, so the suite's "no `Unable to simultaneously satisfy constraints`"
    /// bar speaks for a pinned-then-collapsed item too — the same class of bug
    /// the `restoreSizing(of:)` ordering turned out to be, and the one shape of
    /// it no window had ever been put around.
    func testAMinimizedPaneBesideAZoomedOneComesBackAsBoth() throws {
        let first = try makeTree()
        first.paneDidRequestMinimize(try leaf(leftID, in: first), to: .leading)
        first.paneDidRequestZoom(try leaf(rightID, in: first))
        XCTAssertEqual(project.paneState(nodeID: leftID, key: "chrome.minimize.edge"), "leading",
                       "zooming the other pane leaves this row standing")
        XCTAssertEqual(project.paneState(nodeID: rightID, key: "chrome.zoomed"), "1",
                       "and the zoom is stored beside it")

        let second = try makeTree()
        appear(second)

        let (left, _, leftItem) = try splitItem(for: leftID, in: second)
        XCTAssertEqual(left.minimizedEdge, .leading, "the minimized pane came back minimized")
        XCTAssertEqual(leftItem.maximumThickness, left.minimizedThickness(for: .leading),
                       "its item is pinned to the rail")
        XCTAssertTrue(try leaf(rightID, in: second).isZoomed, "and the zoomed pane came back zoomed")
        XCTAssertTrue(leftItem.isCollapsed, "with the pinned item collapsed under the zoom")
    }

    // MARK: - The other mount path: a root mounted as a tab

    // The placement of the restore in `viewDidAppear()` rests on `viewDidLayout`
    // running first, on *both* paths a root is mounted by. The tests above take
    // the first path, a root set as a window's `contentViewController`. These
    // two take the other — `MultiTabbedViewController.refreshCenterContent()`,
    // which adds a root into a container that is already on screen — where the
    // ordering is not obvious: nothing here is a window being shown, the root
    // is pinned in with constraints that defer its subtree's first real layout,
    // and AppKit sends `viewWillAppear` at the moment it is added.

    /// Mounts `root` the way a tab is mounted: into a `MultiTabbedViewController`
    /// that is already on screen. Unlike the window path, AppKit delivers
    /// `viewDidAppear` here on a later run-loop turn, so the caller has to let
    /// the loop turn before the appearance has happened.
    private func mountAsTab(_ root: NSViewController) {
        let tabs = MultiTabbedViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = tabs
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        windows.append(window)

        tabs.addTab(.init(title: "Tab 1", viewController: root), on: .top)
        window.contentView?.layoutSubtreeIfNeeded()
        for _ in 0..<5 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// The ordering the `viewDidAppear()` comment rests on, recorded on the tab
    /// path. A plain controller rather than a `ComposableTabsViewController`
    /// because that class is `final` and cannot be subclassed to record — and
    /// because the ordering being claimed is AppKit's, a property of how the
    /// container mounts its content, not of what is mounted.
    func testTheTabMountPathLaysOutBeforeItAppears() throws {
        let recorder = AppearanceOrderRecorder()

        mountAsTab(recorder)

        XCTAssertEqual(recorder.events, ["will-appear", "layout", "appear"],
                       "a tab is laid out before it is told it appeared")
    }

    /// And the consequence, for the real controller on the same path: the
    /// restore runs there, and the capture it goes through reads an arrangement
    /// that has actually been laid out.
    ///
    /// The second assertion is what says "laid out". `captureThicknessFractions()`
    /// writes each child's share of the split from the geometry on screen, so
    /// after a capture of a real arrangement the shares tile the split and sum
    /// to one (bar the divider). Before the first layout pass they do not:
    /// every view still holds the frame `loadView` gave it, the children
    /// overflow their parent, and the same capture yields 0.6 and 0.6. So a
    /// restore that ran ahead of layout — which is exactly what this placement
    /// exists to prevent, because the values it writes then replace the
    /// persisted divider positions — would fail here.
    func testARootMountedAsATabRestoresOnlyOnceItIsLaidOut() throws {
        let first = try makeTree()
        first.paneDidRequestMinimize(try leaf(leftID, in: first), to: .leading)

        let second = try makeTree()
        mountAsTab(second)

        let (pane, _, item) = try splitItem(for: leftID, in: second)
        XCTAssertEqual(item.maximumThickness, pane.minimizedThickness(for: .leading),
                       "appearing as a tab restored the tree's half")
        let shares = try second.layoutChildren.map { try XCTUnwrap($0.thicknessFraction) }
        XCTAssertEqual(shares.reduce(0, +), 1.0, accuracy: 0.02,
                       "the capture read a laid-out arrangement, not loadView's placeholder frames")
    }

    /// Closing a pane must not leave its rows behind. The database already
    /// prunes on save; this is the test that says so from up here.
    func testAClosedPaneTakesItsStateWithIt() throws {
        let root = try makeTree()
        let left = try leaf(leftID, in: root)
        root.paneDidRequestMinimize(left, to: .leading)
        // Without this the test cannot tell a prune from a write that never
        // landed — and a write that never lands is exactly what an
        // unregistered repo produces, silently, which is the bug this whole
        // fixture had to be hardened against.
        XCTAssertEqual(project.paneState(nodeID: leftID, key: "chrome.minimize.edge"), "leading",
                       "the row the close has to take with it")

        root.paneDidRequestClose(left)
        project.persistTabs(
            [TabRecord(title: "Tab 1", root: root.snapshotNode())],
            activeTabID: nil,
            enabledEdges: [.top]
        )

        XCTAssertNil(project.paneState(nodeID: leftID, key: "chrome.minimize.edge"))
    }
}

/// Records the appearance and layout callbacks AppKit delivers, in order.
/// Consecutive layout passes collapse into one entry — the question is which
/// side of `viewDidAppear` the first one falls on.
private final class AppearanceOrderRecorder: NSViewController {
    private(set) var events: [String] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        events.append("will-appear")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if events.last != "layout" { events.append("layout") }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        events.append("appear")
    }
}
