---
id: c212ea39-10e7-4146-89dd-36edb3b3455a
title: ProjectDatabase
domain: agentictoolkit://recipes/git-client-projects-project-database
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: SQLite-backed registry of known git repositories, their settings, and the
  schema migration chain that keeps one shared database file current.
platforms:
- swift
- macos
tags:
- git
- projects
- database
- sqlite
- persistence
- migrations
depends-on: []
related:
- agentictoolkit://recipes/git-client-projects-git-repo
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Database/AppStorageLocation.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectDatabaseTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

### Repository CRUD

- **repo-column-set**: `allRepos()`, `repo(id:)`, and `repo(path:)` MUST all select exactly the columns named by `repoColumns` — `id, path, name, remote, first_seen, last_seen, last_opened` — in that order; `missing_since` MUST NOT appear in any `SELECT`, because migration002 has already dropped it from the live schema by the time these methods can run.
- **all-repos-ordering**: `allRepos()` MUST order its results by `name COLLATE NOCASE` ascending, so repositories named `"Apple"`, `"mango"`, and `"zebra"` sort in that order regardless of case.
- **all-repos-includes-every-known-row**: `allRepos()` MUST return every row currently in `git_repo`; per the doc comment, "one [the scanner] did not [find] is deleted, not filtered out here" — `allRepos()` itself performs no filtering by recency, missing state, or any other criterion.
- **repo-lookup-by-id-and-path**: `repo(id:)` MUST filter by `id = ?` bound to `id.uuidString`, and `repo(path:)` MUST filter by `path = ?` bound to the given string; both MUST return `nil` when no row matches, via `.first` on an empty `queryRepos` result.
- **repo-insert-column-set**: `insert(_:)` MUST insert all seven `repoColumns` in a single `INSERT` bound in order to `repo.id.uuidString`, `repo.path`, `repo.name`, `repo.remote` (nullable), `repo.firstSeen`, `repo.lastSeen`, and `repo.lastOpened` (nullable); inserting a `GitRepo` whose `path` duplicates an existing row's `path` MUST throw `ProjectDatabaseError.executionFailed`, because `git_repo.path` is declared `UNIQUE` in migration001.
- **repo-update-column-set**: `update(_:)` MUST overwrite `path`, `name`, `remote`, `first_seen`, `last_seen`, and `last_opened` for the row matching `repo.id`, and MUST NOT provide any narrower, per-field update method — per the doc comment, "the caller always holds the whole record, so a per-field update API would be a second representation of the same knowledge" (`dry`); `update(_:)` MUST NOT change `id`.
- **mark-opened-updates-only-last-opened**: `markOpened(id:at:)` MUST update only the `last_opened` column for the row matching `id`, defaulting `at` to `Date()` evaluated at the call site, and MUST leave `path`, `name`, `remote`, `first_seen`, and `last_seen` on that row unchanged.
- **delete-cascades**: `delete(id:)` MUST execute `DELETE FROM git_repo WHERE id = ?`; per the `ON DELETE CASCADE` foreign keys declared on `project_setting.repo_id`, `layout_nodes.repo_id`, `project_tabs.repo_id`, `project_state.repo_id`, `project_directories.repo_id`, and (from migration003) `pane_state.repo_id`, deleting a `git_repo` row MUST cause SQLite to also delete every row in those six tables that references it, with no additional statement issued by `delete(id:)` itself.

### Settings CRUD

- **settings-scoped-per-repo**: `settings(repoID:)` MUST return every `(key, value)` pair in `project_setting` whose `repo_id` equals the given `UUID`, as a `[String: String]`, and MUST NOT return rows belonging to any other `repo_id`.
- **setting-single-key-lookup**: `setting(repoID:key:)` MUST return the single `value` for the given `(repoID, key)` pair, or `nil` when no such row exists.
- **set-setting-nil-deletes**: `setSetting(repoID:key:value:)` MUST delete the matching `(repo_id, key)` row from `project_setting` when `value` is `nil`, and MUST NOT write an empty-string row in that case; per the doc comment, "'unset' and 'set to empty' stay different answers" (`explicit-over-implicit`).
- **set-setting-upsert**: `setSetting(repoID:key:value:)` MUST insert a new `(repo_id, key, value)` row when none exists for that pair, MUST overwrite `value` in place — via `INSERT … ON CONFLICT(repo_id, key) DO UPDATE SET value = excluded.value` — when a row for that pair already exists, and MUST NOT create a second row for the same `(repo_id, key)` pair.

