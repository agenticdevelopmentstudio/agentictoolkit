import XCTest
@testable import AgenticToolkitMacOS

/// `ProjectWorkspace` vending its stored tabs, per-directory file-browser
/// roots and a resolved git status provider — the accessors a later task
/// builds one tab per git worktree on top of.
@MainActor
final class ProjectWorkspaceTabsTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-tabs-test-\(UUID().uuidString)")
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

    func testStoredTabsIsNilBeforeAnythingIsPersisted() throws {
        let project = try makeProject()
        XCTAssertNil(project.storedTabs())
    }

    func testStoredTabsReturnsWhatWasPersisted() throws {
        let project = try makeProject()
        let record = TabRecord(edge: .left, title: "main", root: project.layout.blueprint())
        project.persistTabs([record], activeTabID: record.id, enabledEdges: [.left])
        let stored = try XCTUnwrap(project.storedTabs())
        XCTAssertEqual(stored.tabs.map(\.id), [record.id])
        XCTAssertEqual(stored.activeTabID, record.id)
        XCTAssertEqual(stored.enabledEdges, [.left])
    }

    func testFileBrowserDirectoriesAreCachedPerPrimary() throws {
        let project = try makeProject()
        let worktree = tempRoot.appendingPathComponent("wt")
        let first = project.fileBrowserDirectories(primary: worktree)
        let again = project.fileBrowserDirectories(primary: worktree)
        XCTAssertTrue(first === again)
        XCTAssertEqual(first.primary.path, worktree.path)
        XCTAssertFalse(project.fileBrowserDirectories === first)
    }

    func testGitStatusProviderComesFromTheResolver() throws {
        let project = try makeProject()
        let worktree = tempRoot.appendingPathComponent("wt")
        let provider = GitStatusProvider(repoRoot: worktree)
        project.gitStatusProviderResolver = { directory in directory.path == worktree.path ? provider : nil }
        XCTAssertTrue(project.gitStatusProvider(forDirectory: worktree) === provider)
        XCTAssertNil(project.gitStatusProvider(forDirectory: tempRoot))
    }
}
