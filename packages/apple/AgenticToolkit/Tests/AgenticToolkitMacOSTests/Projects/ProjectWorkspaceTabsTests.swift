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

    /// A window showing the main checkout *and* a worktree holds two
    /// `FileBrowserDirectories`, each with its own copy of the one list stored
    /// per repository. Each writes the whole list back on any change, so the
    /// second one to save used to write its snapshot — taken before the first
    /// one's addition — over the newer list, and the added folder vanished
    /// with no error.
    func testARootAddedInOneBrowserReachesTheOtherAndSurvivesItsNextSave() throws {
        let project = try makeProject()
        let worktree = tempRoot.appendingPathComponent("wt")
        let addedFromMain = tempRoot.appendingPathComponent("added-from-main")
        let addedFromWorktree = tempRoot.appendingPathComponent("added-from-worktree")

        let mainRoots = project.fileBrowserDirectories(primary: tempRoot)
        let worktreeRoots = project.fileBrowserDirectories(primary: worktree)

        mainRoots.add(addedFromMain)
        XCTAssertEqual(
            worktreeRoots.additional.map(\.path),
            [addedFromMain.resolvingSymlinksInPath().path],
            "the sibling browser must see the addition, not its own stale snapshot"
        )

        worktreeRoots.add(addedFromWorktree)
        XCTAssertEqual(
            Set(project.projectDirectories().map { $0.resolvingSymlinksInPath().path }),
            Set([addedFromMain, addedFromWorktree].map { $0.resolvingSymlinksInPath().path })
        )
        XCTAssertEqual(mainRoots.additional.map(\.path), worktreeRoots.additional.map(\.path))
    }

    /// The stored list may name a directory that is some *other* browser's
    /// primary — the user added the main checkout as a root while looking at a
    /// worktree. That browser's own `additional` never contains its primary,
    /// so its next save would drop the entry unless the merge puts it back.
    func testARootThatIsAnotherBrowsersPrimaryIsNotDroppedByThatBrowsersSave() throws {
        let project = try makeProject()
        let worktree = tempRoot.appendingPathComponent("wt")
        let addedFromMain = tempRoot.appendingPathComponent("added-from-main")

        let mainRoots = project.fileBrowserDirectories(primary: tempRoot)
        let worktreeRoots = project.fileBrowserDirectories(primary: worktree)

        worktreeRoots.add(tempRoot)
        XCTAssertTrue(mainRoots.additional.isEmpty, "a browser never lists its own primary as an added root")

        mainRoots.add(addedFromMain)
        XCTAssertEqual(
            Set(project.projectDirectories().map { $0.resolvingSymlinksInPath().path }),
            Set([tempRoot, addedFromMain].map { $0.resolvingSymlinksInPath().path })
        )
    }
}
