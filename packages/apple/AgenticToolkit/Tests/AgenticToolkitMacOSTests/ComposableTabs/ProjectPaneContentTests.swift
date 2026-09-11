import XCTest
import AppKit
import AgenticToolkitMacOS

/// What an app gets to say about a project's panes: which views exist, how
/// wide each one wants to be, and what a fresh tab starts out holding.
///
/// A registry is per-layout rather than process-global now, so each test builds
/// its own and hands it to the project. Only `ComposableTabsLayout.install` is
/// still global, so only that is undone in `tearDown`.
@MainActor
final class ProjectPaneContentTests: XCTestCase {

    private let sidebar = ComposableTabsViewID("test.sidebar")
    private let notes = ComposableTabsViewID("test.notes")
    private let terminal = ComposableTabsViewID("test.terminal")

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

    nonisolated override func tearDown() {
        // `install` is nonisolated, which is the whole point of it: the
        // project's writer reads the installed layout off the main actor.
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    private func leafViewIDs(in node: LayoutNode) -> [ComposableTabsViewID] {
        switch node.kind {
        case .leaf(let viewID, _):
            return [viewID]
        case .split(_, let first, let second):
            return leafViewIDs(in: first) + leafViewIDs(in: second)
        }
    }

    private func axis(of node: LayoutNode) -> ComposableTabsAxis? {
        if case .split(let axis, _, _) = node.kind { return axis }
        return nil
    }

    // MARK: - Blueprint

    func testDefaultBlueprintIsTwoPlaceholdersSideBySide() {
        let layout = ComposableTabsLayout.makeTabLayout()
        XCTAssertEqual(axis(of: layout), .horizontal)
        XCTAssertEqual(leafViewIDs(in: layout), [.placeholder, .placeholder])
    }

    func testInstalledLayoutReplacesTheDefaultBlueprint() throws {
        ComposableTabsLayout.install(try makeLayout(spec: .split(
            axis: .vertical,
            children: [.pane(notes), .pane(terminal)],
            allows: [.init(notes), .unbounded(terminal)]
        )))
        let layout = ComposableTabsLayout.makeTabLayout()
        XCTAssertEqual(axis(of: layout), .vertical)
        XCTAssertEqual(leafViewIDs(in: layout), [notes, terminal])
    }

    func testClearingTheInstalledLayoutRestoresTheDefaultBlueprint() throws {
        ComposableTabsLayout.install(try makeLayout(spec: .pane(notes, allows: [.init(notes)])))
        ComposableTabsLayout.install(nil)
        XCTAssertEqual(
            leafViewIDs(in: ComposableTabsLayout.makeTabLayout()),
            [.placeholder, .placeholder]
        )
    }

    /// The project's writer can run off the main actor, and it seeds new
    /// packages from the blueprint — so reading it from another thread has to
    /// work, not just happen to.
    func testBlueprintIsReadableOffTheMainActor() async throws {
        ComposableTabsLayout.install(try makeLayout(spec: .pane(notes, allows: [.init(notes)])))
        let tree = await Task.detached {
            ComposableTabsLayout.makeTabLayout()
        }.value
        XCTAssertEqual(leafViewIDs(in: tree), [notes])
    }

    // MARK: - Pane descriptors

    func testUnregisteredViewGetsTheUnknownDescriptor() {
        let registry = ComposableTabsViewRegistry()
        let descriptor = registry.descriptor(for: "test.never-registered")
        XCTAssertEqual(
            descriptor.minimumThickness,
            ComposableTabsViewDescriptor.unknown.minimumThickness
        )
        XCTAssertNil(descriptor.preferredThicknessFraction)
    }

    func testRegisteredDescriptorReachesTheSplitViewItem() throws {
        try installTestLayout()

        let root = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            first: makeLeaf(sidebar),
            second: makeLeaf(.placeholder),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        _ = root.view

        XCTAssertEqual(root.splitViewItems.first?.minimumThickness, 175)
        XCTAssertEqual(root.splitViewItems.first?.preferredThicknessFraction, 0.2)

        // The placeholder keeps the default thickness rather than inheriting
        // its neighbour's.
        XCTAssertEqual(root.splitViewItems.last?.minimumThickness, 120)
    }

    /// A nested split is not "some view controller with default metrics" — it is
    /// as wide as what it holds. Stacked children are as wide as the widest one.
    func testANestedSplitReportsTheWidestOfItsStackedChildren() throws {
        try installTestLayout()

        let inner = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .vertical,
            first: makeLeaf(notes),        // 320
            second: makeLeaf(terminal),    // 400
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: false
        )
        let root = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            first: makeLeaf(sidebar),
            second: inner,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        _ = root.view

        XCTAssertEqual(root.splitViewItems.last?.minimumThickness, 400)
    }