### Internal SQL plumbing (non-public contract)

- **text-binds-copy-the-string**: `bindText(_:_:_:)` MUST bind with `Self.sqliteTransient`, instructing SQLite to copy the string's bytes at bind time rather than retain the Swift `String`'s own storage; every text-valued bind in this file MUST go through `bindText`, `bindOptionalText`, or a call that itself calls one of them, so no bound string can be read after it has been deallocated.
- **step-loop-fails-on-anything-but-row-or-done**: `forEachRow(_:_:)` MUST treat any `sqlite3_step` result other than `SQLITE_ROW` or `SQLITE_DONE` — including `SQLITE_BUSY` — as a thrown `ProjectDatabaseError.executionFailed`, and MUST NOT treat such a result as "no more rows"; per the doc comment, "a locked database would end the loop early and be indistinguishable from a short answer" (`fail-fast`).
- **step-row-fails-on-anything-but-row-or-done**: `stepRow(_:)` MUST return `true` on `SQLITE_ROW`, `false` on `SQLITE_DONE`, and MUST throw `ProjectDatabaseError.executionFailed` for any other status.
- **last-error-message-fallback**: `lastErrorMessage` MUST return `sqlite3_errmsg(database)` when `database` is non-`nil`, and MUST return the literal string `"Database not open"` when `database` is `nil`.
- **module-internal-helpers-not-public**: `columnExists`, `schemaVersion`, `queryRepos`, `execute`, `executeBound`, `forEachRow`, `stepRow`, `bindText`, `bindOptionalText`, `bindOptionalDate`, `columnText`, `columnDate`, `queryScalarString`, and the `database` property itself MUST all be declared without the `public` modifier, restricting them to callers in the same module; `queryScalarString` MUST NOT be called by any method in this file, existing solely for `ProjectDatabase+Layout.swift`, a sibling extension in the same module, to call.

### Malformed row handling

- **malformed-row-handling**: NEEDS REVIEW: Not implemented in source. `queryRepos(_:bind:)`'s per-row guard — `guard let idText = columnText(stmt, 0), let id = UUID(uuidString: idText), let path = columnText(stmt, 1) else { return }` — silently omits any row whose `id` column is not a parseable UUID string or whose `path` column is `NULL`, from `allRepos()`, `repo(id:)`, and `repo(path:)` alike, with no thrown error, no logged message, and no way for a caller to learn a row was skipped. What is missing: whether a row failing this guard should instead throw `ProjectDatabaseError` (surfacing the corrupt row to the caller) or be reported through some other channel is not decided anywhere in this file or its tests. Evidence that would settle it: a test exercising a hand-corrupted `git_repo` row (the way `writeV1Database` in `ProjectDatabaseTests.swift` hand-writes a v1 file) and an explicit statement of the intended behavior from whoever owns this component.

## Appearance

Not applicable — this is a SQLite-backed persistence component, not a visual component.

## States

Not applicable — this is a SQLite-backed persistence component, not a visual component.

## Accessibility

