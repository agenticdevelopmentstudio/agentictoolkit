---
id: c212ea39-10e7-4146-89dd-36edb3b3455a
title: Project Database
domain: agentictoolkit://cookbook/workspace/projects/project-database
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/workspace/projects/git-repo
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Database/AppStorageLocation.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectDatabaseTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Database

## Overview

This component is the project browser's single SQLite-backed registry: one
file, one connection, one append-only migration chain, holding every fact
about every git repository the app knows about — its `git_repo` row
(identity, path, name, remote, timestamps) and its per-project settings
key/value bag. Per its own design rationale, "there is no per-project file:
a project is a row and the rows that reference it," which is what lets a
repository move on disk without losing its settings, layout, or
user-assigned name (`optimize-for-change`). It owns exactly one SQLite
connection per instance, opens it and brings its schema current
synchronously as part of construction, and exposes CRUD for `git_repo` rows
and `project_setting` rows as its public surface. Its own migrations create
the tables a sibling extension (a separate source file, out of scope for
this recipe) later reads and writes for layout, tab, and pane-state data;
the note store that shares this same on-disk file keeps its own migration
bookkeeping under its own table name so the two chains cannot collide.

## Behavioral Requirements

### Errors

- **error-cases**: The set of error cases this component can raise MUST be
  exactly four — an open failure, a prepare failure, an execution failure,
  and an invalid-schema failure — each carrying a message string. Only the
  open-failure, prepare-failure, and execution-failure cases are
  constructed and raised by any method described in this file; the
  invalid-schema case is declared here but is raised only by other methods
  of this same component defined in a sibling extension source, out of
  scope for this recipe.

### Identity and concurrency

- **caller-must-synchronize-cross-thread-access**: This component MUST be
  implemented as a plain reference type with no built-in concurrency-safety
  guarantee of its own — no actor isolation, no automatic thread
  confinement, and no compiler-enforced concurrency-safety marker; an
  instance is not safe to share across concurrency domains without the
  caller's own synchronization.
- **single-connection-per-instance**: Each instance of this component MUST
  own exactly one SQLite connection, opened once during construction and
  closed once when the instance is torn down; no method in this file opens
  a second connection or reassigns the stored connection after construction
  completes.
- **connection-serialized-at-the-c-level**: Opening the connection MUST
  pass `SQLITE_OPEN_FULLMUTEX` alongside `SQLITE_OPEN_READWRITE |
  SQLITE_OPEN_CREATE`; this serializes every call into that connection at
  the SQLite C level, so multiple threads MAY call methods on the same
  instance concurrently without corrupting the connection, though calls
  remain otherwise unordered relative to one another beyond that
  serialization.
- **shared-file-busy-timeout**: Opening the connection MUST call
  `sqlite3_busy_timeout(database, 5_000)` so that when another connection
  to the same file — the note store, per this component's own design
  rationale — holds the write lock, a call on this connection blocks for
  up to 5,000 milliseconds waiting for that lock rather than failing
  immediately with `SQLITE_BUSY`.
- **wal-and-foreign-keys-set-per-connection**: Opening the connection MUST
  execute `PRAGMA journal_mode=WAL` and `PRAGMA foreign_keys=ON` every time
  a connection is opened, because SQLite's foreign-key enforcement is a
  per-connection setting that does not persist inside the database file; a
  connection opened without re-issuing `PRAGMA foreign_keys=ON` would
  silently accept writes that violate the cascade relationships declared in
  migration 1.

### Lifecycle

- **init-creates-parent-directory**: Constructing this component MUST
  derive the parent directory from the given path and, when that derived
  directory is non-empty, MUST create it (including any missing
  intermediate directories) before opening the connection.
- **init-order-open-then-migrate**: Constructing this component MUST open
  the connection before running migrations; either step failing MUST
  propagate out of construction and MUST prevent the instance from being
  returned to the caller.
- **default-path-format**: The default path MUST be a dotfolder named
  after the lowercased, alphanumeric-only storage token, directly under the
  given home directory, containing a file literally named `Projects.db`.
