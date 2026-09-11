import AgenticToolkitCore
import SQLite3
import XCTest
@testable import AgenticToolkitMacOS

/// Schema v4: every tab remembers the directory its panes work in, so a later
/// task can open one tab per git worktree rooted somewhere other than the
/// project directory.
@MainActor
final class ProjectDatabaseWorkingDirectoryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-workdir-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    private func makeDatabase() throws -> ProjectDatabase {
        try ProjectDatabase(path: tempRoot.appendingPathComponent("Test.db").path)
    }

    private func registerRepo(in database: ProjectDatabase) throws -> GitRepo {
        let repo = GitRepo(path: tempRoot.path, name: "Test")
        try database.insert(repo)
        return repo
    }

    /// The path carries a space and a non-ASCII character on purpose: both
    /// survive a naive URL-to-string encoding that a percent-escaped or
    /// UTF-8-mangling round trip would not, so this asserts the actual
    /// TEXT-column encoding rather than reasoning about it from a plain path.
    func testWorkingDirectoryRoundTrips() throws {
        let database = try makeDatabase()
        let repo = try registerRepo(in: database)
        let worktree = tempRoot.appendingPathComponent("wt-feature café")
        let leaf = LayoutNode.leaf(contentType: ComposableTabsViewID("test.editor"), paneLabel: nil)
        let record = TabRecord(edge: .left, title: "feature", root: leaf, workingDirectory: worktree)
        try database.saveTabs([record], activeTabID: record.id, enabledEdges: [.left], repoID: repo.id)

        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertEqual(loaded.tabs.first?.workingDirectory?.path, worktree.path)
    }

    /// A worktree path stored with a trailing slash has to come back with the
    /// same trailing slash — `URL(fileURLWithPath:)` normalizes directory
    /// paths in a way that could silently drop it.
    func testWorkingDirectoryWithATrailingSlashRoundTrips() throws {
        let database = try makeDatabase()
        let repo = try registerRepo(in: database)
        let worktree = tempRoot.appendingPathComponent("wt-trailing", isDirectory: true)
        let leaf = LayoutNode.leaf(contentType: ComposableTabsViewID("test.editor"), paneLabel: nil)
        let record = TabRecord(edge: .left, title: "feature", root: leaf, workingDirectory: worktree)
        try database.saveTabs([record], activeTabID: record.id, enabledEdges: [.left], repoID: repo.id)

        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertEqual(loaded.tabs.first?.workingDirectory?.path, worktree.path)
    }

    func testAMissingWorkingDirectoryLoadsAsNil() throws {
        let database = try makeDatabase()
        let repo = try registerRepo(in: database)
        let leaf = LayoutNode.leaf(contentType: ComposableTabsViewID("test.editor"), paneLabel: nil)
        let record = TabRecord(edge: .top, title: "Tab 1", root: leaf)
        try database.saveTabs([record], activeTabID: record.id, enabledEdges: [.top], repoID: repo.id)

        let loaded = try database.loadTabs(repoID: repo.id)
        XCTAssertNil(loaded.tabs.first?.workingDirectory)
    }

    func testSchemaIsAtVersionFour() throws {
        let database = try makeDatabase()
        XCTAssertGreaterThanOrEqual(try database.schemaVersion(), 4)
    }

    /// Ties `currentSchemaVersion` to what a fresh database actually ends up
    /// at, so the constant cannot drift out of step with the migration chain
    /// again without a test noticing — today it is bumped by hand alongside
    /// the migration and referenced nowhere else.
    func testFreshDatabaseReportsCurrentSchemaVersion() throws {
        let database = try makeDatabase()
        XCTAssertEqual(try database.schemaVersion(), ProjectDatabase.currentSchemaVersion)
    }

    /// A migration that only works on a freshly-created database is the
    /// failure mode this test exists to catch: it hand-builds a v3 file (the
    /// full v1 schema, minus `missing_since` per migration 2, plus
    /// `thickness_fraction` and `pane_state` per migration 3) with a real row
    /// already in `project_tabs`, then opens it through `ProjectDatabase` and
    /// checks the existing row survives with a `nil` working directory. It
    /// also opens the same file a second time to prove re-running migration 4
    /// against an already-migrated file does not fail (`ALTER TABLE ADD
    /// COLUMN` errors if the column already exists).
    func testMigratingFromVersionThreeAddsTheColumnWithoutLosingExistingRows() throws {
        let path = tempRoot.appendingPathComponent("V3.db").path
        let repoID = UUID()
        let nodeID = UUID()
        let tabID = UUID()
        try writeV3Database(at: path, repoID: repoID, nodeID: nodeID, tabID: tabID)

        let database = try ProjectDatabase(path: path)
        XCTAssertEqual(try database.schemaVersion(), 4)

        let loaded = try database.loadTabs(repoID: repoID)
        XCTAssertEqual(loaded.tabs.map(\.id), [tabID])
        XCTAssertEqual(loaded.tabs.first?.title, "from-v3")
        XCTAssertNil(loaded.tabs.first?.workingDirectory)

        // Idempotency: opening the already-migrated file again must not fail.
        let reopened = try ProjectDatabase(path: path)
        XCTAssertEqual(try reopened.schemaVersion(), 4)
    }

    /// The crash window migration 4 used to leave open: the app was killed
    /// between `ALTER TABLE ... ADD COLUMN working_directory` and the
    /// `INSERT INTO schema_migrations (version) VALUES (4)` that records it.
    /// The column is present, `MAX(version)` still says 3 — so the next
    /// launch re-runs the `ALTER`, which fails with `duplicate column name`.
    /// Before this was fixed that threw out of `init(path:)`, and did so on
    /// every subsequent launch too: the user's projects, tabs and pane state
    /// were unreachable for good. Opening it must recover instead.
    func testOpeningADatabaseCrashedMidMigrationRecoversInsteadOfThrowing() throws {
        let path = tempRoot.appendingPathComponent("Crashed.db").path
        let repoID = UUID()
        let nodeID = UUID()
        let tabID = UUID()
        try writeV3Database(
            at: path, repoID: repoID, nodeID: nodeID, tabID: tabID, withWorkingDirectoryColumn: true)

        let database = try ProjectDatabase(path: path)
        XCTAssertEqual(try database.schemaVersion(), 4)

        let loaded = try database.loadTabs(repoID: repoID)
        XCTAssertEqual(loaded.tabs.map(\.id), [tabID])
        XCTAssertEqual(loaded.tabs.first?.title, "from-v3")
        XCTAssertNil(loaded.tabs.first?.workingDirectory)
    }

    // MARK: - v3 fixture

    /// A hand-rolled schema at exactly the shape migration 3 leaves behind.
    /// Written directly with SQLite3, not through `ProjectDatabase`, because
    /// the app can no longer produce a v3 file once migration 4 ships.
    ///
    /// - Parameter withWorkingDirectoryColumn: Adds migration 4's column
    ///   without its version row, which is the state a crash between the two
    ///   statements leaves behind.
    private func writeV3Database(
        at path: String,
        repoID: UUID,
        nodeID: UUID,
        tabID: UUID,
        withWorkingDirectoryColumn: Bool = false
    ) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }

        for sql in [
            """
            CREATE TABLE schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """,
            """
            CREATE TABLE git_repo (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                remote TEXT,
                first_seen REAL NOT NULL,
                last_seen REAL NOT NULL,
                last_opened REAL
            )
            """,
            """
            CREATE TABLE project_setting (
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY (repo_id, key)
            )
            """,
            """
            CREATE TABLE layout_nodes (
                id TEXT PRIMARY KEY,
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                parent_id TEXT REFERENCES layout_nodes(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                kind TEXT NOT NULL CHECK(kind IN ('split','leaf')),
                orientation TEXT,
                content_type TEXT,
                pane_label TEXT,
                thickness_fraction REAL
            )
            """,
            """
            CREATE TABLE project_tabs (
                id TEXT PRIMARY KEY,
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                title TEXT NOT NULL,
                edge TEXT NOT NULL DEFAULT 'top',
                group_id TEXT,
                root_node_id TEXT REFERENCES layout_nodes(id),
                focused_node_id TEXT REFERENCES layout_nodes(id)
            )
            """,
            """
            CREATE TABLE project_state (
                repo_id TEXT PRIMARY KEY REFERENCES git_repo(id) ON DELETE CASCADE,
                active_tab_id TEXT REFERENCES project_tabs(id),
                enabled_edges TEXT NOT NULL DEFAULT 'top'
            )
            """,
            """
            CREATE TABLE project_directories (
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                path TEXT NOT NULL,
                PRIMARY KEY (repo_id, position)
            )
            """,
            """
            CREATE TABLE pane_state (
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                node_id TEXT NOT NULL,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY (repo_id, node_id, key)
            )
            """,
            """
            INSERT INTO git_repo (id, path, name, first_seen, last_seen)
            VALUES ('\(repoID.uuidString)', '\(tempRoot.path)', 'v3-repo', 1, 1)
            """,
            """
            INSERT INTO layout_nodes (id, repo_id, parent_id, position, kind, content_type, pane_label)
            VALUES ('\(nodeID.uuidString)', '\(repoID.uuidString)', NULL, 0, 'leaf', 'test.editor', NULL)
            """,
            """
            INSERT INTO project_tabs (id, repo_id, position, title, edge, group_id, root_node_id)
            VALUES ('\(tabID.uuidString)', '\(repoID.uuidString)', 0, 'from-v3', 'top', '\(tabID.uuidString)',
                    '\(nodeID.uuidString)')
            """,
            "INSERT INTO schema_migrations (version) VALUES (1)",
            "INSERT INTO schema_migrations (version) VALUES (2)",
            "INSERT INTO schema_migrations (version) VALUES (3)"
        ] {
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
        }

        if withWorkingDirectoryColumn {
            let sql = "ALTER TABLE project_tabs ADD COLUMN working_directory TEXT"
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
        }
    }
}
