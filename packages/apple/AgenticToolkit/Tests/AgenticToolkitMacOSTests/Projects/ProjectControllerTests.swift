import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class ProjectControllerTests: XCTestCase {
    private let alpha = ComposableTabsViewID("test.alpha")
    private var repoRoot: URL!
    private var worktreeRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        let repoRootPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-controller-test-\(UUID().uuidString)")
        let worktreeRootPath = repoRootPath.deletingLastPathComponent()
            .appendingPathComponent(repoRootPath.lastPathComponent + "-wt")
        try FileManager.default.createDirectory(at: repoRootPath, withIntermediateDirectories: true)
        // Resolved only once the directory exists: `resolvingSymlinksInPath()`
        // normalizes the trailing slash too, but only for a path that is
        // already there, so resolving the not-yet-created worktree path here
        // would leave it one component short of what `git worktree add`
        // actually produces.
        repoRoot = repoRootPath.resolvingSymlinksInPath()
        try git(["init", "-b", "main"])
        try git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init"])
        try git(["worktree", "add", "-b", "feature", worktreeRootPath.path])
        worktreeRoot = worktreeRootPath.resolvingSymlinksInPath()

        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { _ in
            let content = NSViewController()
            content.view = NSView()
            return content
        }
        // swiftlint:disable:next force_try
        ComposableTabsLayout.install(try! ComposableTabsLayout(
            registry: registry,
            spec: .pane(alpha, allows: [.unbounded(alpha)])
        ))
    }

    override func tearDown() async throws {
        ComposableTabsLayout.install(nil)
        try? FileManager.default.removeItem(at: worktreeRoot)
        try? FileManager.default.removeItem(at: repoRoot)
        try await super.tearDown()
    }

    private func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repoRoot
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
    }

    /// A registered workspace over the throwaway repo. Same database shape as
    /// `ProjectWindowTestSupport.makeProject`, but rooted at a real git
    /// checkout so `worktrees(in:)` has something to list.
    private func makeWorkspace() throws -> ProjectWorkspace {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        return ProjectWorkspace(repo: repo, database: database)
    }

    private func makeController(registry: CommandRegistry? = nil) throws -> ProjectController {
        ProjectController(
            workspace: try makeWorkspace(),
            gitClient: GitClient(configuration: .default),
            commandRegistry: registry
        )
    }

    func testOpenCreatesOneTabGroupPerCheckoutAndPersistsIt() async throws {
        let controller = try makeController()
        await controller.open()

        XCTAssertEqual(controller.checkouts.map(\.displayName), ["main", "feature"])
        XCTAssertEqual(controller.checkouts.map(\.isMain), [true, false])
        XCTAssertEqual(controller.branchControllers.count, 2)

        let stored = try XCTUnwrap(controller.workspace.storedTabs())
        XCTAssertEqual(Set(stored.tabs.map(\.groupID)).count, 2)
        XCTAssertEqual(stored.tabs.map(\.title), ["main", "feature"])
        XCTAssertEqual(stored.tabs.map(\.workingDirectory), [repoRoot, worktreeRoot])
    }

    func testOpeningAgainKeepsTheStoredTabsAndFiresNoChange() async throws {
        let first = try makeController()
        await first.open()
        let before = try XCTUnwrap(first.workspace.storedTabs()).tabs.map(\.id)

        let second = ProjectController(
            workspace: first.workspace,
            gitClient: GitClient(configuration: .default),
            commandRegistry: nil
        )
        var fired = 0
        second.onTabsDidChange = { fired += 1 }
        await second.open()

        XCTAssertEqual(try XCTUnwrap(second.workspace.storedTabs()).tabs.map(\.id), before)
        XCTAssertEqual(fired, 0)
    }

    func testARemovedWorktreeDropsItsTabOnRefresh() async throws {
        let controller = try makeController()
        await controller.open()
        var fired = 0
        controller.onTabsDidChange = { fired += 1 }

        try git(["worktree", "remove", "--force", worktreeRoot.path])
        await controller.refreshCheckouts()

        XCTAssertEqual(controller.checkouts.map(\.displayName), ["main"])
        XCTAssertEqual(try XCTUnwrap(controller.workspace.storedTabs()).tabs.map(\.title), ["main"])
        XCTAssertEqual(fired, 1)
    }

    func testTabItemsForCheckoutsAreHostedPanesAndOthersStayTitles() async throws {
        let controller = try makeController()
        await controller.open()
        let window = ComposableTabsWindowController(project: controller.workspace)
        defer { window.close() }

        let stored = try XCTUnwrap(controller.workspace.storedTabs())
        let main = try XCTUnwrap(stored.tabs.first { $0.title == "main" })
        let item = controller.composableTabsWindowController(window, tabItemFor: main, on: .left)
        guard case .viewController(let pane) = item else { return XCTFail("expected a hosted pane") }
        XCTAssertTrue(pane is TabPaneViewController)
        XCTAssertEqual(pane.title, "main")

        let stray = TabRecord(edge: .left, title: "notes", root: .leaf(contentType: alpha),
                              workingDirectory: URL(fileURLWithPath: "/somewhere/else"))
        let strayItem = controller.composableTabsWindowController(window, tabItemFor: stray, on: .left)
        guard case .title(let title) = strayItem else {
            return XCTFail("expected a plain title")
        }
        XCTAssertEqual(title, "notes")
    }

    func testBranchCommandsAreRegistered() async throws {
        let registry = CommandRegistry()
        let controller = try makeController(registry: registry)
        await controller.open()
        let branchIDs = registry.allCommands.map(\.id).filter { $0.hasPrefix("branch.action.") }
        XCTAssertEqual(branchIDs.count, 6)
    }

    func testTheStatusProviderResolverAnswersPerCheckout() async throws {
        let controller = try makeController()
        await controller.open()
        let main = try XCTUnwrap(controller.workspace.gitStatusProvider(forDirectory: repoRoot))
        let feature = try XCTUnwrap(controller.workspace.gitStatusProvider(forDirectory: worktreeRoot))
        XCTAssertEqual(main.repoRoot, repoRoot)
        XCTAssertEqual(feature.repoRoot, worktreeRoot)
        XCTAssertNil(controller.workspace.gitStatusProvider(forDirectory: URL(fileURLWithPath: "/somewhere/else")))
    }
}
