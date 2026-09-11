import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// `ProjectWindowManager` builds one `ProjectController` per project window,
/// hands it to the window as its `tabItemDataSource`, and tears it down when
/// the window closes.
@MainActor
final class ProjectWindowManagerControllerTests: XCTestCase {
    private let alpha = ComposableTabsViewID("test.alpha")
    private var repoRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        let repoRootPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("window-manager-controller-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoRootPath, withIntermediateDirectories: true)
        // Resolved only after the directory exists: `resolvingSymlinksInPath()`
        // is a filesystem lookup, not the purely lexical `standardizedFileURL`,
        // so it can only normalize a component (like a `/var` -> `/private/var`
        // symlink) once there is something on disk to resolve.
        repoRoot = repoRootPath.resolvingSymlinksInPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "-b", "main"]
        process.currentDirectoryURL = repoRoot
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git init")

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
        try? FileManager.default.removeItem(at: repoRoot)
        try await super.tearDown()
    }

    func testOpeningAProjectBuildsAControllerAndClosingDropsIt() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        // Ruling K: a fresh manager, never `.shared` — a test against the
        // process-wide singleton would leak this window into every other test
        // that touches it.
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)
        manager.gitClient = GitClient(configuration: .default)

        manager.openProject(repo)
        let controller = try XCTUnwrap(manager.projectController(for: repo.id))
        XCTAssertEqual(controller.workspace.directoryURL.resolvingSymlinksInPath(), repoRoot.resolvingSymlinksInPath())

        // open() runs in a task the manager starts; wait for it to have persisted tabs.
        let deadline = Date().addingTimeInterval(5)
        while controller.workspace.storedTabs() == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.workspace.storedTabs()?.tabs.map(\.title), ["main"])
        let window = try XCTUnwrap(manager.windowController(for: repo.id))
        XCTAssertTrue(window.tabItemDataSource === controller)

        manager.closeProject(repoID: repo.id)
        XCTAssertNil(manager.projectController(for: repo.id))
    }

    /// A window regaining key status re-scans worktrees, so a checkout added
    /// or removed in a terminal while the window sat in the background shows
    /// up without a relaunch.
    func testTheWindowBecomingKeyRefreshesCheckouts() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)
        manager.gitClient = GitClient(configuration: .default)

        manager.openProject(repo)
        let controller = try XCTUnwrap(manager.projectController(for: repo.id))

        let deadline = Date().addingTimeInterval(5)
        while controller.workspace.storedTabs() == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.workspace.storedTabs()?.tabs.map(\.title), ["main"])

        let worktreeRoot = repoRoot.deletingLastPathComponent()
            .appendingPathComponent(repoRoot.lastPathComponent + "-wt")
        let commit = Process()
        commit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commit.arguments = ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init"]
        commit.currentDirectoryURL = repoRoot
        try commit.run()
        commit.waitUntilExit()
        XCTAssertEqual(commit.terminationStatus, 0, "git commit")
        let worktreeAdd = Process()
        worktreeAdd.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        worktreeAdd.arguments = ["worktree", "add", "-b", "feature", worktreeRoot.path]
        worktreeAdd.currentDirectoryURL = repoRoot
        try worktreeAdd.run()
        worktreeAdd.waitUntilExit()
        XCTAssertEqual(worktreeAdd.terminationStatus, 0, "git worktree add")
        defer { try? FileManager.default.removeItem(at: worktreeRoot) }

        let window = try XCTUnwrap(manager.windowController(for: repo.id).flatMap(\.window))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

        let refreshDeadline = Date().addingTimeInterval(5)
        while controller.checkouts.map(\.displayName) != ["main", "feature"], Date() < refreshDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.checkouts.map(\.displayName), ["main", "feature"])

        manager.closeProject(repoID: repo.id)
    }

    /// Ruling M: teardown routes through `ProjectController.shutdown()` only
    /// for a window `openProject(_:)` built — a window `adoptForScripting(_:)`
    /// merely registered gets no controller at all, so closing it can only
    /// take the inline fallback, never both. This proves the two windows pick
    /// different branches: the opened one has a controller to drop, the
    /// adopted one never had one to begin with.
    func testAnAdoptedWindowHasNoControllerAndClosesThroughTheFallback() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let openedRepo = GitRepo(path: repoRoot.path, name: "opened")
        try database.insert(openedRepo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)
        manager.gitClient = GitClient(configuration: .default)

        manager.openProject(openedRepo)
        XCTAssertNotNil(manager.projectController(for: openedRepo.id))

        let adoptedWorkspace = ProjectWindowTestSupport.makeProject(label: "ProjectWindowManagerControllerTests")
        let adoptedController = ComposableTabsWindowController(project: adoptedWorkspace)
        adoptedController.showWindow(nil)
        manager.adoptForScripting(adoptedController)
        XCTAssertNil(manager.projectController(for: adoptedWorkspace.id),
                      "adopting registers the window, not a controller for it")

        adoptedController.close()
        XCTAssertNil(manager.windowController(for: adoptedWorkspace.id))
        // The opened window's own controller is untouched by the adopted
        // window's close.
        XCTAssertNotNil(manager.projectController(for: openedRepo.id))

        manager.closeProject(repoID: openedRepo.id)
        XCTAssertNil(manager.projectController(for: openedRepo.id))
    }
}