Not applicable — this is a SQLite-backed persistence component, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-database-001 | repo-insert-column-set | Insert `GitRepo(path: "/Users/someone/Development/whippet", name: "whippet", remote: "git@github.com:someone/whippet.git", firstSeen: Date(timeIntervalSince1970: 1_000), lastSeen: Date(timeIntervalSince1970: 2_000), lastOpened: Date(timeIntervalSince1970: 3_000))`, then call `repo(id:)` (`ProjectDatabaseTests.swift`, `testInsertedRepoRoundTripsEveryColumn`). | The loaded `GitRepo` has the same `path`, `name`, `remote`, `firstSeen` (accuracy 0.001), and `lastOpened` as the value inserted. |
| git-client-projects-project-database-002 | repo-lookup-by-id-and-path | Insert `GitRepo(path: "/tmp/alpha", name: "alpha")`, then call `repo(path: "/tmp/alpha")` and `repo(path: "/tmp/never-scanned")` (`testARepoIsFoundByPathAsWellAsByID`). | `repo(path: "/tmp/alpha")?.id == repo.id`; `repo(path: "/tmp/never-scanned")` returns `nil`. |
| git-client-projects-project-database-003 | repo-insert-column-set | Insert `GitRepo(path: "/tmp/alpha", name: "alpha")`, then insert a second `GitRepo(path: "/tmp/alpha", name: "alpha again")` (`testTwoRowsCannotShareAPath`). | The second `insert(_:)` call throws `ProjectDatabaseError.executionFailed`, because `git_repo.path` is `UNIQUE`. |
| git-client-projects-project-database-004 | all-repos-ordering | Insert repos named `"zebra"`, `"Apple"`, `"mango"` in that order, then call `allRepos()` (`testListingIsSortedByNameCaseInsensitively`). | Returns them in the order `["Apple", "mango", "zebra"]`. |
| git-client-projects-project-database-005 | migration002-drops-missing-since, migration-idempotency | Hand-write a v1-schema database file with two rows, one carrying `missing_since`, then open it with `ProjectDatabase(path:)` (`testOpeningAV1DatabaseDropsMissingSinceAndKeepsEveryRow`). | `allRepos().map(\.name) == ["gone", "here"]`; both rows survive the migration to v4, and updating either row afterward succeeds. |
| git-client-projects-project-database-006 | migration-idempotency | Insert a repo, delete only the `schema_migrations` row for version 4, then reopen the same file with a fresh `ProjectDatabase(path:)` (`testAMigrationWhoseVersionRowIsMissingReRunsWithoutFailing`). | Reopening does not throw; the previously inserted repo is still readable by `repo(id:)`. |
| git-client-projects-project-database-007 | migration-idempotency | Insert a repo, delete every row from `schema_migrations`, then reopen the same file (`testTheWholeMigrationChainIsSafeToReRunOverACurrentSchema`). | Reopening does not throw; the previously inserted repo is still readable by `repo(id:)`. |
| git-client-projects-project-database-008 | mark-opened-updates-only-last-opened | Insert `GitRepo(path: "/tmp/alpha", name: "alpha")` with no `lastOpened`, call `markOpened(id: repo.id, at: Date(timeIntervalSince1970: 9_000))` (`testMarkOpenedRecordsTheTimeWithoutTouchingAnythingElse`). | `repo(id:)?.lastOpened?.timeIntervalSince1970 == 9_000`; `name` and `path` are unchanged. |
| git-client-projects-project-database-009 | repo-update-column-set | Insert `GitRepo(path: "/tmp/alpha", name: "alpha")`, mutate `name` and `path` locally, call `update(_:)` (`testRenamingAndMovingARepoKeepsItsIdentity`). | `repo(id:)` returns the new `name` and `path` under the same `id`; `allRepos().count` is still `1`. |
| git-client-projects-project-database-010 | set-setting-nil-deletes, set-setting-upsert | Call `setSetting(repoID:key: "theme", value: "")`, then `setSetting(repoID:key: "theme", value: nil)` (`testWritingNilRemovesTheSetting`). | After the empty-string write, `setting(repoID:key: "theme") == ""`; after the `nil` write, `setting(repoID:key: "theme")` returns `nil`. |
| git-client-projects-project-database-011 | delete-cascades | Insert a repo, set one setting on it, then call `delete(id:)` (`testDeletingARepoCascadesToItsSettingsAndDirectories`). | `repo(id:)` returns `nil`; `settings(repoID:)` for that id returns an empty dictionary. |
| git-client-projects-project-database-012 | default-path-format, default-path-defaults | Call `ProjectDatabase.defaultPath(inHome: URL(fileURLWithPath: "/tmp/home"), token: "COFFEEgrinder")` and again with `token: "CoffeeGrinder"` (`testDefaultPathIsUnchangedByTheCaseOfTheToken`). | Both calls return the identical string `"/tmp/home/.coffeegrinder/Projects.db"`. |
| git-client-projects-project-database-013 | init-creates-parent-directory | Construct `ProjectDatabase(path:)` with a path whose parent directory does not yet exist (`testTheDatabaseDirectoryIsCreatedOnDemand`). | `init` succeeds, and `FileManager.default.fileExists(atPath: path)` is `true` afterward. |

