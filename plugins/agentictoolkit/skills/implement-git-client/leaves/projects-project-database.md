<!-- leaf: implement-git-client/projects-project-database · source: git-client-projects-project-database.md -->

**Rules** (cite as `implement-git-client/projects-project-database#<slug>`):

- `error-cases` MUST
- `non-sendable-isolation` MUST
- `single-connection-per-instance` MUST
- `connection-serialized-at-the-c-level` MUST
- `shared-file-busy-timeout` MUST
- `wal-and-foreign-keys-set-per-connection` MUST
- `init-creates-parent-directory` MUST
- `init-order-open-then-migrate` MUST
- `default-path-format` MUST
- `default-path-defaults` MUST
- `checkpoint-truncates-wal` MUST
- `deinit-closes-connection` MUST
- `schema-version-constant` MUST
- `migrations-run-in-one-transaction` MUST
- `migration-failure-rolls-back` MUST
- `migrations-are-sequential-and-append-only` MUST
- `schema-version-read` MUST
- `column-existence-check` MUST
- `migration001-schema` MUST
- `migration002-drops-missing-since` MUST
- `migration003-pane-state` MUST
- `migration004-working-directory` MUST
- `migration-idempotency` MUST

# ProjectDatabase

## Overview

`ProjectDatabase` is the project browser's single SQLite-backed registry: one file, one connection, one append-only migration chain, holding every fact about every git repository the app knows about — its `git_repo` row (identity, path, name, remote, timestamps) and its per-project settings key/value bag. Per its header doc comment, "there is no per-project file: a project is a row and the rows that reference it," which is what lets a repository move on disk without losing its settings, layout, or user-assigned name (`optimize-for-change`). The class owns exactly one `sqlite3` connection per instance, opens it and brings its schema current synchronously inside `init(path:)`, and exposes CRUD for `git_repo` rows and `project_setting` rows as its public surface. This file's own migrations create the tables a sibling extension file, `ProjectDatabase+Layout.swift` (a separate source, out of scope for this recipe), later reads and writes for layout, tab, and pane-state data; the note store that shares this same on-disk file keeps its own migration bookkeeping under its own table name so the two chains cannot collide.

## Behavioral Requirements

### Errors

- **error-cases**: `ProjectDatabaseError` MUST declare exactly four cases — `openFailed(String)`, `prepareFailed(String)`, `executionFailed(String)`, and `invalidSchema(String)` — each carrying a `String` message. Only `openFailed`, `prepareFailed`, and `executionFailed` are constructed and thrown by any method in this file; `invalidSchema` is declared here but is thrown only by other `ProjectDatabase` methods defined in `ProjectDatabase+Layout.swift`, a sibling file in the same module and out of scope for this recipe.

### Identity and concurrency

- **non-sendable-isolation**: `ProjectDatabase` MUST be declared as a plain `final class` with no `Sendable` conformance, no `actor` keyword, and no `@MainActor` annotation; an instance is not safe to share across concurrency domains without the caller's own synchronization, and the compiler enforces that by keeping it in the isolation domain of whichever context created it.
- **single-connection-per-instance**: Each `ProjectDatabase` instance MUST own exactly one SQLite connection, stored in `database: OpaquePointer?`, opened once in `init(path:)` and closed once in `deinit`; no method in this file opens a second connection or reassigns `database` after `init` returns.
- **connection-serialized-at-the-c-level**: `openDatabase()` MUST pass `SQLITE_OPEN_FULLMUTEX` alongside `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE` when opening the connection; this serializes every call into that connection at the SQLite C level, so multiple threads MAY call methods on the same `ProjectDatabase` instance concurrently without corrupting the connection, though calls remain otherwise unordered relative to one another beyond that serialization.
- **shared-file-busy-timeout**: `openDatabase()` MUST call `sqlite3_busy_timeout(database, 5_000)` so that when another connection to the same file — explicitly "the notes store," per the doc comment — holds the write lock, a call on this connection blocks for up to 5,000 milliseconds waiting for that lock rather than failing immediately with `SQLITE_BUSY`.
- **wal-and-foreign-keys-set-per-connection**: `openDatabase()` MUST execute `PRAGMA journal_mode=WAL` and `PRAGMA foreign_keys=ON` every time a connection is opened, because SQLite's foreign-key enforcement is a per-connection setting that does not persist inside the database file; a connection opened without re-issuing `PRAGMA foreign_keys=ON` would silently accept writes that violate the cascade relationships declared in migration001.

### Lifecycle

- **init-creates-parent-directory**: `init(path:)` MUST derive the parent directory from `path` via `(path as NSString).deletingLastPathComponent` and, when that derived directory is non-empty, MUST call `FileManager.default.createDirectory(atPath:withIntermediateDirectories: true)` before opening the connection.
- **init-order-open-then-migrate**: `init(path:)` MUST call `openDatabase()` before `runMigrations()`; either call throwing MUST propagate out of `init` and MUST prevent the `ProjectDatabase` instance from being returned to the caller.
- **default-path-format**: `ProjectDatabase.defaultPath(inHome:token:)` MUST return `AppStorageLocation.directory(inHome: home, token: token).appendingPathComponent("Projects.db").path` — a dotfolder named after the lowercased, alphanumeric-only storage token directly under `home`, containing a file literally named `Projects.db`.
- **default-path-defaults**: `defaultPath(inHome:token:)` MUST default `home` to `FileManager.default.homeDirectoryForCurrentUser` and `token` to `AppStorageLocation.token` when the caller supplies neither.
- **checkpoint-truncates-wal**: `checkpoint()` MUST execute `PRAGMA wal_checkpoint(TRUNCATE)`, flushing every committed write from the WAL file into the main database file.
- **deinit-closes-connection**: `deinit` MUST call `sqlite3_close(database)` when `database` is non-`nil`, and MUST NOT call it when `database` is `nil`.

