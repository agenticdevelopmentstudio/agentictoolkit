import XCTest
import AgenticToolkitMacOS

/// The window arrangement half of the registry: what a project opens with, and
/// the guarantee that two projects open at once cannot overwrite each other.
@MainActor
final class ProjectDatabaseLayoutTests: XCTestCase {

    private var tempRoot: URL!
    private let editor = ComposableTabsViewID("test.layout.editor")
    private let terminal = ComposableTabsViewID("test.layout.terminal")

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-layout-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    /// A project nobody has opened yet has no tabs and one tab bar, on top —
    /// not an error and not an empty edge list.
    func testAProjectThatWasNeverOpenedLoadsTheDefaultArrangement() throws {
        let (database, repo) = try makeRegisteredRepo()
        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertTrue(loaded.tabs.isEmpty)
        XCTAssertNil(loaded.activeTabID)
        XCTAssertEqual(loaded.enabledEdges, [.top])
    }

    func testTabsRoundTripWithTheirTreesOrderAndActiveTab() throws {
        let (database, repo) = try makeRegisteredRepo()
        let split = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor, paneLabel: "Editor"),
            second: .leaf(contentType: terminal)
        )
        let first = TabRecord(edge: .top, title: "Code", root: split)
        let second = TabRecord(edge: .left, title: "Notes", root: .leaf(contentType: editor))

        try database.saveTabs([first, second], activeTabID: second.id,
                              enabledEdges: [.top, .left], repoID: repo.id)

        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertEqual(loaded.tabs.map(\.title), ["Code", "Notes"])
        XCTAssertEqual(loaded.tabs.map(\.edge), [.top, .left])
        XCTAssertEqual(loaded.activeTabID, second.id)
        XCTAssertEqual(loaded.enabledEdges, [.top, .left])
        XCTAssertEqual(Self.shape(of: loaded.tabs[0].root),
                       "split(horizontal, leaf(test.layout.editor), leaf(test.layout.terminal))")
        XCTAssertEqual(Self.shape(of: loaded.tabs[1].root), "leaf(test.layout.editor)")
    }

    /// The pane label is what a pane is called in *this* arrangement, so it has
    /// to survive the round trip alongside the content type.
    func testPaneLabelsAndFocusSurviveTheRoundTrip() throws {
        let (database, repo) = try makeRegisteredRepo()
        let leaf = LayoutNode.leaf(contentType: editor, paneLabel: "Left Pane")
        let tab = TabRecord(title: "Code", root: leaf, focusedNodeID: leaf.id)
        try database.saveTabs([tab], activeTabID: tab.id, repoID: repo.id)

        let loaded = try XCTUnwrap(database.loadTabs(repoID: repo.id).tabs.first)
        XCTAssertEqual(loaded.focusedNodeID, leaf.id)
        guard case .leaf(let contentType, let paneLabel) = loaded.root.kind else {
            return XCTFail("the stored root is a leaf")
        }
        XCTAssertEqual(contentType, editor)
        XCTAssertEqual(paneLabel, "Left Pane")
    }

    /// Tabs sharing a group id are one project-level tab spread across edges;
    /// losing the grouping would split them into unrelated tabs on reload.
    func testTabGroupsSurviveTheRoundTrip() throws {
        let (database, repo) = try makeRegisteredRepo()
        let group = UUID()
        let top = TabRecord(groupID: group, edge: .top, title: "Code", root: .leaf(contentType: editor))
        let bottom = TabRecord(groupID: group, edge: .bottom, title: "Code",
                               root: .leaf(contentType: terminal))
        try database.saveTabs([top, bottom], activeTabID: top.id,
                              enabledEdges: [.top, .bottom], repoID: repo.id)

        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertEqual(Set(loaded.tabs.map(\.groupID)), [group])
    }

    /// Saving is a whole-arrangement replace, so a removed tab has to be gone
    /// rather than merged with what was there before.
    func testSavingReplacesTheWholeArrangement() throws {
        let (database, repo) = try makeRegisteredRepo()
        let old = TabRecord(title: "Old", root: .leaf(contentType: editor))
        try database.saveTabs([old], activeTabID: old.id, repoID: repo.id)

        let new = TabRecord(title: "New", root: .leaf(contentType: terminal))
        try database.saveTabs([new], activeTabID: new.id, repoID: repo.id)

        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertEqual(loaded.tabs.map(\.title), ["New"])
        XCTAssertEqual(loaded.activeTabID, new.id)
    }

    /// An active tab that is not in the list is not an active tab. Storing it
    /// anyway would leave the window pointing at a tab it cannot show.
    func testAnActiveTabIDThatNamesNoTabIsDropped() throws {
        let (database, repo) = try makeRegisteredRepo()
        let tab = TabRecord(title: "Code", root: .leaf(contentType: editor))
        try database.saveTabs([tab], activeTabID: UUID(), enabledEdges: [.right], repoID: repo.id)

        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertNil(loaded.activeTabID)
        XCTAssertEqual(loaded.enabledEdges, [.right],
                       "the state row is still written so the edges survive")
    }

    func testTwoProjectsKeepSeparateArrangements() throws {
        let database = try makeDatabase()
        let alpha = try registerRepo(in: database, path: "/tmp/alpha", name: "alpha")
        let beta = try registerRepo(in: database, path: "/tmp/beta", name: "beta")

        let alphaTab = TabRecord(title: "Alpha", root: .leaf(contentType: editor))
        let betaTab = TabRecord(title: "Beta", root: .leaf(contentType: terminal))
        try database.saveTabs([alphaTab], activeTabID: alphaTab.id, repoID: alpha.id)
        try database.saveTabs([betaTab], activeTabID: betaTab.id,
                              enabledEdges: [.bottom], repoID: beta.id)

        XCTAssertEqual(try database.loadTabs(repoID: alpha.id).tabs.map(\.title), ["Alpha"])
        XCTAssertEqual(try database.loadTabs(repoID: alpha.id).enabledEdges, [.top])
        XCTAssertEqual(try database.loadTabs(repoID: beta.id).tabs.map(\.title), ["Beta"])
        XCTAssertEqual(try database.loadTabs(repoID: beta.id).enabledEdges, [.bottom])
    }

    // MARK: - Pane sizes

    /// The sizes are the whole point of the arrangement: a tree that comes back
    /// with the right shape and even panes has still lost what the user did.
    func testPaneSizesSurviveTheRoundTrip() throws {
        let (database, repo) = try makeRegisteredRepo()
        let root = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: editor, thicknessFraction: 0.28),
            second: .split(
                orientation: .vertical,
                first: .leaf(contentType: terminal, thicknessFraction: 0.7),
                second: .leaf(contentType: editor, thicknessFraction: 0.3),
                thicknessFraction: 0.72
            )
        )
        let tab = TabRecord(title: "Code", root: root)
        try database.saveTabs([tab], activeTabID: tab.id, repoID: repo.id)

        let loaded = try XCTUnwrap(database.loadTabs(repoID: repo.id).tabs.first).root
        guard case .split(_, let left, let right) = loaded.kind,
              case .split(_, let top, let bottom) = right.kind else {
            return XCTFail("the stored tree keeps its shape")
        }
        XCTAssertEqual(try XCTUnwrap(left.thicknessFraction), 0.28, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(right.thicknessFraction), 0.72, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(top.thicknessFraction), 0.7, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(bottom.thicknessFraction), 0.3, accuracy: 0.0001)
    }

    /// A pane nobody has sized is a real state, and it has to survive as one:
    /// storing a zero would pin the divider to the edge on the next launch.
    func testAnUnsizedPaneComesBackUnsizedRatherThanZero() throws {
        let (database, repo) = try makeRegisteredRepo()
        let tab = TabRecord(title: "Code", root: .leaf(contentType: editor))
        try database.saveTabs([tab], activeTabID: tab.id, repoID: repo.id)

        let loaded = try XCTUnwrap(database.loadTabs(repoID: repo.id).tabs.first).root
        XCTAssertNil(loaded.thicknessFraction)
    }

    // MARK: - Pane state

    func testPaneStateRoundTripsAndIsScopedToItsPane() throws {
        let (database, repo) = try makeRegisteredRepo()
        let left = UUID()
        let right = UUID()
        XCTAssertNil(try database.paneState(repoID: repo.id, nodeID: left, key: "expanded"))

        try database.setPaneState(repoID: repo.id, nodeID: left, key: "expanded", value: "[\"/tmp\"]")
        try database.setPaneState(repoID: repo.id, nodeID: right, key: "expanded", value: "[\"/var\"]")

        XCTAssertEqual(try database.paneState(repoID: repo.id, nodeID: left, key: "expanded"), "[\"/tmp\"]")
        XCTAssertEqual(try database.paneState(repoID: repo.id, nodeID: right, key: "expanded"), "[\"/var\"]")

        try database.setPaneState(repoID: repo.id, nodeID: left, key: "expanded", value: "[]")
        XCTAssertEqual(try database.paneState(repoID: repo.id, nodeID: left, key: "expanded"), "[]",
                       "a second write replaces rather than duplicates")

        try database.setPaneState(repoID: repo.id, nodeID: left, key: "expanded", value: nil)
        XCTAssertNil(try database.paneState(repoID: repo.id, nodeID: left, key: "expanded"))
    }

    /// `saveTabs` rewrites every layout row, so pane state has to be kept by id
    /// rather than by foreign key — and pruned by the same pass, or a window
    /// accumulates the state of every pane it has ever closed.
    func testSavingTabsKeepsTheStateOfLivePanesAndDropsTheRest() throws {
        let (database, repo) = try makeRegisteredRepo()
        let kept = LayoutNode.leaf(contentType: editor)
        let closed = LayoutNode.leaf(contentType: terminal)
        let tab = TabRecord(title: "Code", root: .split(
            orientation: .horizontal, first: kept, second: closed))
        try database.saveTabs([tab], activeTabID: tab.id, repoID: repo.id)

        try database.setPaneState(repoID: repo.id, nodeID: kept.id, key: "selected", value: "/tmp/a.swift")
        try database.setPaneState(repoID: repo.id, nodeID: closed.id, key: "selected", value: "/tmp/b.swift")

        // The second pane is closed: the survivor is promoted to the root.
        let after = TabRecord(id: tab.id, title: "Code", root: kept)
        try database.saveTabs([after], activeTabID: after.id, repoID: repo.id)

        XCTAssertEqual(try database.paneState(repoID: repo.id, nodeID: kept.id, key: "selected"),
                       "/tmp/a.swift")
        XCTAssertNil(try database.paneState(repoID: repo.id, nodeID: closed.id, key: "selected"))
    }

    /// A leaf that keeps its id but changes its content is a different pane in
    /// the same place, and the state the old content wrote means nothing to the
    /// new one. The node-id sweep cannot see this: the id is still there.
    ///
    /// `ComposableTabLayoutSpec.reconcile(_:)` is the live case — it demotes a
    /// leaf naming a view this build no longer allows to a placeholder, keeping
    /// the node so the *shape* of the user's layout survives. Without this, the
    /// demoted leaf carries the old pane's state forever, and hands it back if
    /// that content ever returns to the leaf.
    func testSavingTabsDropsTheStateOfALeafWhoseContentChanged() throws {
        let (database, repo) = try makeRegisteredRepo()
        let leaf = LayoutNode.leaf(contentType: editor)
        let tab = TabRecord(title: "Code", root: leaf)
        try database.saveTabs([tab], activeTabID: tab.id, repoID: repo.id)
        try database.setPaneState(repoID: repo.id, nodeID: leaf.id, key: "selected", value: "/tmp/a.swift")

        let demoted = TabRecord(id: tab.id, title: "Code",
                                root: .leaf(id: leaf.id, contentType: .placeholder))
        try database.saveTabs([demoted], activeTabID: demoted.id, repoID: repo.id)

        XCTAssertNil(try database.paneState(repoID: repo.id, nodeID: leaf.id, key: "selected"))
    }

    /// The other half of the rule above: a leaf whose content is unchanged keeps
    /// its state even when everything around it moves. Sizing, labelling and
    /// re-rooting a pane are not content changes.
    func testSavingTabsKeepsTheStateOfALeafThatOnlyMoved() throws {
        let (database, repo) = try makeRegisteredRepo()
        let leaf = LayoutNode.leaf(contentType: editor)
        let tab = TabRecord(title: "Code", root: leaf)
        try database.saveTabs([tab], activeTabID: tab.id, repoID: repo.id)
        try database.setPaneState(repoID: repo.id, nodeID: leaf.id, key: "selected", value: "/tmp/a.swift")

        let moved = TabRecord(id: tab.id, title: "Code", root: .split(
            orientation: .horizontal,
            first: .leaf(contentType: terminal),
            second: .leaf(id: leaf.id, contentType: editor, paneLabel: "Editor", thicknessFraction: 0.25)
        ))
        try database.saveTabs([moved], activeTabID: moved.id, repoID: repo.id)

        XCTAssertEqual(try database.paneState(repoID: repo.id, nodeID: leaf.id, key: "selected"),
                       "/tmp/a.swift")
    }

    func testPaneStateIsScopedToItsProject() throws {
        let database = try makeDatabase()
        let alpha = try registerRepo(in: database, path: "/tmp/alpha", name: "alpha")
        let beta = try registerRepo(in: database, path: "/tmp/beta", name: "beta")
        let node = UUID()

        try database.setPaneState(repoID: alpha.id, nodeID: node, key: "selected", value: "/tmp/a")
        XCTAssertNil(try database.paneState(repoID: beta.id, nodeID: node, key: "selected"))
    }

    /// The rows belong to the project, so deleting it takes them with it.
    func testDeletingAProjectTakesItsPaneStateWithIt() throws {
        let (database, repo) = try makeRegisteredRepo()
        let node = UUID()
        try database.setPaneState(repoID: repo.id, nodeID: node, key: "selected", value: "/tmp/a")

        try database.delete(id: repo.id)
        XCTAssertNil(try database.paneState(repoID: repo.id, nodeID: node, key: "selected"))
    }

    // MARK: - Project directories

    /// Only the *extra* directories are stored: the repository's own folder
    /// comes from `git_repo.path`, so it cannot go stale when the repo moves.
    func testProjectDirectoriesRoundTripInOrderAndReplaceWholesale() throws {
        let (database, repo) = try makeRegisteredRepo()
        XCTAssertEqual(try database.loadProjectDirectories(repoID: repo.id), [])

        try database.saveProjectDirectories(["/tmp/notes", "/tmp/docs"], repoID: repo.id)
        XCTAssertEqual(try database.loadProjectDirectories(repoID: repo.id), ["/tmp/notes", "/tmp/docs"])

        try database.saveProjectDirectories(["/tmp/docs"], repoID: repo.id)
        XCTAssertEqual(try database.loadProjectDirectories(repoID: repo.id), ["/tmp/docs"])
    }

    // MARK: - Helpers

    private func makeDatabase() throws -> ProjectDatabase {
        try ProjectDatabase(path: tempRoot.appendingPathComponent("Test.db").path)
    }

    @discardableResult
    private func registerRepo(in database: ProjectDatabase, path: String, name: String) throws -> GitRepo {
        let repo = GitRepo(path: path, name: name)
        try database.insert(repo)
        return repo
    }

    private func makeRegisteredRepo() throws -> (ProjectDatabase, GitRepo) {
        let database = try makeDatabase()
        return (database, try registerRepo(in: database, path: "/tmp/alpha", name: "alpha"))
    }

    /// A stable string for a tree, so an assertion reads as the arrangement
    /// rather than as a walk over it.
    private static func shape(of node: LayoutNode) -> String {
        switch node.kind {
        case .leaf(let contentType, _):
            return "leaf(\(contentType.rawValue))"
        case .split(let orientation, let first, let second):
            return "split(\(orientation.rawValue), \(shape(of: first)), \(shape(of: second)))"
        }
    }
}