- **default-path-defaults**: The default path's parameters MUST default
  `home` to the current user's home directory and `token` to the shared
  storage token used by other stores when the caller supplies neither.
- **checkpoint-truncates-wal**: Checkpointing MUST execute `PRAGMA
  wal_checkpoint(TRUNCATE)`, flushing every committed write from the WAL
  file into the main database file.
- **connection-closed-on-teardown**: Tearing down an instance MUST close
  the SQLite connection when one is open, and MUST NOT attempt to close it
  when none is open.

### Migrations

- **schema-version-constant**: The current schema version constant MUST be
  `4`, matching the highest version number any migration in this component
  inserts into `schema_migrations`.
- **migrations-run-in-one-transaction**: Running migrations MUST wrap the
  `schema_migrations` table creation and every pending migration in a
  single `BEGIN IMMEDIATE TRANSACTION` … `COMMIT`, and MUST issue `BEGIN
  IMMEDIATE` rather than a deferred `BEGIN`, taking the write lock before
  the first schema statement runs rather than on first write.
- **migration-failure-rolls-back**: If any statement during running
  migrations fails, running migrations MUST execute `ROLLBACK`
  (discarding any error from that rollback attempt itself) and MUST
  propagate the original failure to the caller; the file MUST be left
  exactly as it was before running migrations began.
- **migrations-are-sequential-and-append-only**: Running migrations MUST
  run migration 1, migration 2, migration 3, and migration 4, in that
  fixed order, and MUST run each one if and only if the current schema
  version is less than that migration's target version; a migration MUST
  NOT be skipped because a later migration already ran, and MUST NOT run
  twice in the same construction call.
- **schema-version-read**: Reading the schema version MUST return `SELECT
  COALESCE(MAX(version), 0) FROM schema_migrations` as an integer, and MUST
  distinguish "the query found no rows" (yielding `0`) from "the query
  failed" (raising a thrown execution-failure error) rather than collapsing
  both to `0` by substituting a default for any failure.
- **column-existence-check**: Checking whether a column exists MUST query
  `pragma_table_info(?)` bound to the table name, filtered by the bound
  column name, and MUST return true only when the count is greater than
  zero; every migration that adds or drops a column MUST call this first
  and skip the `ALTER TABLE` when the column is already in the state that
  migration would produce.
- **migration001-schema**: Migration 1 MUST create, each guarded by `IF NOT
  EXISTS`, the tables `git_repo` (`id TEXT PRIMARY KEY`, `path TEXT NOT
  NULL UNIQUE`, `name TEXT NOT NULL`, `remote TEXT`, `first_seen REAL NOT
  NULL`, `last_seen REAL NOT NULL`, `last_opened REAL`, `missing_since
  REAL`), `project_setting` (primary key `(repo_id, key)`, `repo_id
  REFERENCES git_repo(id) ON DELETE CASCADE`), `layout_nodes` (a
  self-referencing `parent_id REFERENCES layout_nodes(id) ON DELETE
  CASCADE` and `kind TEXT NOT NULL CHECK(kind IN ('split','leaf'))`),
  `project_tabs`, `project_state` (`repo_id TEXT PRIMARY KEY REFERENCES
  git_repo(id) ON DELETE CASCADE`), and `project_directories`; plus indexes
  `idx_git_repo_name`, `idx_layout_nodes_parent`, `idx_layout_nodes_repo`,
  and `idx_project_tabs_repo`; and MUST insert version row `1` last.
- **migration002-drops-missing-since**: Migration 2 MUST drop the
  `git_repo.missing_since` column only if that column exists on
  `git_repo`, MUST NOT delete any row from `git_repo` regardless of
  whether that row previously had `missing_since` set, and MUST insert
  version row `2`.
- **migration003-pane-state**: Migration 3 MUST add a nullable
  `layout_nodes.thickness_fraction REAL` column when it does not already
  exist, MUST create table `pane_state` with columns `repo_id`, `node_id`,
  `key`, `value` and primary key `(repo_id, node_id, key)`, MUST declare
  `repo_id REFERENCES git_repo(id) ON DELETE CASCADE` on `pane_state`, and
  MUST NOT declare any foreign-key reference on `pane_state.node_id`.
