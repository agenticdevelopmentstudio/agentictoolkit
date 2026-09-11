import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class ComposableTabsWorkingDirectoryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("composable-workdir-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    private func makeProject() throws -> ProjectWorkspace {
        let database = try ProjectDatabase(path: tempRoot.appendingPathComponent("Test.db").path)
        let repo = GitRepo(path: tempRoot.path, name: "Test")
        try database.insert(repo)
        return ProjectWorkspace(repo: repo, database: database)
    }

    func testTheContextCarriesTheWorkingDirectoryToTheFactory() throws {
        let project = try makeProject()
        let worktree = tempRoot.appendingPathComponent("wt")
        let viewID = ComposableTabsViewID("test.workdir.view")
        var seen: URL?
        project.layout.registry.register(
            viewID,
            descriptor: ComposableTabsViewDescriptor(displayName: "Test", symbolName: "square"),
            factory: { context in
                seen = context.workingDirectory
                let controller = NSViewController()
                controller.view = NSView()
                return controller
            }
        )
        let split = ComposableTabsViewController.make(
            from: .leaf(contentType: viewID, paneLabel: nil),
            project: project,
            workingDirectory: worktree,
            isRoot: true
        )
        split.loadViewIfNeeded()
        XCTAssertEqual(seen?.path, worktree.path)
        XCTAssertEqual(split.workingDirectory.path, worktree.path)
    }

    /// The core regression this task exists to close: `persistAllTabs()`
    /// used to rebuild every `TabRecord` from live state without ever
    /// mentioning `workingDirectory`, so a tab's directory was written once
    /// (by `installInitialTabs()`, reading a stored record) and then silently
    /// wiped the moment anything touched the layout — the very next split,
    /// close, or tab switch persisted `nil` over it.
    ///
    /// This test drives the real production path: a stored record with a
    /// non-default working directory is installed, a layout mutation
    /// (`split(_:adding:direction:)`) is performed — the same call a user
    /// action makes — which fires `onLayoutDidChange` and, through it,
    /// `persistAllTabs()`. A *fresh* `ProjectWorkspace` is then built over the
    /// same on-disk database to rule out the value merely surviving in
    /// memory, and its `initialTabs()` must still report the directory.
    func testPersistAllTabsRoundTripsTheWorkingDirectoryThroughAReload() throws {
        let project = try makeProject()
        let customDirectory = tempRoot.appendingPathComponent("custom-workdir")
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)

        let initialTab = TabRecord(
            title: "Tab 1",
            root: project.layout.blueprint(),
            workingDirectory: customDirectory
        )
        project.persistTabs([initialTab], activeTabID: initialTab.id, enabledEdges: [.top])

        let windowController = ComposableTabsWindowController(project: project)
        windowController.showWindow(nil)

        guard let content = windowController.window?.contentViewController,
              let split = Self.firstSplitTree(under: content) else {
            XCTFail("expected the persisted tab's split tree to be installed")
            return
        }
        XCTAssertEqual(
            split.workingDirectory.path, customDirectory.path,
            "installInitialTabs() must read the working directory back off the stored record"
        )

        guard let leaf = split.firstLeaf() else {
            XCTFail("expected the installed tab to have at least one pane")
            return
        }
        // A real layout mutation, exactly like a user splitting a pane: this
        // is what reaches `persistAllTabs()` through `onLayoutDidChange`.
        split.split(leaf, adding: .placeholder, direction: .right)

        // A brand-new workspace over the same database file: nothing here can
        // be answered from state `project` merely kept in memory.
        let reloadedProject = ProjectWorkspace(repo: project.repo, database: project.database)
        let reloaded = reloadedProject.initialTabs()
        XCTAssertEqual(
            reloaded.tabs.first?.workingDirectory?.path, customDirectory.path,
            "persistAllTabs() must not drop the tab's working directory on a layout change"
        )
    }

    private static func firstSplitTree(under controller: NSViewController) -> ComposableTabsViewController? {
        for child in controller.children {
            if let split = child as? ComposableTabsViewController { return split }
            if let found = firstSplitTree(under: child) { return found }
        }
        return nil
    }
}
