import XCTest
import SQLite3
import AgenticToolkitMacOS

/// The project registry's storage contract: a repository is a row, its
/// settings hang off that row, and nothing about it is a file on disk.
@MainActor
final class ProjectDatabaseTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-db-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Repositories

    func testInsertedRepoRoundTripsEveryColumn() throws {
        let database = try makeDatabase()
        let firstSeen = Date(timeIntervalSince1970: 1_000)
        let repo = GitRepo(
            path: "/Users/someone/Development/whippet",
            name: "whippet",
            remote: "git@github.com:someone/whippet.git",
            firstSeen: firstSeen,
            lastSeen: Date(timeIntervalSince1970: 2_000),
            lastOpened: Date(timeIntervalSince1970: 3_000)
        )
        try database.insert(repo)

        let loaded = try XCTUnwrap(database.repo(id: repo.id))
        XCTAssertEqual(loaded.path, repo.path)
        XCTAssertEqual(loaded.name, "whippet")
        XCTAssertEqual(loaded.remote, "git@github.com:someone/whippet.git")
        XCTAssertEqual(loaded.firstSeen.timeIntervalSince1970, 1_000, accuracy: 0.001)
        XCTAssertEqual(loaded.lastOpened?.timeIntervalSince1970, 3_000)
    }

    /// Both lookups have to agree, because a scan finds a repository by path
    /// and everything else refers to it by id.
    func testARepoIsFoundByPathAsWellAsByID() throws {
        let database = try makeDatabase()
        let repo = GitRepo(path: "/tmp/alpha", name: "alpha")
        try database.insert(repo)

        XCTAssertEqual(try database.repo(path: "/tmp/alpha")?.id, repo.id)
        XCTAssertNil(try database.repo(path: "/tmp/never-scanned"))
    }

    /// The path is the one thing two rows can never share: it is how a scan
    /// recognises a repository it already knows.
    func testTwoRowsCannotShareAPath() throws {
        let database = try makeDatabase()
        try database.insert(GitRepo(path: "/tmp/alpha", name: "alpha"))
        XCTAssertThrowsError(try database.insert(GitRepo(path: "/tmp/alpha", name: "alpha again")))
    }

    func testListingIsSortedByNameCaseInsensitively() throws {
        let database = try makeDatabase()
        try database.insert(GitRepo(path: "/tmp/one", name: "zebra"))
        try database.insert(GitRepo(path: "/tmp/two", name: "Apple"))
        try database.insert(GitRepo(path: "/tmp/three", name: "mango"))

        XCTAssertEqual(try database.allRepos().map(\.name), ["Apple", "mango", "zebra"])
    }

    /// v1 kept a repository the scan could not find, marked `missing_since`.
    /// v2 drops the column — and deliberately keeps every row, marked or not:
    /// the scan that follows is what decides which of them are really gone, and
    /// it can only keep a project's id and settings if the row is still there.
    func testOpeningAV1DatabaseDropsMissingSinceAndKeepsEveryRow() throws {
        let path = tempRoot.appendingPathComponent("v1.db").path
        try writeV1Database(at: path)

        let database = try ProjectDatabase(path: path)
        let names = try database.allRepos().map(\.name)
        XCTAssertEqual(names, ["gone", "here"])
        // The column is gone, so every write goes through the v2 shape.
        var repo = try XCTUnwrap(database.repo(path: "/tmp/gone"))
        repo.name = "renamed"
        try database.update(repo)
        XCTAssertEqual(try database.repo(id: repo.id)?.name, "renamed")
    }

    /// v3 is what makes a reopened window look like it did: a size per pane,
    /// and a bag of state per pane. An older file has to gain both on the way
    /// in, or the first save writes to columns that are not there.
    func testOpeningAnOlderDatabaseGainsPaneSizesAndPaneState() throws {
        let path = tempRoot.appendingPathComponent("v1-to-v3.db").path
        try writeV1Database(at: path)

        let database = try ProjectDatabase(path: path)
        let repo = try XCTUnwrap(database.repo(path: "/tmp/here"))
        let leaf = LayoutNode.leaf(contentType: ComposableTabsViewID("test.editor"), thicknessFraction: 0.4)
        let tab = TabRecord(title: "Code", root: leaf)
        try database.saveTabs([tab], activeTabID: tab.id, repoID: repo.id)

        let loaded = try XCTUnwrap(database.loadTabs(repoID: repo.id).tabs.first).root
        XCTAssertEqual(try XCTUnwrap(loaded.thicknessFraction), 0.4, accuracy: 0.0001)

        try database.setPaneState(repoID: repo.id, nodeID: leaf.id, key: "selected", value: "/tmp/a.swift")
        XCTAssertEqual(try database.paneState(repoID: repo.id, nodeID: leaf.id, key: "selected"),
                       "/tmp/a.swift")
    }

    func testMarkOpenedRecordsTheTimeWithoutTouchingAnythingElse() throws {
        let database = try makeDatabase()
        let repo = GitRepo(path: "/tmp/alpha", name: "alpha")
        try database.insert(repo)
        XCTAssertNil(try database.repo(id: repo.id)?.lastOpened)

        try database.markOpened(id: repo.id, at: Date(timeIntervalSince1970: 9_000))

        let loaded = try XCTUnwrap(database.repo(id: repo.id))
        XCTAssertEqual(loaded.lastOpened?.timeIntervalSince1970, 9_000)
        XCTAssertEqual(loaded.name, "alpha")
        XCTAssertEqual(loaded.path, "/tmp/alpha")
    }

    /// The user's name for a project is the one fact about it that no scan may
    /// overwrite, so it has to survive a move.
    func testRenamingAndMovingARepoKeepsItsIdentity() throws {
        let database = try makeDatabase()
        var repo = GitRepo(path: "/tmp/alpha", name: "alpha")
        try database.insert(repo)
        repo.name = "The Alpha Project"
        repo.path = "/tmp/moved/alpha"
        try database.update(repo)

        let loaded = try XCTUnwrap(database.repo(id: repo.id))
        XCTAssertEqual(loaded.name, "The Alpha Project")
        XCTAssertEqual(loaded.path, "/tmp/moved/alpha")
        XCTAssertEqual(try database.allRepos().count, 1)
    }

    // MARK: - Settings

    func testSettingsAreScopedToTheirRepo() throws {
        let database = try makeDatabase()
        let alpha = GitRepo(path: "/tmp/alpha", name: "alpha")
        let beta = GitRepo(path: "/tmp/beta", name: "beta")
        try database.insert(alpha)
        try database.insert(beta)

        try database.setSetting(repoID: alpha.id, key: "terminal.shell", value: "/bin/zsh")
        try database.setSetting(repoID: beta.id, key: "terminal.shell", value: "/bin/bash")

        XCTAssertEqual(try database.setting(repoID: alpha.id, key: "terminal.shell"), "/bin/zsh")
        XCTAssertEqual(try database.settings(repoID: beta.id), ["terminal.shell": "/bin/bash"])
    }

    func testWritingASettingTwiceReplacesIt() throws {
        let database = try makeDatabase()
        let repo = GitRepo(path: "/tmp/alpha", name: "alpha")
        try database.insert(repo)

        try database.setSetting(repoID: repo.id, key: "theme", value: "dark")
        try database.setSetting(repoID: repo.id, key: "theme", value: "light")

        XCTAssertEqual(try database.settings(repoID: repo.id), ["theme": "light"])
    }

    /// "Unset" and "set to empty" are different answers, so `nil` removes the
    /// row rather than storing an empty string.
    func testWritingNilRemovesTheSetting() throws {
        let database = try makeDatabase()
        let repo = GitRepo(path: "/tmp/alpha", name: "alpha")
        try database.insert(repo)

        try database.setSetting(repoID: repo.id, key: "theme", value: "")
        XCTAssertEqual(try database.setting(repoID: repo.id, key: "theme"), "")

        try database.setSetting(repoID: repo.id, key: "theme", value: nil)
        XCTAssertNil(try database.setting(repoID: repo.id, key: "theme"))
    }

    /// Deleting a project takes its configuration with it — there is no file to
    /// throw away, so the cascade is the whole cleanup.
    func testDeletingARepoCascadesToItsSettingsAndDirectories() throws {
        let database = try makeDatabase()
        let repo = GitRepo(path: "/tmp/alpha", name: "alpha")
        try database.insert(repo)
        try database.setSetting(repoID: repo.id, key: "theme", value: "dark")
        try database.saveProjectDirectories(["/tmp/notes"], repoID: repo.id)

        try database.delete(id: repo.id)

        XCTAssertNil(try database.repo(id: repo.id))
        XCTAssertTrue(try database.settings(repoID: repo.id).isEmpty)
        XCTAssertEqual(try database.loadProjectDirectories(repoID: repo.id), [])
    }

    // MARK: - Persistence

    /// Reopening the file has to find the same rows, and re-running migrations
    /// against an already-migrated file has to be a no-op (`idempotency`).
    func testReopeningTheSameFileFindsTheSameRows() throws {
        let path = tempRoot.appendingPathComponent("Reopen.db").path
        let repo = GitRepo(path: "/tmp/alpha", name: "alpha")
        do {
            let database = try ProjectDatabase(path: path)
            try database.insert(repo)
            try database.setSetting(repoID: repo.id, key: "theme", value: "dark")
            try database.checkpoint()
        }
        let reopened = try ProjectDatabase(path: path)
        XCTAssertEqual(try reopened.allRepos().map(\.id), [repo.id])
        XCTAssertEqual(try reopened.setting(repoID: repo.id, key: "theme"), "dark")
    }

    /// The database directory is created on demand: the app's dotfolder does
    /// not exist on a machine that has never run it.
    func testTheDatabaseDirectoryIsCreatedOnDemand() throws {
        let path = tempRoot
            .appendingPathComponent("not-yet-there", isDirectory: true)
            .appendingPathComponent("Projects.db").path
        _ = try ProjectDatabase(path: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    /// The file is named for its contents, not for the app, so two display
    /// names differing only in capitalization resolve to one database rather
    /// than to a real one and an empty one beside it.
    func testDefaultPathIsUnchangedByTheCaseOfTheToken() {
        let home = URL(fileURLWithPath: "/tmp/home")
        XCTAssertEqual(
            ProjectDatabase.defaultPath(inHome: home, token: "COFFEEgrinder"),
            ProjectDatabase.defaultPath(inHome: home, token: "CoffeeGrinder"))
        XCTAssertEqual(
            ProjectDatabase.defaultPath(inHome: home, token: "CoffeeGrinder"),
            "/tmp/home/.coffeegrinder/Projects.db")
    }

    // MARK: - Helpers

    private func makeDatabase() throws -> ProjectDatabase {
        try ProjectDatabase(path: tempRoot.appendingPathComponent("Test.db").path)
    }

    /// The v1 tables the later migrations touch — `git_repo`, and the
    /// v1's tables, plus two repository rows: one the scan had written off and
    /// one it had not. Hand-written rather than produced by the app, because
    /// the app can no longer make a v1 file — which is exactly why the whole
    /// schema is here and not just the one table a given test reads.
    private func writeV1Database(at path: String) throws {
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
                last_opened REAL,
                missing_since REAL
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
                pane_label TEXT
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
            INSERT INTO git_repo (id, path, name, first_seen, last_seen, missing_since)
            VALUES ('\(UUID().uuidString)', '/tmp/gone', 'gone', 1, 1, 5000)
            """,
            """
            INSERT INTO git_repo (id, path, name, first_seen, last_seen)
            VALUES ('\(UUID().uuidString)', '/tmp/here', 'here', 1, 1)
            """,
            "INSERT INTO schema_migrations (version) VALUES (1)"
        ] {
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
        }
    }
}