- **migration004-working-directory**: Migration 4 MUST add a nullable
  `project_tabs.working_directory TEXT` column when it does not already
  exist, and MUST insert version row `4`.
- **migration-idempotency**: Re-running construction — and therefore
  running migrations — against a database file that already has every
  migration applied MUST be a no-op that leaves every row unchanged, and
  re-running it against a file whose `schema_migrations` rows were
  partially or entirely deleted while the schema itself is already current
  MUST also complete without error, because every `CREATE TABLE`, `CREATE
  INDEX`, and `ALTER TABLE` statement in every migration is guarded by `IF
  NOT EXISTS` or a preceding column-existence check (`idempotency`).

### Repository CRUD

- **repo-column-set**: Listing every repository, looking one up by id, and
  looking one up by path MUST all select exactly the columns `id, path,
  name, remote, first_seen, last_seen, last_opened`, in that order;
  `missing_since` MUST NOT appear in any `SELECT`, because migration 2 has
  already dropped it from the live schema by the time these operations can
  run.
- **all-repos-ordering**: Listing every repository MUST order its results
  by `name COLLATE NOCASE` ascending, so repositories named "Apple",
  "mango", and "zebra" sort in that order regardless of case.
- **all-repos-includes-every-known-row**: Listing every repository MUST
  return every row currently in `git_repo`; per this component's own
  design rationale, "one [the scanner] did not [find] is deleted, not
  filtered out here" — listing performs no filtering by recency, missing
  state, or any other criterion.
- **repo-lookup-by-id-and-path**: Looking up a repository by id MUST
  filter by `id = ?` bound to the id's string form, and looking up by path
  MUST filter by `path = ?` bound to the given string; both MUST return
  nothing when no row matches.
- **repo-insert-column-set**: Inserting a repository MUST insert all seven
  columns in a single `INSERT` bound in order to the repository's id,
  path, name, remote (nullable), first-seen time, last-seen time, and
  last-opened time (nullable); inserting a repository whose path
  duplicates an existing row's path MUST raise an execution-failure error,
  because `git_repo.path` is declared `UNIQUE` in migration 1.
- **repo-update-column-set**: Updating a repository MUST overwrite `path`,
  `name`, `remote`, `first_seen`, `last_seen`, and `last_opened` for the
  row matching its id, and MUST NOT provide any narrower, per-field update
  operation — per this component's own design rationale, "the caller
  always holds the whole record, so a per-field update API would be a
  second representation of the same knowledge" (`dry`); updating a
  repository MUST NOT change its id.
- **mark-opened-updates-only-last-opened**: Marking a repository opened
  MUST update only the `last_opened` column for the row matching its id,
  defaulting the recorded time to the current time when the caller
  supplies none, and MUST leave `path`, `name`, `remote`, `first_seen`,
  and `last_seen` on that row unchanged.
- **delete-cascades**: Deleting a repository MUST execute `DELETE FROM
  git_repo WHERE id = ?`; per the `ON DELETE CASCADE` foreign keys
  declared on `project_setting.repo_id`, `layout_nodes.repo_id`,
  `project_tabs.repo_id`, `project_state.repo_id`,
  `project_directories.repo_id`, and (from migration 3)
  `pane_state.repo_id`, deleting a `git_repo` row MUST cause SQLite to
  also delete every row in those six tables that references it, with no
  additional statement issued by this operation itself.

### Settings CRUD

- **settings-scoped-per-repo**: Reading a repository's settings MUST
  return every `(key, value)` pair in `project_setting` whose `repo_id`
  equals the given repository id, as a key/value map, and MUST NOT return
  rows belonging to any other repository.
- **setting-single-key-lookup**: Looking up a single setting MUST return
  the value for the given repository-id/key pair, or nothing when no such
  row exists.
