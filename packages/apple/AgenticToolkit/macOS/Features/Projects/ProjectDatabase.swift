import Foundation
import SQLite3
import AgenticToolkitCore
import AgenticToolkitDatabase

public enum ProjectDatabaseError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case executionFailed(String)
    case invalidSchema(String)
}

/// The app's one database.
///
/// Every project fact lives here — which git repositories exist, what the user
/// calls them, their per-project settings, and the window layout each one opens
/// with — keyed by `git_repo.id`. There is no per-project file: a project is a
/// row and the rows that reference it, which is what lets a repository move on
/// disk without losing anything (`optimize-for-change`).
///
/// One connection, one migration chain, one schema owner. Other stores that
/// share the file (the note store) keep their own migration bookkeeping under
/// their own table name so the two chains cannot collide.
public final class ProjectDatabase {

    var database: OpaquePointer?
    public let databasePath: String

    public static let currentSchemaVersion = 3

    /// `~/.<token>/<Token>.db` — e.g. `~/.coffeegrinder/CoffeeGrinder.db`.
    ///
    /// A dotfolder in the home directory rather than Application Support: this
    /// is the same registry the command line tools read, and asking someone to
    /// type a path with two spaces in it is a hostile default.
    /// - Parameter home: The home directory to hang it off. Defaults to the
    ///   user's; a test passes a temporary one so a run cannot edit the
    ///   developer's own registry (`homeDirectoryForCurrentUser` ignores
    ///   `$HOME`, so there is no ambient way to redirect this).
    public static func defaultPath(inHome home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let token = AppStorageLocation.token
        return AppStorageLocation.directory(inHome: home, token: token)
            .appendingPathComponent("\(token).db")
            .path
    }