### Migrations

- **schema-version-constant**: `ProjectDatabase.currentSchemaVersion` MUST be the `Int` literal `4`, matching the highest version number any migration in this file inserts into `schema_migrations`.
- **migrations-run-in-one-transaction**: `runMigrations()` MUST wrap the `schema_migrations` table creation and every pending migration in a single `BEGIN IMMEDIATE TRANSACTION` … `COMMIT`, and MUST issue `BEGIN IMMEDIATE` rather than a deferred `BEGIN`, taking the write lock before the first schema statement runs rather than on first write.
- **migration-failure-rolls-back**: If any statement inside `runMigrations()`'s `do` block throws, `runMigrations()` MUST execute `ROLLBACK` (via `try? execute("ROLLBACK")`, discarding that call's own result) and MUST rethrow the original error; the file MUST be left exactly as it was before `runMigrations()` was called.
- **migrations-are-sequential-and-append-only**: `runMigrations()` MUST run `migration001_createSchema`, `migration002_dropMissingSince`, `migration003_paneSizesAndState`, and `migration004_tabWorkingDirectory`, in that fixed order, and MUST run each one if and only if `schemaVersion()` is currently less than that migration's target version; a migration MUST NOT be skipped because a later migration already ran, and MUST NOT run twice in the same `init` call.
- **schema-version-read**: `schemaVersion()` MUST return `SELECT COALESCE(MAX(version), 0) FROM schema_migrations` as an `Int`, and MUST distinguish "the query found no rows" (via `stepRow` returning `false`, yielding `0`) from "the query failed" (which `stepRow` raises as `ProjectDatabaseError.executionFailed`) rather than collapsing both to `0` with `??`.
- **column-existence-check**: `columnExists(_:in:)` MUST query `pragma_table_info(?)` bound to the table name, filtered by the bound column name, and MUST return `true` only when the count is greater than zero; every migration that adds or drops a column MUST call this first and skip the `ALTER TABLE` when the column is already in the state that migration would produce.
- **migration001-schema**: `migration001_createSchema()` MUST create, each guarded by `IF NOT EXISTS`, the tables `git_repo` (`id TEXT PRIMARY KEY`, `path TEXT NOT NULL UNIQUE`, `name TEXT NOT NULL`, `remote TEXT`, `first_seen REAL NOT NULL`, `last_seen REAL NOT NULL`, `last_opened REAL`, `missing_since REAL`), `project_setting` (primary key `(repo_id, key)`, `repo_id REFERENCES git_repo(id) ON DELETE CASCADE`), `layout_nodes` (a self-referencing `parent_id REFERENCES layout_nodes(id) ON DELETE CASCADE` and `kind TEXT NOT NULL CHECK(kind IN ('split','leaf'))`), `project_tabs`, `project_state` (`repo_id TEXT PRIMARY KEY REFERENCES git_repo(id) ON DELETE CASCADE`), and `project_directories`; plus indexes `idx_git_repo_name`, `idx_layout_nodes_parent`, `idx_layout_nodes_repo`, and `idx_project_tabs_repo`; and MUST insert version row `1` last.
- **migration002-drops-missing-since**: `migration002_dropMissingSince()` MUST drop the `git_repo.missing_since` column only if `columnExists("missing_since", in: "git_repo")` returns `true`, MUST NOT delete any row from `git_repo` regardless of whether that row previously had `missing_since` set, and MUST insert version row `2`.
- **migration003-pane-state**: `migration003_paneSizesAndState()` MUST add a nullable `layout_nodes.thickness_fraction REAL` column when it does not already exist, MUST create table `pane_state` with columns `repo_id`, `node_id`, `key`, `value` and primary key `(repo_id, node_id, key)`, MUST declare `repo_id REFERENCES git_repo(id) ON DELETE CASCADE` on `pane_state`, and MUST NOT declare any foreign-key reference on `pane_state.node_id`.
- **migration004-working-directory**: `migration004_tabWorkingDirectory()` MUST add a nullable `project_tabs.working_directory TEXT` column when it does not already exist, and MUST insert version row `4`.
- **migration-idempotency**: Re-running `init(path:)` — and therefore `runMigrations()` — against a database file that already has every migration applied MUST be a no-op that leaves every row unchanged, and re-running it against a file whose `schema_migrations` rows were partially or entirely deleted while the schema itself is already current MUST also complete without error, because every `CREATE TABLE`, `CREATE INDEX`, and `ALTER TABLE` statement in every migration is guarded by `IF NOT EXISTS` or a preceding `columnExists` check (`idempotency`).