- **set-setting-nil-deletes**: Setting a value MUST delete the matching
  `(repo_id, key)` row from `project_setting` when the given value is
  absent, and MUST NOT write an empty-string row in that case; per this
  component's own design rationale, "'unset' and 'set to empty' stay
  different answers" (`explicit-over-implicit`).
- **set-setting-upsert**: Setting a value MUST insert a new `(repo_id,
  key, value)` row when none exists for that pair, MUST overwrite the
  value in place — via `INSERT … ON CONFLICT(repo_id, key) DO UPDATE SET
  value = excluded.value` — when a row for that pair already exists, and
  MUST NOT create a second row for the same `(repo_id, key)` pair.

### Internal SQL plumbing (non-public contract)

- **text-binds-copy-the-string**: Every text bind in this file MUST
  instruct SQLite to copy the string's bytes at bind time rather than
  retain the language runtime's own string storage, so no bound string can
  be read after it has been deallocated.
- **step-loop-fails-on-anything-but-row-or-done**: A row-iteration loop
  MUST treat any step result other than "row" or "done" — including
  `SQLITE_BUSY` — as a thrown execution-failure error, and MUST NOT treat
  such a result as "no more rows"; per this component's own design
  rationale, "a locked database would end the loop early and be
  indistinguishable from a short answer" (`fail-fast`).
- **step-row-fails-on-anything-but-row-or-done**: Stepping a single-row
  query MUST return true on "row", false on "done", and MUST throw an
  execution-failure error for any other status.
- **last-error-message-fallback**: Reading the last error message MUST
  return SQLite's own error text when a connection is open, and MUST
  return the literal string "Database not open" when it is not.

### Malformed row handling