    /// Children arranged along the same axis as the parent stack up, so the
    /// split needs room for all of them at once.
    func testANestedSplitSumsChildrenLaidOutAlongTheSameAxis() throws {
        try installTestLayout()

        let inner = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            first: makeLeaf(notes),        // 320
            second: makeLeaf(terminal),    // 400
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: false
        )
        let root = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            first: makeLeaf(.placeholder),
            second: inner,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        _ = root.view

        XCTAssertEqual(root.splitViewItems.last?.minimumThickness, 720)
    }

    /// A pane that named a fraction holds the width it was given when the window
    /// grows; without a higher holding priority AppKit spreads the growth evenly
    /// and a 22% sidebar ends up owning half the window.
    func testAPaneWithAPreferredFractionResistsResizeMoreThanItsNeighbours() throws {
        try installTestLayout()

        let root = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            first: makeLeaf(sidebar),
            second: makeLeaf(notes),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        _ = root.view

        let sidebarPriority = root.splitViewItems.first?.holdingPriority.rawValue ?? 0
        let contentPriority = root.splitViewItems.last?.holdingPriority.rawValue ?? 0
        XCTAssertGreaterThan(sidebarPriority, contentPriority)
    }

    // MARK: - Content lifecycle

    func testContentIsAdoptedAsAChildViewController() throws {
        try installTeardownSpyLayout()
        let leaf = makeLeaf(notes)
        _ = leaf.view

        let content = leaf.contentViewController
        XCTAssertTrue(content is TeardownSpyViewController)
        // Containment is what keeps the content alive and gets it appearance
        // callbacks; a bare view would have neither.
        XCTAssertIdentical(content?.parent, leaf)
        XCTAssertEqual(leaf.children.count, 1)
    }

    func testRemovingAPaneTearsDownItsContent() throws {
        try installTeardownSpyLayout()
        let doomed = makeLeaf(terminal)
        let survivor = makeLeaf(terminal)
        let root = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            first: doomed,
            second: survivor,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        _ = root.view

        let spy = doomed.contentViewController as? TeardownSpyViewController
        XCTAssertEqual(spy?.teardownCount, 0)
        root.remove(doomed)
        XCTAssertEqual(spy?.teardownCount, 1)

        // The surviving pane keeps its content running.
        let survivorSpy = survivor.contentViewController as? TeardownSpyViewController
        XCTAssertEqual(survivorSpy?.teardownCount, 0)
    }

    func testTheLastPaneIsNotTornDownBecauseItIsNotRemoved() throws {
        try installTeardownSpyLayout()
        let only = makeLeaf(terminal)
        let root = ComposableTabsViewController(
            nodeID: UUID(),
            axis: .horizontal,
            children: [only],
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        _ = root.view

        root.remove(only)
        let spy = only.contentViewController as? TeardownSpyViewController
        XCTAssertEqual(spy?.teardownCount, 0)
    }

    // MARK: - Tab-level teardown

    /// `reloadTabs()` discards whole split trees without going through
    /// `remove(_:)`, which until now was the framework's only call site for
    /// `paneWillBeRemoved()`. Every pane on a discarded tab kept whatever it
    /// owned — a shell, an FSEvents stream — with nothing left able to reap it,
    /// and the reconcile path runs this on every project open.
    func testReloadingTabsTearsDownEveryPaneItDiscards() throws {
        try installTeardownSpyLayout()
        let window = ComposableTabsWindowController(project: project)
        defer { window.close() }
        let discarded = spies(in: window.allPanes())
        XCTAssertFalse(discarded.isEmpty)
        XCTAssertTrue(discarded.allSatisfy { $0.teardownCount == 0 })

        window.reloadTabs()

        XCTAssertTrue(
            discarded.allSatisfy { $0.teardownCount == 1 },
            "a tab thrown away by reloadTabs() must tell its panes they are being discarded"
        )
        // The replacements are live, not collaterally torn down.
        XCTAssertTrue(spies(in: window.allPanes()).allSatisfy { $0.teardownCount == 0 })
    }

    /// The same gap on the other path that drops a whole tree: closing a tab.
    func testClosingATabGroupTearsDownItsPanesAndLeavesTheRestRunning() throws {
        try installTeardownSpyLayout()
        let records = try seedTwoStoredTabGroups()
        let window = ComposableTabsWindowController(project: project)
        defer { window.close() }
        let host = try XCTUnwrap(window.contentViewController as? WindowFooterContentViewController)
        let tabbed = try XCTUnwrap(host.contentViewController as? MultiTabbedViewController)
        let doomed = spies(in: window.panes(inTab: records[0].groupID.uuidString))
        let survivors = spies(in: window.panes(inTab: records[1].groupID.uuidString))
        XCTAssertFalse(doomed.isEmpty)
        XCTAssertFalse(survivors.isEmpty)

        window.multiTabbedViewController(tabbed, didRequestCloseTab: records[0].id, on: .top)

        XCTAssertTrue(doomed.allSatisfy { $0.teardownCount == 1 })
        XCTAssertTrue(survivors.allSatisfy { $0.teardownCount == 0 })
    }

    // MARK: - Helpers

    /// The teardown spies behind `panes`, with each pane's view forced to load
    /// first: a pane nobody displayed has no content at all, which would let
    /// these tests pass for the wrong reason.
    private func spies(in panes: [ComposableTabsPaneViewController]) -> [TeardownSpyViewController] {
        panes.compactMap { pane in
            _ = pane.view
            return pane.contentViewController as? TeardownSpyViewController
        }
    }

    /// Two stored tab groups, because `didRequestCloseTab` refuses to close the
    /// last one. The repo row has to exist first — tab rows reference it, and
    /// `persistTabs` only logs the failure it would otherwise hit.
    @discardableResult
    private func seedTwoStoredTabGroups() throws -> [TabRecord] {
        try project.database.insert(project.repo)
        let records = ["alpha", "beta"].map { title in
            TabRecord(edge: .top, title: title, root: project.layout.blueprint())
        }
        project.persistTabs(records, activeTabID: records.first?.id, enabledEdges: [.top])
        return records
    }

    /// A sidebar that names a fraction, plus two views with distinct minimums —
    /// the three shapes the metrics tests need.
    private func makeTestRegistry(
        content: ComposableTabsViewRegistry.Factory? = nil
    ) -> ComposableTabsViewRegistry {
        let factory: ComposableTabsViewRegistry.Factory = content ?? { context in
            PlaceholderPaneViewController(paneNumber: context.paneNumber)
        }
        let registry = ComposableTabsViewRegistry()
        registry.register(sidebar, descriptor: .init(
            displayName: "Sidebar",
            preferredAxis: .horizontal,
            minimumThickness: 175,
            preferredThicknessFraction: 0.2
        ), factory: factory)
        registry.register(notes, descriptor: .init(
            displayName: "Notes", preferredAxis: .vertical, minimumThickness: 320
        ), factory: factory)
        registry.register(terminal, descriptor: .init(
            displayName: "Terminal", preferredAxis: .vertical, minimumThickness: 400
        ), factory: factory)
        return registry
    }

    private func makeLayout(
        spec: ComposableTabLayoutSpec,
        registry: ComposableTabsViewRegistry? = nil
    ) throws -> ComposableTabsLayout {
        try ComposableTabsLayout(registry: registry ?? makeTestRegistry(), spec: spec)
    }

    private var testSpec: ComposableTabLayoutSpec {
        .split(
            axis: .horizontal,
            children: [
                .pane(sidebar),
                .split(axis: .vertical, children: [.pane(notes), .pane(terminal)])
            ],
            allows: [
                .init(sidebar), .init(notes), .unbounded(terminal), .unbounded(.placeholder)
            ]
        )
    }

    private func installTestLayout() throws {
        project.layout = try makeLayout(spec: testSpec)
    }

    private func installTeardownSpyLayout() throws {
        project.layout = try makeLayout(
            spec: testSpec,
            registry: makeTestRegistry { _ in TeardownSpyViewController() }
        )
    }

    private func makeLeaf(_ viewID: ComposableTabsViewID) -> ComposableTabsPaneViewController {
        ComposableTabsPaneViewController(
            nodeID: UUID(),
            paneNumber: project.allocatePaneNumber(),
            viewID: viewID,
            project: project,
            workingDirectory: project.directoryURL
        )
    }
}

/// Stands in for pane content that owns something worth releasing — a shell, an
/// FSEvents stream — and counts how many times the pane told it to let go.
@MainActor
private final class TeardownSpyViewController: NSViewController, PaneContentTeardown {

    private(set) var teardownCount = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }

    func paneContentWillBeDiscarded() {
        teardownCount += 1
    }
}
