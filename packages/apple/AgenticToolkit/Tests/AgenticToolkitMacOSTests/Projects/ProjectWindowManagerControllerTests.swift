import AgenticToolkitCore
import AgenticToolkitLanguage
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// A pane content view that can take the window's focus. The window arms its
/// debounced tab persist from first-responder changes *inside a pane*, so a
/// test that needs that writer running needs a view AppKit will actually hand
/// the responder to.
private final class FocusableTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

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
            content.view = FocusableTestView()
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

        // MAJOR 1 (review fix round 1): stored tab titles only prove the
        // database was written, not that the window itself shows anything
        // but a plain title button. `ComposableTabsWindowController.init`
        // installs tabs, so the `tabItemDataSource:` argument the manager
        // passes to it is what turns "main" into a hosted pane — drop that
        // argument and every other assertion in this test still passes.
        let reloadDeadline = Date().addingTimeInterval(5)
        func isHostedPane(_ item: TabItem) -> Bool {
            if case .viewController = item { return true }
            return false
        }
        while !(window.tabItems(on: .top).allSatisfy(isHostedPane) && !window.tabItems(on: .top).isEmpty),
              Date() < reloadDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let items = window.tabItems(on: .top)
        XCTAssertFalse(items.isEmpty, "the main checkout's tab must have been installed")
        for item in items {
            guard case .viewController = item else {
                XCTFail("expected a hosted pane after open() lands, got a plain title: \(item)")
                continue
            }
        }

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

        // MAJOR 1 (review fix round 1): checkouts changing is not the same
        // claim as the window's tab items changing. `onTabsDidChange` is now
        // the only thing anywhere that calls
        // `reloadTabs()` — delete that assignment and
        // `checkouts` above still updates, but the window keeps showing only
        // "main" forever.
        let windowController = try XCTUnwrap(manager.windowController(for: repo.id))
        let tabDeadline = Date().addingTimeInterval(5)
        while windowController.tabItems(on: .top).count != 2, Date() < tabDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(windowController.tabItems(on: .top).count, 2,
                        "the window's tab items must follow the checkout list onTabsDidChange reports")

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
        // NIT 9: aligned with the character right after the opening paren.
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

    /// MAJOR 2 (review fix round 1): closing a window must drop its
    /// `NSWindow.didBecomeKeyNotification` observer, not merely leave it
    /// harmless because `projectControllers[repoID]` also happened to go
    /// empty. Reopening the *same* repo id gives that repo a fresh, live
    /// controller again — if the dead window's observer were still
    /// registered, posting the notification against it would find that live
    /// controller and refresh it, doing real, unwanted work. Deleting
    /// `ProjectWindowManager`'s `keyObservers` removal (the three lines
    /// right after the controller is dropped in `observeClose`) leaves every
    /// assertion but the last two in this test passing.
    func testClosingRemovesTheKeyObserverSoAStaleWindowCannotTriggerARefresh() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)

        let logDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("key-observer-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logDir) }
        let fakeGitURL = try makeCountingFakeGitExecutable(logDir: logDir)
        manager.gitClient = GitClient(configuration: GitClientConfiguration(executableURL: fakeGitURL, timeout: 10))

        manager.openProject(repo)
        let firstDeadline = Date().addingTimeInterval(5)
        while manager.projectController(for: repo.id)?.workspace.storedTabs() == nil, Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let staleWindow = try XCTUnwrap(manager.windowController(for: repo.id)?.window)

        manager.closeProject(repoID: repo.id)
        XCTAssertNil(manager.projectController(for: repo.id))
        XCTAssertFalse(manager.hasKeyObserver(for: repo.id), "closing a window must drop its key observer")

        // Reopen the same repo id: a fresh, live controller now exists.
        manager.openProject(repo)
        let secondDeadline = Date().addingTimeInterval(5)
        while manager.projectController(for: repo.id)?.workspace.storedTabs() == nil, Date() < secondDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        // Reopening starts its own reconcile — `open()`'s trailing
        // `branchControllers` refresh loop can still be landing calls after
        // `storedTabs()` is first written — so the baseline is taken only
        // once the call count has gone quiet, not at the first sight of
        // stored tabs.
        var callsAfterReopen = try callCount(in: logDir)
        var quietSince = Date()
        let quiesceDeadline = Date().addingTimeInterval(5)
        while Date().timeIntervalSince(quietSince) < 0.3, Date() < quiesceDeadline {
            try await Task.sleep(for: .milliseconds(50))
            let current = try callCount(in: logDir)
            if current != callsAfterReopen {
                callsAfterReopen = current
                quietSince = Date()
            }
        }

        // Posted against the *dead* window, not the reopened one.
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: staleWindow)

        // Long enough for a wrongly-triggered refresh to reach the fake git.
        try await Task.sleep(for: .milliseconds(300))
        let callsAfterStalePost = try callCount(in: logDir)
        XCTAssertEqual(
            callsAfterStalePost, callsAfterReopen,
            "a closed window's stale observer must not trigger a refresh on the reopened project's controller"
        )

        manager.closeProject(repoID: repo.id)
    }

    /// MAJOR 3 (review fix round 1): the fixture in
    /// `testAnAdoptedWindowHasNoControllerAndClosesThroughTheFallback` never
    /// gave either window real language services, so neither of Ruling M's
    /// two teardown branches did any observable work — that test would pass
    /// identically if both branches ran unconditionally. Here both windows
    /// carry their own counting `ProjectLanguageServices`, so shutting the
    /// wrong one down, or shutting one down twice, is directly observable.
    func testClosingShutsDownExactlyOneLanguageServicesPerWindow() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let openedRepo = GitRepo(path: repoRoot.path, name: "opened")
        try database.insert(openedRepo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)
        manager.gitClient = GitClient(configuration: .default)

        let openedServices = makeLanguageServices()
        manager.languageServicesFactory = { [openedServices] _ in openedServices }

        manager.openProject(openedRepo)
        let projectController = try XCTUnwrap(manager.projectController(for: openedRepo.id))
        XCTAssertTrue(projectController.workspace.languageServices === openedServices)

        let adoptedServices = makeLanguageServices()
        let adoptedWorkspace = ProjectWindowTestSupport.makeProject(
            label: "ProjectWindowManagerControllerTests",
            languageServices: adoptedServices
        )
        let adoptedController = ComposableTabsWindowController(project: adoptedWorkspace)
        adoptedController.showWindow(nil)
        manager.adoptForScripting(adoptedController)

        adoptedController.close()
        let adoptedDeadline = Date().addingTimeInterval(5)
        while adoptedServices.shutdownCallCount == 0, Date() < adoptedDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(
            adoptedServices.shutdownCallCount, 1,
            "the adopted-window fallback must shut its own project's services down exactly once"
        )
        XCTAssertEqual(
            openedServices.shutdownCallCount, 0,
            "closing the adopted window must not touch the opened window's services"
        )

        manager.closeProject(repoID: openedRepo.id)
        let openedDeadline = Date().addingTimeInterval(5)
        while openedServices.shutdownCallCount == 0, Date() < openedDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(
            openedServices.shutdownCallCount, 1,
            "the controller path must shut its own project's services down exactly once, never twice"
        )
    }

    /// MAJOR 4 / Ruling Q (review fix round 1): `openProject(_:)`'s
    /// completion task captures `projectController` strongly, so closing the
    /// window mid-scan must not let that task persist a dead window's tabs
    /// or reload it once the slow git call finally lands. The fake git here
    /// always sleeps past the point this test closes the window, so the
    /// open() task is provably still in flight — not merely not-yet-started —
    /// when `closeProject` runs.
    func testClosingWhileTheOpenTaskIsInFlightPersistsNothingAndReloadsNothing() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)

        let scriptDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("close-mid-open-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scriptDir) }
        let fakeGitURL = try makeSlowFakeGitExecutable(scriptDir: scriptDir)
        manager.gitClient = GitClient(configuration: GitClientConfiguration(executableURL: fakeGitURL, timeout: 10))

        manager.openProject(repo)
        let controller = try XCTUnwrap(manager.projectController(for: repo.id))
        let windowController = try XCTUnwrap(manager.windowController(for: repo.id))

        // `ComposableTabsWindowController.init` builds a placeholder "Tab 1"
        // in memory (`topUpTabs` finds every enabled edge's group already has
        // a member and never calls `persistAllTabs()`), so nothing is
        // written to the database until a reconcile actually persists —
        // confirmed here rather than assumed, since that is exactly what
        // this test must not let happen.
        XCTAssertNil(controller.workspace.storedTabs(), "nothing should be persisted before any reconcile lands")

        let startedMarker = scriptDir.appendingPathComponent("started").path
        let startDeadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: startedMarker), Date() < startDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: startedMarker),
            "the fixture's git call never started — the fixture itself is broken, not the code under test"
        )

        manager.closeProject(repoID: repo.id)
        XCTAssertNil(manager.projectController(for: repo.id))

        // The fake git sleeps 0.4s past the marker; wait well past that for
        // the in-flight open() task to land.
        try await Task.sleep(for: .milliseconds(900))

        // The database, which is the claim that matters: a window closed
        // mid-scan must leave the project's rows exactly as it found them.
        // This assertion was impossible to write while the window's debounced
        // focus-persist could fire on its own schedule — it wrote the live
        // (placeholder) tab set and so landed "Tab 1" here no matter what the
        // reconcile did. The close now drops that pending item, so nothing
        // writes these rows behind the guard.
        XCTAssertNil(
            controller.workspace.storedTabs(),
            "a window closed mid-scan must not leave tab rows behind"
        )
        // `controller.checkouts` is the same guard seen one step earlier:
        // `reconcile()` re-checks `!isClosed` after the `await` a close can
        // land inside of, before assigning it, and everything downstream
        // (`branchControllers` and the persisted tabs) flows from that same
        // assignment.
        XCTAssertTrue(
            controller.checkouts.isEmpty,
            "a window closed mid-scan must never have its checkouts updated by the in-flight reconcile"
        )
        // Downstream of the same guard: with `checkouts` never populated,
        // `branchController(forDirectory:)` can never resolve one, so the
        // data source's fallback keeps every tab a plain title — this would
        // hold even if `reloadTabs()` ran regardless, but proves the window
        // was never handed a hosted pane for the checkout either way.
        XCTAssertTrue(
            windowController.tabItems(on: .top).allSatisfy { item in
                if case .viewController = item { return false }
                return true
            },
            "a window closed mid-scan must never be reloaded with the checkout's hosted pane"
        )
    }

    /// BLOCKER 2 (final review B): the window and the project controller are
    /// both writers of the project's tab rows, and `saveTabs` is a full
    /// delete-then-insert, so whichever lands last wins outright.
    ///
    /// On a first open the window has nothing stored to install, so its live
    /// tab set is a single placeholder. The 250 ms focus-persist armed the
    /// moment focus lands in a pane then fires *after* reconcile has written
    /// one tab per worktree and replaces every one of them with that
    /// placeholder — and it does not self-heal, because the next reconcile
    /// keeps the placeholder (its directory resolves to the project) and adds
    /// the checkouts back beside it.
    ///
    /// The fake git answers `worktree list` at once with two checkouts and
    /// then sleeps in `rev-parse`, which is what used to hold the post-open
    /// reload well past the debounce and leave the placeholder standing as the
    /// final state of the database.
    func testAFirstOpenKeepsTheReconciledTabsAgainstTheWindowsDebouncedWrite() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)

        let worktreeRoot = repoRoot.deletingLastPathComponent()
            .appendingPathComponent(repoRoot.lastPathComponent + "-wt")
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktreeRoot) }

        let scriptDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("two-writer-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scriptDir) }
        let fakeGitURL = try makeTwoCheckoutFakeGitExecutable(scriptDir: scriptDir, worktreeRoot: worktreeRoot)
        manager.gitClient = GitClient(configuration: GitClientConfiguration(executableURL: fakeGitURL, timeout: 10))

        manager.openProject(repo)
        let controller = try XCTUnwrap(manager.projectController(for: repo.id))
        let windowController = try XCTUnwrap(manager.windowController(for: repo.id))
        // Still in the turn that opened the window, so this is provably armed
        // before the reconcile's own write — the ordering the bug needs.
        try armFocusPersist(on: windowController)

        // Past the 250 ms debounce and past the checkout scan, but nowhere
        // near the sleeping `rev-parse` calls behind it.
        try await Task.sleep(for: .milliseconds(900))

        let stored = try XCTUnwrap(
            controller.workspace.storedTabs(),
            "the reconcile must have written this project's tabs"
        )
        XCTAssertEqual(
            Set(stored.tabs.map(\.title)), ["main", "feature"],
            "the window's debounced write must not replace the reconciled tabs with its placeholder"
        )

        manager.closeProject(repoID: repo.id)
    }

    /// MAJOR 6 (final review B): opening a project built its whole pane tree
    /// twice — once inside `init`, before the data source was assigned, so
    /// every tab fell back to a plain title, and again from a `reloadTabs()`
    /// that ran whether or not the scan had changed anything. With every tab
    /// carrying a terminal, the second build is a set of shells killed and a
    /// set spawned for nothing.
    ///
    /// A reopen is where it shows: the checkouts are already stored, so the
    /// reconcile writes nothing and there is nothing to reload. The panes the
    /// window built for itself must simply still be there.
    func testReopeningAnUnchangedProjectKeepsThePanesItsWindowBuilt() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)
        manager.gitClient = GitClient(configuration: .default)

        manager.openProject(repo)
        let firstController = try XCTUnwrap(manager.projectController(for: repo.id))
        let firstDeadline = Date().addingTimeInterval(5)
        while firstController.workspace.storedTabs() == nil, Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let storedBefore = try XCTUnwrap(firstController.workspace.storedTabs()).tabs.map(\.id)
        manager.closeProject(repoID: repo.id)

        manager.openProject(repo)
        let windowController = try XCTUnwrap(manager.windowController(for: repo.id))
        // Read in the opening turn: these are the panes `init` built, before
        // any reconcile could have landed.
        // Held strongly, and compared by identity rather than by address: a
        // rebuild would deallocate these, and a fresh pane could land on a
        // recycled address and pass an `ObjectIdentifier` comparison for the
        // wrong reason. Keeping them alive makes that impossible.
        let panesAtOpen = windowController.allPanes()
        XCTAssertFalse(panesAtOpen.isEmpty, "the stored tab must have been installed by init")

        // Past the reconcile, and past the window's own 250 ms debounce.
        try await Task.sleep(for: .milliseconds(800))

        let panesAfterScan = windowController.allPanes()
        XCTAssertEqual(
            panesAfterScan.count, panesAtOpen.count,
            "a reopen that changed nothing must not change how many panes the window has"
        )
        XCTAssertTrue(
            zip(panesAfterScan, panesAtOpen).allSatisfy { $0 === $1 },
            "a reopen that changed nothing must not throw the window's panes away and rebuild them"
        )
        // The tab *buttons* are the one thing the scan does have to correct:
        // at init the project controller had not scanned yet, so it could only
        // answer `.title`. It must correct them without touching the panes
        // asserted above — which is exactly what the assertion pair says.
        XCTAssertTrue(
            windowController.tabItems(on: .top).allSatisfy { item in
                if case .viewController = item { return true }
                return false
            },
            "the checkout scan must hand the tabs their real items once it has them"
        )
        let reopened = try XCTUnwrap(manager.projectController(for: repo.id))
        XCTAssertEqual(try XCTUnwrap(reopened.workspace.storedTabs()).tabs.map(\.id), storedBefore)

        manager.closeProject(repoID: repo.id)
    }

    /// The close has to reach the controller's closed flag in its **own**
    /// main-actor turn. `shutdown()` sets the same flag, but it is `async` and
    /// the close handler reaches it through `Task { await … }`, so the flag
    /// went down one hop late — and the job that hop lets through is precisely
    /// the one that matters: a reconcile continuation resuming from
    /// `readCheckouts()`'s `await`, which then writes `checkouts`, registers
    /// commands for a dead window and persists its tabs. Asserting right here,
    /// with no `await` between the close and the check, is what distinguishes
    /// "synchronously" from "very soon".
    func testClosingMarksTheControllerClosedInTheSameTurn() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)
        manager.gitClient = GitClient(configuration: .default)

        manager.openProject(repo)
        let controller = try XCTUnwrap(manager.projectController(for: repo.id))
        XCTAssertFalse(controller.isClosed, "an open project's controller is not closed")

        manager.closeProject(repoID: repo.id)
        XCTAssertTrue(
            controller.isClosed,
            "the close handler must close the controller synchronously, not in a task it schedules"
        )
    }

    /// Task 23: `ProjectWindowManager`'s scripting surface must route through
    /// `projectController(for:)` to a real `BranchController.currentBranch`
    /// lookup, not the `{ _ in nil }` placeholder Task 20 left behind. This
    /// drives `scriptableProjectTabs` / `scriptableProjectTab(uniqueID:)`
    /// end to end over a real two-checkout repo (main + a `feature`
    /// worktree, same fixture as `testTheWindowBecomingKeyRefreshesCheckouts`
    /// above) so the main-checkout tab must report branch "main" and its own
    /// directory, and the worktree tab must report "feature" and its own —
    /// proof the resolver is wired to the *right* checkout's branch
    /// controller, not just *a* branch controller.
    func testScriptableProjectTabsReportEachCheckoutsOwnBranchAndDirectory() async throws {
        let database = try ProjectDatabase(path: repoRoot.appendingPathComponent(".test-project.db").path)
        let repo = GitRepo(path: repoRoot.path, name: "fixture")
        try database.insert(repo)
        let coordinator = try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
        let manager = ProjectWindowManager()
        manager.attach(to: coordinator)
        manager.gitClient = GitClient(configuration: .default)

        manager.openProject(repo)
        let controller = try XCTUnwrap(manager.projectController(for: repo.id))

        let firstDeadline = Date().addingTimeInterval(5)
        while controller.workspace.storedTabs() == nil, Date() < firstDeadline {
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

        let windowController = try XCTUnwrap(manager.windowController(for: repo.id))
        let tabDeadline = Date().addingTimeInterval(5)
        while windowController.tabItems(on: .top).count != 2, Date() < tabDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let tabs = manager.scriptableProjectTabs
        XCTAssertEqual(tabs.count, 2, "one scriptable tab per checkout")

        let mainDirectory = repoRoot.resolvingSymlinksInPath().path
        let worktreeDirectory = worktreeRoot.resolvingSymlinksInPath().path
        let mainTab = try XCTUnwrap(tabs.first { $0.tabWorkingDirectory == mainDirectory })
        let featureTab = try XCTUnwrap(tabs.first { $0.tabWorkingDirectory == worktreeDirectory })
        XCTAssertEqual(mainTab.tabBranch, "main")
        XCTAssertEqual(featureTab.tabBranch, "feature")

        let lookedUp = try XCTUnwrap(manager.scriptableProjectTab(uniqueID: mainTab.uniqueID))
        XCTAssertEqual(lookedUp.tabBranch, "main")
        XCTAssertEqual(lookedUp.tabWorkingDirectory, mainDirectory)

        manager.closeProject(repoID: repo.id)
    }

    // MARK: - Fixtures

    private func makeLanguageServices() -> ProjectLanguageServices {
        let settings = SettingsStore(
            with: InMemorySettingsStorageProvider(),
            secureSettingsProvider: InMemorySecureSettingsStorageProvider()
        )
        let registry = LanguageServerRegistry(store: settings, workspaceURL: repoRoot, builtInConfigurations: [])
        return ProjectLanguageServices(documentStore: TextDocumentStore(), registry: registry)
    }

    /// Writes an executable fake `git` to `logDir` that answers `worktree
    /// list --porcelain` with a single checkout (`repoRoot`, branch `main`)
    /// and `rev-parse --abbrev-ref HEAD` with `main`, appending one line to
    /// `logDir/calls.log` on every invocation regardless of verb — the
    /// count of lines is the count of git calls made.
    private func makeCountingFakeGitExecutable(logDir: URL) throws -> URL {
        let script = """
        #!/usr/bin/env python3
        import os
        import sys

        LOG_DIR = \(pythonLiteral(logDir.path))
        REPO_ROOT = \(pythonLiteral(repoRoot.path))


        def main():
            fd = os.open(os.path.join(LOG_DIR, "calls.log"), os.O_CREAT | os.O_WRONLY | os.O_APPEND)
            os.write(fd, b"call\\n")
            os.close(fd)
            args = sys.argv[1:]
            verb = args[0] if args else ""
            if verb == "worktree":
                sys.stdout.write(
                    "worktree " + REPO_ROOT + "\\n"
                    "HEAD 0000000000000000000000000000000000000001\\n"
                    "branch refs/heads/main\\n"
                )
                sys.exit(0)
            elif verb == "rev-parse":
                sys.stdout.write("main\\n")
                sys.exit(0)
            else:
                sys.exit(1)


        main()
        """
        let scriptURL = logDir.appendingPathComponent("fake-git.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    /// Puts the window's focus inside its first pane and tells the window the
    /// responder changed, which is exactly what arms the debounced tab
    /// persist. Asserts the responder actually moved: a view that refuses it
    /// would leave the writer this exercises switched off, and the test would
    /// pass by testing nothing.
    private func armFocusPersist(on windowController: ComposableTabsWindowController) throws {
        let window = try XCTUnwrap(windowController.window)
        let pane = try XCTUnwrap(windowController.allPanes().first)
        // The pane's content is built with its view, and the responder has to
        // land on a real view inside the leaf.
        _ = pane.view
        let content = try XCTUnwrap(pane.contentViewController)
        XCTAssertTrue(window.makeFirstResponder(content.view), "the pane's content must accept first responder")
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
    }

    /// Writes an executable fake `git` answering `worktree list --porcelain`
    /// immediately with two checkouts — `repoRoot` on `main` and
    /// `worktreeRoot` on `feature` — and taking a full second over each
    /// `rev-parse`. The delay is the point: it holds the branch refresh that
    /// follows a reconcile well past the window's 250 ms focus-persist
    /// debounce, so the two writers are ordered the way the bug needs them.
    private func makeTwoCheckoutFakeGitExecutable(scriptDir: URL, worktreeRoot: URL) throws -> URL {
        let script = """
        #!/usr/bin/env python3
        import sys
        import time

        REPO_ROOT = \(pythonLiteral(repoRoot.path))
        WORKTREE_ROOT = \(pythonLiteral(worktreeRoot.path))


        def main():
            args = sys.argv[1:]
            verb = args[0] if args else ""
            if verb == "worktree":
                sys.stdout.write(
                    "worktree " + REPO_ROOT + "\\n"
                    "HEAD 0000000000000000000000000000000000000001\\n"
                    "branch refs/heads/main\\n"
                    "\\n"
                    "worktree " + WORKTREE_ROOT + "\\n"
                    "HEAD 0000000000000000000000000000000000000002\\n"
                    "branch refs/heads/feature\\n"
                )
                sys.exit(0)
            elif verb == "rev-parse":
                time.sleep(1.0)
                sys.stdout.write("main\\n")
                sys.exit(0)
            else:
                sys.exit(1)


        main()
        """
        let scriptURL = scriptDir.appendingPathComponent("fake-git.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func callCount(in logDir: URL) throws -> Int {
        let logPath = logDir.appendingPathComponent("calls.log")
        guard let contents = try? String(contentsOf: logPath, encoding: .utf8) else { return 0 }
        return contents.split(separator: "\n").count
    }

    /// Writes an executable fake `git` that marks `scriptDir/started` the
    /// instant it is invoked with `worktree`, then sleeps 0.4s before
    /// answering with a single checkout — long enough for a test to close
    /// the window while that call is provably still in flight.
    private func makeSlowFakeGitExecutable(scriptDir: URL) throws -> URL {
        let script = """
        #!/usr/bin/env python3
        import os
        import sys
        import time

        SCRIPT_DIR = \(pythonLiteral(scriptDir.path))
        REPO_ROOT = \(pythonLiteral(repoRoot.path))


        def main():
            args = sys.argv[1:]
            verb = args[0] if args else ""
            if verb == "worktree":
                with open(os.path.join(SCRIPT_DIR, "started"), "w") as marker:
                    marker.write("1")
                time.sleep(0.4)
                sys.stdout.write(
                    "worktree " + REPO_ROOT + "\\n"
                    "HEAD 0000000000000000000000000000000000000001\\n"
                    "branch refs/heads/main\\n"
                )
                sys.exit(0)
            elif verb == "rev-parse":
                sys.stdout.write("main\\n")
                sys.exit(0)
            else:
                sys.exit(1)


        main()
        """
        let scriptURL = scriptDir.appendingPathComponent("fake-git.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    /// A Python single-quoted string literal for `value`, escaping backslashes
    /// and single quotes so an absolute path — which on this OS never contains
    /// a newline — can be spliced straight into the generated script.
    private func pythonLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}