- **malformed-row-handling**: NEEDS REVIEW: Not implemented in source. The
  per-row guard applied when reading repository rows silently omits any
  row whose id column is not a parseable UUID string or whose path column
  is null, from every repository-listing and lookup operation alike, with
  no thrown error, no logged message, and no way for a caller to learn a
  row was skipped. What is missing: whether a row failing this guard
  should instead throw an error (surfacing the corrupt row to the caller)
  or be reported through some other channel is not decided anywhere in
  this file or its tests. Evidence that would settle it: a test exercising
  a hand-corrupted `git_repo` row (the way a hand-written v1 fixture
  already does in this component's own test suite) and an explicit
  statement of the intended behavior from whoever owns this component.

## Appearance

Not applicable — this is a SQLite-backed persistence component, not a
visual component.

## States

Not applicable — this is a SQLite-backed persistence component, not a
visual component.

## Accessibility

Not applicable — this is a SQLite-backed persistence component, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-database-001 | repo-insert-column-set | Insert a repository record with path "/Users/someone/Development/whippet", name "whippet", remote "git@github.com:someone/whippet.git", first-seen time 1,000 seconds since the epoch, last-seen time 2,000 seconds since the epoch, and last-opened time 3,000 seconds since the epoch, then look it up by id. | The loaded record has the same path, name, remote, first-seen time (within 0.001 seconds), and last-opened time as the value inserted. |
| git-client-projects-project-database-002 | repo-lookup-by-id-and-path | Insert a repository record with path "/tmp/alpha" and name "alpha", then look it up by path "/tmp/alpha" and by path "/tmp/never-scanned". | The first lookup's id equals the inserted record's id; the second lookup returns nothing. |
| git-client-projects-project-database-003 | repo-insert-column-set | Insert a repository record with path "/tmp/alpha" and name "alpha", then insert a second record with the same path "/tmp/alpha" and name "alpha again". | The second insert raises an execution-failure error, because `git_repo.path` is `UNIQUE`. |
| git-client-projects-project-database-004 | all-repos-ordering | Insert repositories named "zebra", "Apple", "mango" in that order, then list every repository. | Returns them in the order ["Apple", "mango", "zebra"]. |
| git-client-projects-project-database-005 | migration002-drops-missing-since, migration-idempotency | Hand-write a v1-schema database file with two rows, one carrying `missing_since`, then open it. | Listing every repository by name returns ["gone", "here"]; both rows survive the migration to v4, and updating either row afterward succeeds. |
| git-client-projects-project-database-006 | migration-idempotency | Insert a repository, delete only the `schema_migrations` row for version 4, then reopen the same file. | Reopening does not fail; the previously inserted repository is still readable by id. |
| git-client-projects-project-database-007 | migration-idempotency | Insert a repository, delete every row from `schema_migrations`, then reopen the same file. | Reopening does not fail; the previously inserted repository is still readable by id. |
| git-client-projects-project-database-008 | mark-opened-updates-only-last-opened | Insert a repository with no last-opened time, then mark it opened at time 9,000 seconds since the epoch. | Looking it up by id returns a last-opened time of 9,000 seconds since the epoch; its name and path are unchanged. |
| git-client-projects-project-database-009 | repo-update-column-set | Insert a repository with path "/tmp/alpha" and name "alpha", change its name and path locally, then update it. | Looking it up by id returns the new name and path under the same id; listing every repository still returns exactly 1 row. |
| git-client-projects-project-database-010 | set-setting-nil-deletes, set-setting-upsert | Set the "theme" setting to the empty string, then set the "theme" setting to absent (unset it). | After the empty-string write, looking up "theme" returns the empty string; after the unset write, looking up "theme" returns nothing. |
| git-client-projects-project-database-011 | delete-cascades | Insert a repository, set one setting on it, then delete it. | Looking it up by id returns nothing; reading its settings returns an empty map. |
| git-client-projects-project-database-012 | default-path-format, default-path-defaults | Compute the default path for home directory "/tmp/home" and token "COFFEEgrinder", and again for token "CoffeeGrinder". | Both calls return the identical string "/tmp/home/.coffeegrinder/Projects.db". |
| git-client-projects-project-database-013 | init-creates-parent-directory | Construct this component with a path whose parent directory does not yet exist. | Construction succeeds, and the parent directory exists on disk afterward. |

## Edge Cases

- **Null and empty input (MUST)**: An empty path argument to construction
  produces an empty parent directory, so construction skips creating a
  directory entirely and passes the empty string straight to opening the
  connection; nothing in this file rejects an empty path before that call,
  and an open-failure error is thrown only when the underlying open call
  does not succeed. Similarly, inserting or updating a repository accepts
  a record whose path or name is the empty string with no validation of
  either; the only value this file treats specially is an absent value
  passed to setting a value, which deletes the row rather than storing it
  (see **set-setting-nil-deletes**).
- **Boundary values (MUST)**: Reading the schema version's boundaries are
  exactly less-than-1, less-than-2, less-than-3, and less-than-4 — a
  database already at version 4 runs none of the four migrations; a
  database whose `schema_migrations` table exists but is empty reads as
  version 0 and runs all four. Checking whether a column exists has a
  boundary of "greater than zero matching rows" against
  `pragma_table_info` — i.e. exactly zero or one matching row, since
  SQLite disallows two columns of the same name on one table.
- **Concurrent access (MUST)**: A single instance's one connection is
  opened with `SQLITE_OPEN_FULLMUTEX`, so concurrent calls into the same
  instance from multiple threads cannot corrupt the connection, but are
  otherwise unordered relative to one another beyond SQLite's own
  serialization. A second connection to the same file — this component's
  own design rationale names the note store as sharing it — contends for
  the WAL write lock; `sqlite3_busy_timeout(database, 5_000)` makes a call
  on the losing connection block up to 5 seconds rather than fail
  immediately, and if the timeout still elapses, the row-iteration and
  single-row-step operations surface the resulting `SQLITE_BUSY` as an
  execution-failure error rather than retrying or silently dropping the
  write.
- **Error states (MUST)**: Every SQL failure this file's own code can
  produce — a failed connection open, a failed statement prepare, a
  non-`SQLITE_OK` result from executing a statement, or a step result
  other than "row"/"done" — is surfaced to the caller as a thrown error
  case carrying SQLite's own error text; no method in this file returns a
  sentinel value in place of throwing when a SQL statement fails to
  prepare or execute. The one exception is the malformed-row path (see
  **malformed-row-handling**), which drops a row instead of throwing.
- **Offline or disconnected state**: Not applicable — this component opens
  a local file and makes no network call of any kind; there is no
  connectivity for this component to lose.
- **Missing file or unreachable directory (MUST)**: When creating the
  parent directory fails (for example, a permissions error on the parent
  directory), that thrown error propagates out of construction unchanged;
  construction does not wrap or translate it into one of this component's
  own error cases, so a caller catching only those cases would not catch
  this particular failure.
- **Cancellation and timeouts (MUST)**: No operation in this file is
  asynchronous, and none checks a cancellation flag of any kind; the
  busy-timeout's 5-second wait is the only timeout of any kind in this
  file, and it blocks the calling thread synchronously for up to that long
  with no way for a caller to interrupt it early from this file's own
  code.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` (construction parameter) | string | none — required | Absolute filesystem path to the SQLite file; not validated as absolute, non-empty, or writable before use (see Edge Cases: Null and empty input). |
| `home` (default-path parameter) | directory reference | the current user's home directory | The directory the default path hangs the storage dotfolder off of. |
| `token` (default-path parameter) | string | the shared storage token used by other stores (derived from the running app's name, alphanumeric-filtered) | Names the shared dotfolder this file's database lives in alongside other stores. |
| `at` (mark-opened parameter) | timestamp | the current time at the call site | The timestamp recorded as `last_opened`. |
| `value` (set-setting parameter) | string, optional | none — required | Absent deletes the setting row; any string, including the empty string, upserts it. |

The busy timeout (5,000 milliseconds) and the current schema version
constant (`4`) are fixed constants in this file, not exposed as
configuration a caller can override.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination — it is a persistence layer with no UI surface to link to.

## Localization

Not applicable: this component builds no string intended for an end user
to read. The only text this file produces beyond SQL statements is the
diagnostic message carried inside a thrown error's payload (SQLite's or
the OS's own error string) — a raw error string with no localization key —
but nothing in this file presents that string to a user; it exists to be
caught and handled programmatically by a caller.

## Accessibility Options

Not applicable: this component renders nothing, so Reduce Motion, Increase
Contrast, and Differentiate Without Color have no surface in this file to
apply to.

## Feature Flags

Not applicable: this component contains no feature-flag, build-configuration,
or conditional-compilation check of any kind gating any of its behavior.

## Analytics

Not applicable: this component makes no analytics or event-tracking call of
any kind.

## Privacy

- **Data collected**: `git_repo.path` (an absolute filesystem path, which
  under a typical home directory embeds the user's account name),
  `git_repo.remote` (a git remote URL, stored verbatim exactly as it was
  already read out of the repository's own config by another component),
  and `project_setting.value` (an arbitrary caller-supplied string keyed
  by an arbitrary caller-supplied key, per this component's own design
  rationale "callers own the meaning of their own keys") — this file does
  not know or constrain what a caller stores there.
- **Storage**: Every one of those values is written, unencrypted, to a
  single SQLite file on local disk, with `journal_mode=WAL` meaning
  committed data can additionally live in a `-wal` file alongside the main
  database file until checkpointing or SQLite's own auto-checkpoint
  truncates it. Nothing in this file encrypts the file, redacts a remote
  URL that happens to embed user-info credentials, or restricts the
  file's permissions beyond whatever the underlying directory-creation and
  connection-open calls default to.
- **Transmission**: None — this component makes no network call; every
  method operates on the local file through the SQLite C API.
- **Retention**: Indefinite. A `git_repo` row, its settings, and its
  cascaded layout, tab, and pane rows persist until it is deleted
  (cascading via the foreign keys described in **delete-cascades**) or the
  file itself is removed by something outside this file; nothing in this
  file expires or prunes data on its own.

## Logging

Not applicable: this component contains no logging call of any kind —
every diagnostic detail (a SQLite error message) is returned to the
caller through a thrown error, not written to a log by this file.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift`,
  importing only `Foundation`, `SQLite3` (the C SQLite library linked
  directly, not `Core Data` or `SwiftData`), `AgenticToolkitCore`, and
  `AgenticToolkitDatabase` (for `AppStorageLocation`); it depends on no UI
  framework, and a caller anywhere in a SwiftUI app — an `@Observable` view
  model, an `App`'s startup code — constructs and owns one instance
  directly. `ProjectDatabase` is declared as a plain `final class` with no
  `Sendable` conformance, no `actor` keyword, and no `@MainActor`
  annotation — the mechanism behind
  **caller-must-synchronize-cross-thread-access** — so the compiler keeps
  it in the isolation domain of whichever context created it and does not
  itself enforce any cross-thread safety. Its one connection is stored as
  `database: OpaquePointer?`, opened in `init(path:)` and closed in
  `deinit` only when non-`nil` — the mechanism behind
  **connection-closed-on-teardown**. `columnExists`, `schemaVersion`,
  `queryRepos`, `execute`, `executeBound`, `forEachRow`, `stepRow`,
  `bindText`, `bindOptionalText`, `bindOptionalDate`, `columnText`,
  `columnDate`, `queryScalarString`, and the `database` property itself
  are all declared without the `public` modifier, restricting them to
  callers in the same module; `queryScalarString` is called by no method
  in this file, existing solely for `ProjectDatabase+Layout.swift`, a
  sibling extension in the same module, to call.
- **Compose**: Port the SQLite access with `androidx.sqlite` or a light
  wrapper over `android.database.sqlite.SQLiteOpenHelper`/`SQLiteDatabase`,
  keeping the same one-connection-per-store shape; run the four migrations
  inside `SQLiteDatabase.beginTransactionNonExclusive()`/`endTransaction()`,
  re-issue the `foreign_keys=ON` pragma per connection the same way opening
  the connection does here, and represent `GitRepo` as the Kotlin `data
  class` the sibling `GitRepo` recipe already specifies.
- **React/Web**: A browser has no filesystem or SQLite; if this pattern is
  ported into a Node-hosted process (e.g. an Electron main process or a
  local dev server), use `better-sqlite3` or `node:sqlite`, apply the same
  `PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=ON`, and a busy-timeout
  equivalent (`better-sqlite3`'s `pragma('busy_timeout = 5000')`), and run
  the migration chain inside one transaction — checking `PRAGMA table_info`
  for column existence the same way this file's column-existence check
  does before any `ALTER TABLE`.
- **AppKit / UIKit**: Identical to the SwiftUI note — nothing in this file
  is tied to a UI framework; it ports unchanged to either, or to a headless
  command-line tool, since this component's own design rationale for the
  default path explicitly notes "this is the same registry the command
  line tools read".
- **WinUI 3**: Port with `Microsoft.Data.Sqlite` (or the raw `sqlite3`
  P/Invoke layer for closer fidelity) rather than `Windows.Storage`'s
  roaming or local settings APIs, since this component's contract is
  relational rows with foreign-key cascades, not key-value settings
  storage. Open the connection, then issue `PRAGMA journal_mode=WAL;` and
  `PRAGMA foreign_keys=ON;` immediately after, exactly as opening the
  connection does here, and issue `PRAGMA busy_timeout=5000;` to match the
  5-second wait (`Microsoft.Data.Sqlite` has no dedicated
  `SQLITE_OPEN_FULLMUTEX` flag, but serializes access per connection by
  default, preserving the same one-connection, thread-safe-by-default
  shape). Run the four migrations inside a transaction opened with `BEGIN
  IMMEDIATE;`/`COMMIT;`/`ROLLBACK;` issued as raw command text the way this
  file's own execute operation does, guarding each `ALTER TABLE` with a
  `PRAGMA table_info('table')` read the way this file's column-existence
  check does. Model `GitRepo` as the C# `record` the sibling `GitRepo`
  recipe specifies, and keep this component's own operations
  synchronous — this file performs every SQL call synchronously on the
  caller's thread — letting a `Task.Run` at the call site, not inside this
  component, move a call off a UI dispatcher thread.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift` |

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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
