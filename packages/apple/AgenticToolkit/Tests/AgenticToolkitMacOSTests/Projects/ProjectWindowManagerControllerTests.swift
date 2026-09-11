import AgenticToolkitCore
import AgenticToolkitLanguage
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

        // MAJOR 1 (review fix round 1): stored tab titles only prove the
        // database was written, not that the window itself shows anything
        // but a plain title button. `ComposableTabsWindowController.init`
        // installs tabs before `tabItemDataSource` is even set, so the
        // `reloadTabs()` call after `open()` lands (`ProjectWindowManager`
        // line ~236) is what turns "main" into a hosted pane — delete it and
        // every other assertion in this test still passes.
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
        // claim as the window's tab items changing. `onTabsDidChange` (set at
        // `ProjectWindowManager` line ~224) is the only thing that calls
        // `reloadTabs()` on this path — delete that assignment and
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

        // Checking the *database* here would not actually prove anything:
        // `ComposableTabsWindowController` separately schedules a
        // focus-tracking persist (`scheduleFocusPersist()`, driven by
        // `NSWindow.didUpdateNotification` -> `refreshFocusedLeaf()`)
        // whenever the window's first responder changes, entirely unrelated
        // to the git-reconcile path and not something the `isClosed` guard
        // is meant to cover. Closing the window fires more first-responder
        // updates, which keep re-debouncing that persist — verified directly,
        // by disabling `isClosed`'s check in `reconcile(notify:)`, that this
        // still lands "Tab 1" (the placeholder) in the database within the
        // wait window above: the debounced focus persist overwrites
        // reconcile's own write, so a stored-tabs assertion cannot tell a
        // guarded close from an unguarded one. (It fires here only because
        // this test keeps `windowController` alive after close — production
        // drops the last strong reference to it in `observeClose`, so the
        // scheduled work's `weak self` resolves to nil before it runs.)
        //
        // `controller.checkouts` is not touched by that unrelated mechanism,
        // and it is exactly what `reconcile(notify:)` guards on `!isClosed`
        // — checked again after the `await` a close can land inside of —
        // before assigning it, and everything downstream (`branchControllers`
        // and the persisted tabs) flows from that same assignment. A window
        // closed mid-scan must never see it happen, no matter how long the
        // slow git call takes to return.
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
