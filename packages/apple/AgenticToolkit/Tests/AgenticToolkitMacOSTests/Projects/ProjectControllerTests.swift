import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class ProjectControllerTests: XCTestCase {
    private let alpha = ComposableTabsViewID("test.alpha")
    private var repoRoot: URL!
    private var worktreeRoot: URL!
    /// A symlink pointing at `repoRoot`, for exercising Ruling B′ directly:
    /// every other URL in this fixture is resolved before a test ever sees
    /// it, and on this OS `FileManager.default.temporaryDirectory` itself
    /// does not round-trip through `/private` the way `NSTemporaryDirectory`
    /// notes historically assumed (`resolvingSymlinksInPath()` on a path
    /// under `/var/folders/...` here already returns `/var/folders/...`, not
    /// `/private/var/folders/...`) — so a real symlink is the only reliable
    /// way to get a path that is genuinely unresolved yet still names the
    /// same directory.
    private var unresolvedRepoRoot: URL!

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
        let symlinkPath = repoRootPath.deletingLastPathComponent()
            .appendingPathComponent(repoRootPath.lastPathComponent + "-symlink")
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: repoRoot)
        unresolvedRepoRoot = symlinkPath
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
        try? FileManager.default.removeItem(at: unresolvedRepoRoot)
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

    private func makeController(
        registry: CommandRegistry? = nil,
        gitClient: GitClient = GitClient(configuration: .default)
    ) throws -> ProjectController {
        ProjectController(
            workspace: try makeWorkspace(),
            gitClient: gitClient,
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

    /// `open()` hardcodes `notify: false`, so this proves only that a second
    /// open (a fresh `ProjectController` over the same workspace, as happens
    /// on relaunch) leaves the already-persisted tabs untouched — it does NOT
    /// exercise notify-suppression. `testAnUnchangedRefreshFiresNoChangeAndLeavesStoredTabsAlone`
    /// below covers that, on the one path (`refreshCheckouts`) that can fire.
    func testOpeningAgainKeepsTheStoredTabsAcrossASecondOpen() async throws {
        let first = try makeController()
        await first.open()
        let before = try XCTUnwrap(first.workspace.storedTabs()).tabs.map(\.id)

        let second = ProjectController(
            workspace: first.workspace,
            gitClient: GitClient(configuration: .default),
            commandRegistry: nil
        )
        await second.open()

        XCTAssertEqual(try XCTUnwrap(second.workspace.storedTabs()).tabs.map(\.id), before)
    }

    /// Exercises the `guard stored == nil || !plan.isUnchanged else { return }`
    /// short-circuit in `reconcile(notify:)` on the one path that can actually
    /// fire a notification: `refreshCheckouts()`, called a second time with
    /// nothing changed on disk. Also covers the NIT that a reused
    /// `BranchController` is not rebuilt across an unchanged reconcile.
    func testAnUnchangedRefreshFiresNoChangeAndLeavesStoredTabsAlone() async throws {
        let controller = try makeController()
        await controller.open()
        let before = try XCTUnwrap(controller.workspace.storedTabs()).tabs.map(\.id)
        let mainBefore = try XCTUnwrap(controller.checkouts.first { $0.isMain })
        let mainController = try XCTUnwrap(controller.branchControllers[mainBefore])

        var fired = 0
        controller.onTabsDidChange = { fired += 1 }
        await controller.refreshCheckouts()

        XCTAssertEqual(try XCTUnwrap(controller.workspace.storedTabs()).tabs.map(\.id), before)
        XCTAssertEqual(fired, 0)
        let mainAfter = try XCTUnwrap(controller.checkouts.first { $0.isMain })
        let mainControllerAfter = try XCTUnwrap(controller.branchControllers[mainAfter])
        XCTAssertTrue(mainControllerAfter === mainController)
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

    /// Ruling B′: `branchController(forDirectory:)` resolves symlinks in the
    /// URL it is handed before comparing. Every other URL in this fixture is
    /// already resolved by the time a test sees it, so this test deliberately
    /// feeds it `unresolvedRepoRoot` — a symlink that names `repoRoot` but is
    /// textually different from it — and checks it still finds the same
    /// controller as the resolved path does.
    func testBranchControllerLookupResolvesAnUnresolvedDirectory() async throws {
        let controller = try makeController()
        await controller.open()

        let viaResolved = try XCTUnwrap(controller.branchController(forDirectory: repoRoot))
        let viaUnresolved = try XCTUnwrap(controller.branchController(forDirectory: unresolvedRepoRoot))
        XCTAssertTrue(viaResolved === viaUnresolved)
    }

    /// A `git worktree list` that fails outright (distinct from succeeding
    /// with zero worktrees) must not collapse `checkouts` to the
    /// single-project fallback: that would silently drop the feature
    /// checkout's `BranchController` and re-render its tab as a plain title.
    /// `GitClient`'s async-provider initializer lets the configuration flip
    /// mid-test to one with no git executable at all.
    func testATransientGitFailureKeepsTheLastKnownCheckouts() async throws {
        let availability = FlippableGitAvailability()
        let gitClient = GitClient(configuration: { await availability.configuration() })
        let controller = try makeController(gitClient: gitClient)
        await controller.open()
        XCTAssertEqual(controller.checkouts.map(\.displayName), ["main", "feature"])
        XCTAssertEqual(controller.branchControllers.count, 2)
        let before = try XCTUnwrap(controller.workspace.storedTabs()).tabs.map(\.id)

        await availability.flipToUnhealthy()
        await controller.refreshCheckouts()

        XCTAssertEqual(controller.checkouts.map(\.displayName), ["main", "feature"])
        XCTAssertEqual(controller.branchControllers.count, 2)
        XCTAssertEqual(try XCTUnwrap(controller.workspace.storedTabs()).tabs.map(\.id), before)
    }
}

/// Flips a `GitClientConfiguration` from a real git executable to a path that
/// does not exist, for `testATransientGitFailureKeepsTheLastKnownCheckouts`.
private actor FlippableGitAvailability {
    private var healthy = true

    func flipToUnhealthy() {
        healthy = false
    }

    func configuration() -> GitClientConfiguration {
        guard healthy else {
            return GitClientConfiguration(executableURL: URL(fileURLWithPath: "/nonexistent/git"))
        }
        return .default
    }
}
