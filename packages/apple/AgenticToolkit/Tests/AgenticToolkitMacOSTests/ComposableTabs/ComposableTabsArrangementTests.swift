import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// One arrangement per project, worn by every tab in it.
///
/// A tab is a *place* — a checkout, an edge — and the panes in it belong to the
/// project, so arranging them in the tab that happens to be in front arranges
/// them everywhere. These tests drive the production paths a user does: a real
/// split inside a live window, a real new tab, and the reload that follows.
@MainActor
final class ComposableTabsArrangementTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("arrangement-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - A split in one tab

    func testSplittingAPaneInOneTabRearrangesEveryTab() throws {
        let project = try makeProject()
        let records = try seedTwoTabs(in: project)
        let window = ComposableTabsWindowController(project: project)
        defer { window.close() }
        window.showWindow(nil)

        let front = try XCTUnwrap(splitTree(for: records[0], in: window))
        front.split(try XCTUnwrap(front.firstLeaf()), adding: .placeholder, direction: .right)

        let stored = try XCTUnwrap(project.storedTabs()).tabs
        XCTAssertEqual(stored.count, 2)
        let shapes = Set(stored.map { shape(of: $0.root) })
        XCTAssertEqual(shapes.count, 1, "every tab in the project must be arranged the same way")
        // The blueprint's two panes, one of them split in two: three leaves
        // under two splits, in the tab that was split and in the one that
        // followed it.
        XCTAssertEqual(stored.map { ids(of: $0.root).count }, [5, 5])
    }

    /// The shape travels; the ids stay. Two tabs holding one node id cannot
    /// both be saved — `layout_nodes.id` is a primary key — and a pane is found
    /// again across a rebuild by its node id, so a tab handed another tab's ids
    /// would throw away every pane it had.
    func testTheTabsThatFollowKeepTheirOwnIDs() throws {
        let project = try makeProject()
        let records = try seedTwoTabs(in: project)
        let window = ComposableTabsWindowController(project: project)
        defer { window.close() }
        window.showWindow(nil)

        let front = try XCTUnwrap(splitTree(for: records[0], in: window))
        front.split(try XCTUnwrap(front.firstLeaf()), adding: .placeholder, direction: .right)

        let stored = try XCTUnwrap(project.storedTabs()).tabs
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, ids(of: $0.root)) })
        let first = try XCTUnwrap(byID[records[0].id])
        let second = try XCTUnwrap(byID[records[1].id])
        XCTAssertTrue(Set(first).isDisjoint(with: Set(second)))
    }

    /// What a follower is spared: being rebuilt from storage. The panes it was
    /// already showing are carried into the new arrangement, so a terminal on a
    /// tab nobody is looking at keeps its shell when another tab is split.
    func testATabThatFollowsCarriesItsLivePanesAcross() throws {
        let project = try makeProject()
        let records = try seedTwoTabs(in: project)
        let window = ComposableTabsWindowController(project: project)
        defer { window.close() }
        window.showWindow(nil)

        let follower = records[1].groupID.uuidString
        let before = window.panes(inTab: follower)
        XCTAssertEqual(before.count, 2)

        let front = try XCTUnwrap(splitTree(for: records[0], in: window))
        front.split(try XCTUnwrap(front.firstLeaf()), adding: .placeholder, direction: .right)

        let after = window.panes(inTab: follower)
        XCTAssertEqual(after.count, 3, "the follower takes the new shape")
        for pane in before {
            XCTAssertTrue(after.contains { $0 === pane }, "a pane that merely moved must not be rebuilt")
        }
    }

    // MARK: - A tab that does not exist yet

    func testANewTabOpensInTheArrangementTheOthersAreIn() throws {
        let project = try makeProject()
        let records = try seedTwoTabs(in: project)
        let window = ComposableTabsWindowController(project: project)
        defer { window.close() }
        window.showWindow(nil)

        let front = try XCTUnwrap(splitTree(for: records[0], in: window))
        front.split(try XCTUnwrap(front.firstLeaf()), adding: .placeholder, direction: .right)
        window.multiTabbedViewControllerNeedsNewTab(try XCTUnwrap(multiTabbed(in: window)))

        let stored = try XCTUnwrap(project.storedTabs()).tabs
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(Set(stored.map { shape(of: $0.root) }).count, 1)
        XCTAssertEqual(Set(stored.flatMap { ids(of: $0.root) }).count, 15, "no tab may share a node id")
    }

    // MARK: - Sizes, without a rebuild

    /// A divider drag posts a change per mouse event, so the tabs that follow
    /// take the new sizes where they stand: same panes, new fractions.
    func testATabTakesNewSizesWithoutGivingUpItsPanes() throws {
        let project = try makeProject()
        let arrangement = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: .placeholder, thicknessFraction: 0.5),
            second: .leaf(contentType: .placeholder, thicknessFraction: 0.5)
        )
        let follower = ComposableTabsViewController.make(
            from: arrangement.inFreshIDs(),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        let panes = follower.allLeaves()

        let dragged = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: .placeholder, thicknessFraction: 0.2),
            second: .leaf(contentType: .placeholder, thicknessFraction: 0.8)
        )
        follower.applySizes(from: follower.snapshotNode().reshaped(toMatch: dragged))

        XCTAssertEqual(fractions(of: follower.snapshotNode()), [0.2, 0.8])
        XCTAssertEqual(
            follower.allLeaves().map(ObjectIdentifier.init),
            panes.map(ObjectIdentifier.init),
            "taking a size must not cost the tab its panes"
        )
    }

    // MARK: - Reload

    /// Tabs stored before one arrangement was the rule — and any that drifted
    /// since — come back in step with the tab that comes up in front.
    func testTabsStoredInDifferentShapesComeBackInOne() throws {
        let project = try makeProject()
        let wide = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: .placeholder),
            second: .split(
                orientation: .vertical,
                first: .leaf(contentType: .placeholder),
                second: .leaf(contentType: .placeholder)
            )
        )
        let narrow = LayoutNode.leaf(contentType: .placeholder)
        let first = TabRecord(edge: .top, title: "alpha", root: wide)
        let second = TabRecord(edge: .top, title: "beta", root: narrow)
        project.persistTabs([first, second], activeTabID: first.id, enabledEdges: [.top])

        let reloaded = ProjectWorkspace(repo: project.repo, database: project.database).initialTabs()

        XCTAssertEqual(Set(reloaded.tabs.map { shape(of: $0.root) }).count, 1)
        XCTAssertEqual(Set(reloaded.tabs.flatMap { ids(of: $0.root) }).count, 10)
    }

    // MARK: - Helpers

    private func makeProject() throws -> ProjectWorkspace {
        let database = try ProjectDatabase(path: tempRoot.appendingPathComponent("Test.db").path)
        let repo = GitRepo(path: tempRoot.path, name: "Test")
        try database.insert(repo)
        return ProjectWorkspace(repo: repo, database: database)
    }

    /// Two tab groups on one edge, each starting from the default blueprint —
    /// the state a project was in before an arrangement was shared at all.
    @discardableResult
    private func seedTwoTabs(in project: ProjectWorkspace) throws -> [TabRecord] {
        let records = ["alpha", "beta"].map { title in
            TabRecord(edge: .top, title: title, root: project.layout.blueprint())
        }
        project.persistTabs(records, activeTabID: records[0].id, enabledEdges: [.top])
        return records
    }

    /// The tab controller the window wraps, found the way a test has to find
    /// it: by walking down from the window's content, since the controller
    /// keeps it to itself.
    private func multiTabbed(in window: ComposableTabsWindowController) -> MultiTabbedViewController? {
        guard let content = window.window?.contentViewController else { return nil }
        return Self.firstTabController(under: content)
    }

    private static func firstTabController(under controller: NSViewController) -> MultiTabbedViewController? {
        for child in controller.children {
            if let tabbed = child as? MultiTabbedViewController { return tabbed }
            if let found = firstTabController(under: child) { return found }
        }
        return nil
    }

    /// The root of one tab's live split tree, reached the way anything outside
    /// the window controller has to: through a pane it holds.
    private func splitTree(
        for record: TabRecord, in window: ComposableTabsWindowController
    ) -> ComposableTabsViewController? {
        let panes = window.panes(inTab: record.groupID.uuidString)
        return (panes.first?.host as? ComposableTabsViewController)?.rootSplit()
    }

    /// What a tree *is*, with the ids left out — the half that is shared.
    private func shape(of node: LayoutNode) -> String {
        switch node.kind {
        case .split(let orientation, let first, let second):
            return "(\(orientation) \(shape(of: first)) \(shape(of: second)))"
        case .leaf(let contentType, _):
            return contentType.rawValue
        }
    }

    private func ids(of node: LayoutNode) -> [UUID] {
        switch node.kind {
        case .split(_, let first, let second):
            return [node.id] + ids(of: first) + ids(of: second)
        case .leaf:
            return [node.id]
        }
    }

    private func fractions(of node: LayoutNode) -> [Double?] {
        switch node.kind {
        case .split(_, let first, let second):
            return fractions(of: first) + fractions(of: second)
        case .leaf:
            return [node.thicknessFraction]
        }
    }
}