    public init(path: String) throws {
        self.databasePath = path
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true)
        }
        try openDatabase()
        try runMigrations()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private func openDatabase() throws {
        let result = sqlite3_open_v2(
            databasePath, &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK else {
            throw ProjectDatabaseError.openFailed(lastErrorMessage)
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        // WAL allows one writer at a time, and this file has more than one
        // connection on it — the notes store opens the same database. Without a
        // busy timeout the loser of a race gets `SQLITE_BUSY` immediately, which
        // surfaces as a lost save rather than a wait.
        sqlite3_busy_timeout(database, 5_000)
    }

    /// Flushes the WAL into the main file so a file-level copy captures every
    /// committed write.
    public func checkpoint() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)
        if try schemaVersion() < 1 {
            try migration001_createSchema()
        }
        if try schemaVersion() < 2 {
            try migration002_dropMissingSince()
        }
        if try schemaVersion() < 3 {
            try migration003_paneSizesAndState()
        }
    }

    private func schemaVersion() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT COALESCE(MAX(version), 0) FROM schema_migrations"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        // Not `?? 0`: a read that failed rather than found nothing would report
        // a fresh database and re-run every migration over a populated one.
        guard try stepRow(stmt) else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// The original schema, left exactly as it shipped. Migrations are
    /// append-only — a fresh database runs this and then every later one, so
    /// this stays the description of v1 rather than of the current shape.
    private func migration001_createSchema() throws {
        try execute("""
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
        """)
        try execute("CREATE INDEX idx_git_repo_name ON git_repo(name)")

        try execute("""
            CREATE TABLE project_setting (
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY (repo_id, key)
            )
        """)

        try execute("""
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
        """)
        try execute("CREATE INDEX idx_layout_nodes_parent ON layout_nodes(parent_id)")
        try execute("CREATE INDEX idx_layout_nodes_repo ON layout_nodes(repo_id)")

        try execute("""
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
        """)
        try execute("CREATE INDEX idx_project_tabs_repo ON project_tabs(repo_id, position)")

        try execute("""
            CREATE TABLE project_state (
                repo_id TEXT PRIMARY KEY REFERENCES git_repo(id) ON DELETE CASCADE,
                active_tab_id TEXT REFERENCES project_tabs(id),
                enabled_edges TEXT NOT NULL DEFAULT 'top'
            )
        """)

        try execute("""
            CREATE TABLE project_directories (
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                path TEXT NOT NULL,
                PRIMARY KEY (repo_id, position)
            )
        """)

        try execute("INSERT INTO schema_migrations (version) VALUES (1)")
    }

    /// Drops `missing_since`.
    ///
    /// v1 kept a repository the scan could not find, on the theory that an
    /// unmounted volume must not cost a project its settings. In practice a
    /// registry built from a whole home directory fills with rows that cannot
    /// be opened and that no scan ever clears. The scan now deletes what it
    /// does not find (`ProjectReconciler.plan`), so nothing writes the column.
    ///
    /// Deliberately does not delete the rows that were marked missing: the
    /// scan that runs moments later is the thing qualified to judge them, and
    /// it keeps — id, settings and layout intact — the ones that turn out to
    /// be on disk after all.
    private func migration002_dropMissingSince() throws {
        try execute("ALTER TABLE git_repo DROP COLUMN missing_since")
        try execute("INSERT INTO schema_migrations (version) VALUES (2)")
    }

    /// The two things a reopened window used to forget: how big each pane was,
    /// and everything a pane knew about itself.
    ///
    /// `thickness_fraction` is nullable because a node nobody has sized is a
    /// real state, distinct from one sized at zero — the descriptor's preferred
    /// fraction is what fills in for it.
    ///
    /// `pane_state` is a bag rather than a column per feature, for the same
    /// reason `project_setting` is: a pane that gains a remembered detail
    /// (a scroll position, a sort order) should not cost a schema migration.
    /// `node_id` is not a foreign key into `layout_nodes` — `saveTabs` deletes
    /// and rewrites that whole table on every layout change, which would
    /// cascade the state away seconds after it was written. `saveTabs` prunes
    /// by node id instead, so state outlives the rewrite but not the pane.
    private func migration003_paneSizesAndState() throws {
        try execute("ALTER TABLE layout_nodes ADD COLUMN thickness_fraction REAL")
        try execute("""
            CREATE TABLE pane_state (
                repo_id TEXT NOT NULL REFERENCES git_repo(id) ON DELETE CASCADE,
                node_id TEXT NOT NULL,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY (repo_id, node_id, key)
            )
        """)
        try execute("INSERT INTO schema_migrations (version) VALUES (3)")
    }

    // MARK: - Repositories

    private static let repoColumns =
        "id, path, name, remote, first_seen, last_seen, last_opened"

    /// Every known repository. They are all repositories the last scan found:
    /// one it did not is deleted, not filtered out here.
    public func allRepos() throws -> [GitRepo] {
        try queryRepos("SELECT \(Self.repoColumns) FROM git_repo ORDER BY name COLLATE NOCASE")
    }

    public func repo(id: UUID) throws -> GitRepo? {
        try queryRepos("SELECT \(Self.repoColumns) FROM git_repo WHERE id = ?") { stmt in
            self.bindText(stmt, 1, id.uuidString)
        }.first
    }

    public func repo(path: String) throws -> GitRepo? {
        try queryRepos("SELECT \(Self.repoColumns) FROM git_repo WHERE path = ?") { stmt in
            self.bindText(stmt, 1, path)
        }.first
    }

    public func insert(_ repo: GitRepo) throws {
        try executeBound("""
            INSERT INTO git_repo (\(Self.repoColumns))
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """) { stmt in
            bindText(stmt, 1, repo.id.uuidString)
            bindText(stmt, 2, repo.path)
            bindText(stmt, 3, repo.name)
            bindOptionalText(stmt, 4, repo.remote)
            sqlite3_bind_double(stmt, 5, repo.firstSeen.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 6, repo.lastSeen.timeIntervalSince1970)
            bindOptionalDate(stmt, 7, repo.lastOpened)
        }
    }

    /// Writes every mutable column. The caller always holds the whole record,
    /// so a per-field update API would be a second representation of the same
    /// knowledge (`dry`).
    public func update(_ repo: GitRepo) throws {
        try executeBound("""
            UPDATE git_repo
            SET path = ?, name = ?, remote = ?, first_seen = ?, last_seen = ?,
                last_opened = ?
            WHERE id = ?
        """) { stmt in
            bindText(stmt, 1, repo.path)
            bindText(stmt, 2, repo.name)
            bindOptionalText(stmt, 3, repo.remote)
            sqlite3_bind_double(stmt, 4, repo.firstSeen.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 5, repo.lastSeen.timeIntervalSince1970)
            bindOptionalDate(stmt, 6, repo.lastOpened)
            bindText(stmt, 7, repo.id.uuidString)
        }
    }

    /// Records that a project window was opened, which is what the browser
    /// sorts "recent" by.
    public func markOpened(id: UUID, at date: Date = Date()) throws {
        try executeBound("UPDATE git_repo SET last_opened = ? WHERE id = ?") { stmt in
            sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
            bindText(stmt, 2, id.uuidString)
        }
    }

    /// Deletes the repository and, by cascade, its settings, tabs and layout.
    public func delete(id: UUID) throws {
        try executeBound("DELETE FROM git_repo WHERE id = ?") { stmt in
            bindText(stmt, 1, id.uuidString)
        }
    }

    private func queryRepos(
        _ sql: String,
        bind: ((OpaquePointer?) -> Void)? = nil
    ) throws -> [GitRepo] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bind?(stmt)
        var repos: [GitRepo] = []
        try forEachRow(stmt) {
            guard let idText = columnText(stmt, 0),
                  let id = UUID(uuidString: idText),
                  let path = columnText(stmt, 1) else { return }
            repos.append(GitRepo(
                id: id,
                path: path,
                name: columnText(stmt, 2) ?? GitRepo.defaultName(forPath: path),
                remote: columnText(stmt, 3),
                firstSeen: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                lastOpened: columnDate(stmt, 6)
            ))
        }
        return repos
    }

    // MARK: - Project settings

    /// A project's settings as a key/value bag.
    ///
    /// Untyped on purpose: the settings a project carries are a moving target,
    /// and a column per setting would mean a migration every time a panel gains
    /// a checkbox. Callers own the meaning of their own keys.
    public func settings(repoID: UUID) throws -> [String: String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT key, value FROM project_setting WHERE repo_id = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bindText(stmt, 1, repoID.uuidString)
        var result: [String: String] = [:]
        try forEachRow(stmt) {
            guard let key = columnText(stmt, 0), let value = columnText(stmt, 1) else { return }
            result[key] = value
        }
        return result
    }

    public func setting(repoID: UUID, key: String) throws -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT value FROM project_setting WHERE repo_id = ? AND key = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bindText(stmt, 1, repoID.uuidString)
        bindText(stmt, 2, key)
        guard try stepRow(stmt) else { return nil }
        return columnText(stmt, 0)
    }

    /// Writing `nil` removes the row, so "unset" and "set to empty" stay
    /// different answers (`explicit-over-implicit`).
    public func setSetting(repoID: UUID, key: String, value: String?) throws {
        guard let value else {
            try executeBound("DELETE FROM project_setting WHERE repo_id = ? AND key = ?") { stmt in
                bindText(stmt, 1, repoID.uuidString)
                bindText(stmt, 2, key)
            }
            return
        }
        try executeBound("""
            INSERT INTO project_setting (repo_id, key, value) VALUES (?, ?, ?)
            ON CONFLICT(repo_id, key) DO UPDATE SET value = excluded.value
        """) { stmt in
            bindText(stmt, 1, repoID.uuidString)
            bindText(stmt, 2, key)
            bindText(stmt, 3, value)
        }
    }

    // MARK: - SQL helpers

    var lastErrorMessage: String {
        if let database { return String(cString: sqlite3_errmsg(database)) }
        return "Database not open"
    }

    @discardableResult
    func execute(_ sql: String) throws -> Int32 {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw ProjectDatabaseError.executionFailed(message)
        }
        return result
    }

    /// Prepares `sql`, lets `bind` populate parameters, then steps once.
    func executeBound(_ sql: String, bind: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw ProjectDatabaseError.executionFailed(lastErrorMessage)
        }
    }

    /// Steps `stmt` to exhaustion, calling `row` once per result row.
    ///
    /// The obvious `while sqlite3_step(stmt) == SQLITE_ROW` ends on anything
    /// that is not a row, and `SQLITE_BUSY` is not a row: a locked database
    /// would end the loop early and be indistinguishable from a short answer.
    /// Every caller here writes back what it read, so a truncated read becomes
    /// a truncated table. Anything but ROW or DONE is raised (`fail-fast`).
    func forEachRow(_ stmt: OpaquePointer?, _ row: () throws -> Void) throws {
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { return }
            guard status == SQLITE_ROW else {
                throw ProjectDatabaseError.executionFailed(lastErrorMessage)
            }
            try row()
        }
    }

    /// Steps once, keeping "there is no such row" and "the read failed" apart.
    @discardableResult
    func stepRow(_ stmt: OpaquePointer?) throws -> Bool {
        let status = sqlite3_step(stmt)
        if status == SQLITE_ROW { return true }
        guard status == SQLITE_DONE else {
            throw ProjectDatabaseError.executionFailed(lastErrorMessage)
        }
        return false
    }

    /// SQLite keeps the pointer, so the string has to outlive the bind call —
    /// which is what `SQLITE_TRANSIENT` asks it to copy. Every text bind in
    /// this file goes through here so none of them can forget.
    func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, Self.sqliteTransient)
    }

    func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value { bindText(stmt, index, value) } else { sqlite3_bind_null(stmt, index) }
    }

    func bindOptionalDate(_ stmt: OpaquePointer?, _ index: Int32, _ value: Date?) {
        if let value {
            sqlite3_bind_double(stmt, index, value.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_text(stmt, index).map { String(cString: $0) }
    }

    func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    func queryScalarString(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) throws -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ProjectDatabaseError.prepareFailed(lastErrorMessage)
        }
        bind?(stmt)
        guard try stepRow(stmt) else { return nil }
        return columnText(stmt, 0)
    }

    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
