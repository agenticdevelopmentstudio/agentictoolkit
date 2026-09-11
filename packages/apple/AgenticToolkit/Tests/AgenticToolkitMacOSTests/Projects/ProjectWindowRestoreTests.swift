import XCTest
@testable import AgenticToolkitMacOS

/// Reopening the windows that were up at quit has to survive the folder under
/// one of them being deleted or renamed in the meantime — otherwise the
/// workspace comes back with an empty tree and a terminal in `/`, which reads
/// as a broken app rather than a missing project.
@MainActor
final class ProjectWindowRestoreTests: XCTestCase {

    private func makeRepo(_ name: String, path: String) -> GitRepo {
        GitRepo(path: path, name: name, remote: nil, firstSeen: Date(), lastSeen: Date())
    }

    func testAProjectThatWasOpenAndIsStillOnDiskIsReopened() {
        let here = makeRepo("here", path: "/here")

        let plan = ProjectWindowManager.restorePlan(
            repos: [here],
            wasOpen: { _ in true },
            existsOnDisk: { _ in true }
        )

        XCTAssertEqual(plan.reopen.map(\.name), ["here"])
        XCTAssertTrue(plan.forget.isEmpty)
    }

    func testAProjectThatWasNotOpenIsLeftAlone() {
        let closed = makeRepo("closed", path: "/closed")

        let plan = ProjectWindowManager.restorePlan(
            repos: [closed],
            wasOpen: { _ in false },
            existsOnDisk: { _ in true }
        )

        XCTAssertTrue(plan.reopen.isEmpty)
        XCTAssertTrue(plan.forget.isEmpty, "a project nobody had open has no flag to clear")
    }

    /// The regression: a renamed folder reopened as an empty workspace.
    func testAProjectWhoseFolderIsGoneIsForgottenRatherThanReopened() {
        let gone = makeRepo("gone", path: "/gone")

        let plan = ProjectWindowManager.restorePlan(
            repos: [gone],
            wasOpen: { _ in true },
            existsOnDisk: { _ in false }
        )

        XCTAssertTrue(plan.reopen.isEmpty)
        XCTAssertEqual(plan.forget.map(\.name), ["gone"], "the flag has to be cleared, or it retries every launch")
    }

    func testOneMissingProjectDoesNotStopTheOthersReopening() {
        let gone = makeRepo("gone", path: "/gone")
        let here = makeRepo("here", path: "/here")

        let plan = ProjectWindowManager.restorePlan(
            repos: [gone, here],
            wasOpen: { _ in true },
            existsOnDisk: { $0.path == "/here" }
        )

        XCTAssertEqual(plan.reopen.map(\.name), ["here"])
        XCTAssertEqual(plan.forget.map(\.name), ["gone"])
    }
}

/// What the manager reports as "the projects with a window open", and in what
/// order.
///
/// `openOrder` exists in `ProjectWindowManager` precisely so that the answer is
/// the order the projects were opened in — its own comment says "a script that
/// lists `panes` twice must get the same order twice". `openWorkspaceIDs` and
/// `openWorkspaces` are the two accessors that were reading `controllers`
/// directly instead, and a `Dictionary`'s key order is seeded per process and
/// reshuffles on insert and remove.
///
/// Ten projects rather than two: with two, a dictionary that happened to
/// enumerate them in insertion order would let the bug through half the time.
/// At ten the chance of that is one in 10!, which is the difference between a
/// test that pins the behaviour and one that samples it.
@MainActor
final class ProjectWindowOpenOrderTests: XCTestCase {

    private static let projectCount = 10

    private func makeControllers() -> [ComposableTabsWindowController] {
        (0..<Self.projectCount).map { index in
            ComposableTabsWindowController(
                project: ProjectWindowTestSupport.makeProject(
                    label: "ProjectWindowOpenOrderTests", named: "project-\(index)"))
        }
    }

    func testOpenWorkspaceIDsFollowTheOrderTheProjectsWereRegisteredIn() {
        let manager = ProjectWindowManager()
        let controllers = makeControllers()
        for controller in controllers { manager.adoptForScripting(controller) }
        defer { for controller in controllers { manager.forgetForScripting(controller) } }

        let expected = controllers.map(\.project.id)
        XCTAssertEqual(manager.openWorkspaceIDs, expected)
        XCTAssertEqual(manager.openWorkspaces.map(\.id), expected)
        // The three accessors are three views of one list, and
        // `openWindowControllers` is the one that was already right.
        XCTAssertEqual(manager.openWindowControllers.map(\.project.id), expected)
    }

    /// Removing one from the middle must not disturb the rest: a `Dictionary`
    /// rehashes on remove, which is the second half of what made the published
    /// order jump around while a user opened and closed windows.
    func testRemovingOneProjectLeavesTheOthersInOrder() throws {
        let manager = ProjectWindowManager()
        let controllers = makeControllers()
        for controller in controllers { manager.adoptForScripting(controller) }
        defer { for controller in controllers { manager.forgetForScripting(controller) } }

        let removed = try XCTUnwrap(controllers.dropFirst(4).first)
        manager.forgetForScripting(removed)

        let expected = controllers.filter { $0 !== removed }.map(\.project.id)
        XCTAssertEqual(manager.openWorkspaceIDs, expected)
        XCTAssertEqual(manager.openWorkspaces.map(\.id), expected)
        XCTAssertEqual(manager.openWindowControllers.map(\.project.id), expected)
    }
}