## Edge Cases

- **Null and empty input (MUST)**: An empty `path` argument to `init(path:)` produces `directory = ""` via `deletingLastPathComponent`, so `init` skips `createDirectory` entirely (the `!directory.isEmpty` guard) and passes the empty string straight to `sqlite3_open_v2`; nothing in this file rejects an empty `path` before that call, and `openFailed` is thrown only when the result code is not `SQLITE_OK`. Similarly, `insert(_:)` and `update(_:)` accept a `GitRepo` whose `path` or `name` is the empty string with no validation of either; the only value this file treats specially is a `nil` passed to `setSetting`'s `value:` parameter, which deletes the row rather than storing it (see `set-setting-nil-deletes`).
- **Boundary values (MUST)**: `schemaVersion()`'s boundaries are exactly `< 1`, `< 2`, `< 3`, and `< 4` — a database already at version 4 runs none of the four migration functions; a database whose `schema_migrations` table exists but is empty reads as version `0` and runs all four. `columnExists`'s boundary is `COUNT(*) > 0` against `pragma_table_info`, i.e. exactly zero or one matching row, since SQLite disallows two columns of the same name on one table.
- **Concurrent access (MUST)**: A single `ProjectDatabase` instance's one connection is opened with `SQLITE_OPEN_FULLMUTEX`, so concurrent calls into the same instance from multiple threads cannot corrupt the connection, but are otherwise unordered relative to one another beyond SQLite's own serialization. A second connection to the same file — this file's own doc comment names "the notes store" as sharing it — contends for the WAL write lock; `sqlite3_busy_timeout(database, 5_000)` makes a call on the losing connection block up to 5 seconds rather than fail immediately, and if the timeout still elapses, `forEachRow`/`stepRow`/`executeBound` surface the resulting `SQLITE_BUSY` as `ProjectDatabaseError.executionFailed` rather than retrying or silently dropping the write.
- **Error states (MUST)**: Every SQL failure this file's own code can produce — a failed `sqlite3_open_v2`, a failed `sqlite3_prepare_v2`, a non-`SQLITE_OK` result from `sqlite3_exec`, or a `sqlite3_step` result other than `ROW`/`DONE` — is surfaced to the caller as a thrown `ProjectDatabaseError` case carrying `sqlite3_errmsg`'s text; no method in this file returns a sentinel value in place of throwing when a SQL statement fails to prepare or execute. The one exception is the malformed-row path in `queryRepos` (see `malformed-row-handling`), which drops a row instead of throwing.
- **Offline or disconnected state**: Not applicable — `ProjectDatabase.swift` opens a local file with `sqlite3_open_v2` and makes no network call of any kind; there is no connectivity for this component to lose.
- **Missing file or unreachable directory (MUST)**: When `FileManager.default.createDirectory(atPath:withIntermediateDirectories:)` fails (for example, a permissions error on the parent directory), that thrown error propagates out of `init(path:)` unchanged; `init` does not wrap or translate it into a `ProjectDatabaseError`, so a caller catching only `ProjectDatabaseError` cases would not catch this particular failure.
- **Cancellation and timeouts (MUST)**: No method in this file is `async`, and none checks a cancellation flag of any kind; `sqlite3_busy_timeout`'s 5-second wait is the only timeout of any kind in this file, and it blocks the calling thread synchronously for up to that long with no way for a caller to interrupt it early from this file's own code.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` (`init`) | `String` | none — required | Absolute filesystem path to the SQLite file; not validated as absolute, non-empty, or writable before use (see Edge Cases: Null and empty input). |
| `home` (`defaultPath(inHome:token:)`) | `URL` | `FileManager.default.homeDirectoryForCurrentUser` | The directory `defaultPath` hangs the storage dotfolder off of. |
| `token` (`defaultPath(inHome:token:)`) | `String` | `AppStorageLocation.token` (the running app's `CFBundleName`, alphanumeric-filtered) | Names the shared dotfolder this file's database lives in alongside other stores. |
| `at` (`markOpened(id:at:)`) | `Date` | `Date()` at the call site | The timestamp recorded as `last_opened`. |
| `value` (`setSetting(repoID:key:value:)`) | `String?` | none — required | `nil` deletes the setting row; any `String`, including the empty string, upserts it. |

The busy timeout (5,000 milliseconds) and `currentSchemaVersion` (`4`) are fixed constants in this file, not exposed as configuration a caller can override.

## Deep Linking

Not applicable: `ProjectDatabase.swift` defines no URL scheme, route, or navigation destination — it is a persistence layer with no UI surface to link to.

## Localization

Not applicable: `ProjectDatabase.swift` builds no string intended for an end user to read. The only text this file produces beyond SQL statements is the diagnostic message carried inside a `ProjectDatabaseError` payload (via `lastErrorMessage`, and `sqlite3_exec`'s error pointer) — a raw SQLite or OS error string with no localization key — but nothing in this file presents that string to a user; it exists to be caught and handled programmatically by a caller.

## Accessibility Options

Not applicable: `ProjectDatabase.swift` renders nothing, so Reduce Motion, Increase Contrast, and Differentiate Without Color have no surface in this file to apply to.

## Feature Flags

Not applicable: `ProjectDatabase.swift` contains no feature-flag, build-configuration, or conditional-compilation check of any kind gating any of its behavior.

## Analytics

Not applicable: `ProjectDatabase.swift` makes no analytics or event-tracking call of any kind.

## Privacy

- **Data collected**: `git_repo.path` (an absolute filesystem path, which under a typical macOS home directory embeds the user's account name), `git_repo.remote` (a git remote URL, stored verbatim exactly as `GitRepo.remote` was already read out of `.git/config` by another component), and `project_setting.value` (an arbitrary caller-supplied string keyed by an arbitrary caller-supplied `key`, per the doc comment "callers own the meaning of their own keys,") — this file does not know or constrain what a caller stores there.
- **Storage**: Every one of those values is written, unencrypted, to a single SQLite file on local disk at `databasePath`, with `journal_mode=WAL` meaning committed data can additionally live in a `-wal` file alongside the main database file until `checkpoint()` or SQLite's own auto-checkpoint truncates it. Nothing in this file encrypts the file, redacts a `remote` URL that happens to embed user-info credentials, or restricts the file's POSIX permissions beyond whatever `FileManager.default.createDirectory` and `sqlite3_open_v2` default to.
- **Transmission**: None — `ProjectDatabase.swift` makes no network call; every method operates on the local file through the SQLite C API.
- **Retention**: Indefinite. A `git_repo` row, its settings, and its cascaded layout, tab, and pane rows persist until `delete(id:)` is called for that row (cascading via the foreign keys described in `delete-cascades`) or the file itself is removed by something outside this file; nothing in this file expires or prunes data on its own.

## Logging

Not applicable: `ProjectDatabase.swift` contains no `Logger`, `os.log`, `print`, or any other logging call — every diagnostic detail (a SQLite error message) is returned to the caller through a thrown `ProjectDatabaseError`, not written to a log by this file.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift`, importing only `Foundation`, `SQLite3` (the C SQLite library linked directly, not `Core Data` or `SwiftData`), `AgenticToolkitCore`, and `AgenticToolkitDatabase` (for `AppStorageLocation`); it depends on no UI framework, and a caller anywhere in a SwiftUI app — an `@Observable` view model, an `App`'s startup code — constructs and owns one instance directly.
- **Compose**: Port the SQLite access with `androidx.sqlite` or a light wrapper over `android.database.sqlite.SQLiteOpenHelper`/`SQLiteDatabase`, keeping the same one-connection-per-store shape; run the four migrations inside `SQLiteDatabase.beginTransactionNonExclusive()`/`endTransaction()`, re-issue the `foreign_keys=ON` pragma per connection the same way `openDatabase()` does, and represent `GitRepo` as the Kotlin `data class` the sibling `GitRepo` recipe already specifies.
- **React/Web**: A browser has no filesystem or SQLite; if this pattern is ported into a Node-hosted process (e.g. an Electron main process or a local dev server), use `better-sqlite3` or `node:sqlite`, apply the same `PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=ON`, and a busy-timeout equivalent (`better-sqlite3`'s `pragma('busy_timeout = 5000')`), and run the migration chain inside one transaction — checking `PRAGMA table_info` for column existence the same way `columnExists` does before any `ALTER TABLE`.
- **AppKit / UIKit**: Identical to the SwiftUI note — nothing in this file is tied to a UI framework; it ports unchanged to either, or to a headless command-line tool, since the doc comment on `defaultPath` explicitly notes "this is the same registry the command line tools read".
- **WinUI 3**: Port with `Microsoft.Data.Sqlite` (or the raw `sqlite3` P/Invoke layer for closer fidelity) rather than `Windows.Storage`'s roaming or local settings APIs, since this component's contract is relational rows with foreign-key cascades, not key-value settings storage. Open the connection, then issue `PRAGMA journal_mode=WAL;` and `PRAGMA foreign_keys=ON;` immediately after, exactly as `openDatabase()` does, and issue `PRAGMA busy_timeout=5000;` to match the 5-second wait (`Microsoft.Data.Sqlite` has no dedicated `SQLITE_OPEN_FULLMUTEX` flag, but serializes access per connection by default, preserving the same one-connection, thread-safe-by-default shape). Run the four migrations inside a transaction opened with `BEGIN IMMEDIATE;`/`COMMIT;`/`ROLLBACK;` issued as raw command text the way `execute(_:)` does here, guarding each `ALTER TABLE` with a `PRAGMA table_info('table')` read the way `columnExists` does. Model `GitRepo` as the C# `record` the sibling `GitRepo` recipe specifies, and keep `ProjectDatabase`'s own methods synchronous — this file performs every SQL call synchronously on the caller's thread — letting a `Task.Run` at the call site, not inside this component, move a call off a UI dispatcher thread.

## Design Decisions

**Decision**: The database's default location is a dotfolder in the home directory (`~/.<token>/Projects.db`) rather than `Application Support`.
**Rationale**: Per the doc comment on `defaultPath`, this is "the same registry the command line tools read, and asking someone to type a path with two spaces in it is a hostile default" — `Application Support` paths on macOS commonly contain spaces, which complicates command-line and script access to the same file a GUI app writes.
**Approved**: pending

**Decision**: The file is named `Projects.db` unconditionally, never after the storage token itself.
**Rationale**: Per the doc comment, naming the file after the token too was tried and reverted: the directory name is lowercased for matching but the file name was not, so a display-name capitalization change alone resolved to the same directory but a different, empty file that `openDatabase` would then create and migrate from scratch beside the real one. Naming the file after its contents rather than the app removes that second, independently-foldable spelling of the app's name.
**Approved**: pending

**Decision**: `runMigrations()` wraps the `schema_migrations` table creation and all four migrations in one `BEGIN IMMEDIATE TRANSACTION` … `COMMIT`, and every individual migration statement is additionally guarded by `IF NOT EXISTS` or a `columnExists` check.
**Rationale**: Per the doc comment, before this transaction existed, a crash, kill, or power loss between a schema statement and the `INSERT` recording it left the schema changed with `schema_migrations` still behind it; the next launch re-ran the already-applied schema statement, `ALTER TABLE … ADD COLUMN` failed with a duplicate-column error, and `init(path:)` threw on that launch and every one after it, with every project, tab, and pane state in the file permanently unreachable. The transaction makes a half-applied state unreachable going forward; the per-statement guards make re-running the chain over a database an older, un-transacted build already left half-applied safe rather than fatal (`idempotency`).
**Approved**: pending

**Decision**: `openDatabase()` opens with `SQLITE_OPEN_FULLMUTEX`, sets `journal_mode=WAL`, and calls `sqlite3_busy_timeout(database, 5_000)`.
**Rationale**: Per the doc comment, this file is not the only connection to this database — "the notes store opens the same database" — and WAL mode allows only one writer at a time; without a busy timeout, the connection that loses a write race gets `SQLITE_BUSY` immediately, "which surfaces as a lost save rather than a wait." A 5-second timeout trades a bounded stall for a save that would otherwise silently fail to persist.
**Approved**: pending

**Decision**: `pane_state.node_id` (added in migration003) carries no foreign key back to `layout_nodes`, even though every row it stores is conceptually scoped to one layout node.
**Rationale**: Per the doc comment, `layout_nodes` is deleted and rewritten wholesale on every layout change elsewhere in the module; a foreign key from `pane_state` to `layout_nodes` would cascade-delete a pane's remembered state seconds after it was written, on the very next save. Pruning `pane_state` by node id is left to the code that performs that rewrite, so state "outlives the rewrite but not the pane."
**Approved**: pending

**Decision**: `migration002_dropMissingSince()` drops the `missing_since` column but does not delete any row that previously had it set.
**Rationale**: Per the doc comment, the scan that runs immediately after a database is opened is "the thing qualified to judge" whether a previously-missing repository is really gone; deleting those rows here, before that scan has run, would discard a repository's id, settings, and layout the moment a v1 database is opened, even for repositories that turn out to still be on disk.
**Approved**: pending

**Decision**: `schemaVersion()` reads `COALESCE(MAX(version), 0)` and returns `0` only when `stepRow` finds no row, never by substituting a failed read with `?? 0`.
**Rationale**: Per the doc comment, collapsing "the query found nothing" and "the query failed to run" into the same `0` would make a read that failed for some other reason look like a fresh database, causing `runMigrations()` to re-run every migration over a database that already has data and possibly already has some of that schema in place — a bug this file avoids by letting `stepRow`'s own error path propagate instead.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: separation-of-concerns passes because `ProjectDatabase.swift` holds only schema, migration, and CRUD statements against its own tables — it performs no directory scanning, no reconciliation, and no window or layout business logic beyond storing and returning the rows another component reads and writes. unit-test-coverage is partial: `ProjectDatabaseTests.swift` exercises every public repository and settings method plus five distinct migration scenarios (a fresh database, a v1-to-v4 upgrade, a version row deleted mid-chain, the whole chain rewound, and directory-on-demand creation), but `checkpoint()` has no assertion verifying the WAL file was actually truncated, and the row-dropping path this recipe flags under `malformed-row-handling` has no test anywhere in the given sources. explicit-error-handling is partial for the same reason: every SQL-level failure this file's own statements can produce throws a specific `ProjectDatabaseError` case, but the malformed-row guard in `queryRepos` is the one path in this file that discards a failure signal instead of raising it — see the open question on `malformed-row-handling`. data-integrity is partial: the `UNIQUE` constraint on `git_repo.path`, the `ON DELETE CASCADE` foreign keys, and the transaction-wrapped, idempotency-guarded migration chain are all real, exercised integrity mechanisms, but this file never calls `PRAGMA integrity_check` and has no detection at all for a row that fails to parse on the way out of the database — again, the open question on `malformed-row-handling`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation; documents the migration transaction's crash-safety rationale and the open question on malformed-row handling. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
