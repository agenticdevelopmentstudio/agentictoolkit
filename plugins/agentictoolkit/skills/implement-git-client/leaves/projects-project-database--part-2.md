<!-- leaf: implement-git-client/projects-project-database--part-2 · source: git-client-projects-project-database.md -->

# ProjectDatabase — continued (part 2)

**Rules** (cite as `implement-git-client/projects-project-database--part-2#<slug>`):

- `repo-column-set` MUST
- `all-repos-ordering` MUST
- `all-repos-includes-every-known-row` MUST
- `repo-lookup-by-id-and-path` MUST
- `repo-insert-column-set` MUST
- `repo-update-column-set` MUST
- `mark-opened-updates-only-last-opened` MUST
- `delete-cascades` MUST
- `settings-scoped-per-repo` MUST
- `setting-single-key-lookup` MUST
- `set-setting-nil-deletes` MUST
- `set-setting-upsert` MUST
- `text-binds-copy-the-string` MUST
- `step-loop-fails-on-anything-but-row-or-done` MUST
- `step-row-fails-on-anything-but-row-or-done` MUST
- `last-error-message-fallback` MUST
- `module-internal-helpers-not-public` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` (`init`) | `String` | none — required | Absolute filesystem path to the SQLite file; not validated as absolute, non-empty, or writable before use (see Edge Cases: Null and empty input). |
| `home` (`defaultPath(inHome:token:)`) | `URL` | `FileManager.default.homeDirectoryForCurrentUser` | The directory `defaultPath` hangs the storage dotfolder off of. |
| `token` (`defaultPath(inHome:token:)`) | `String` | `AppStorageLocation.token` (the running app's `CFBundleName`, alphanumeric-filtered) | Names the shared dotfolder this file's database lives in alongside other stores. |
| `at` (`markOpened(id:at:)`) | `Date` | `Date()` at the call site | The timestamp recorded as `last_opened`. |
| `value` (`setSetting(repoID:key:value:)`) | `String?` | none — required | `nil` deletes the setting row; any `String`, including the empty string, upserts it. |

The busy timeout (5,000 milliseconds) and `currentSchemaVersion` (`4`) are fixed constants in this file, not exposed as configuration a caller can override.

## Privacy

- **Data collected**: `git_repo.path` (an absolute filesystem path, which under a typical macOS home directory embeds the user's account name), `git_repo.remote` (a git remote URL, stored verbatim exactly as `GitRepo.remote` was already read out of `.git/config` by another component), and `project_setting.value` (an arbitrary caller-supplied string keyed by an arbitrary caller-supplied `key`, per the doc comment "callers own the meaning of their own keys,") — this file does not know or constrain what a caller stores there.
- **Storage**: Every one of those values is written, unencrypted, to a single SQLite file on local disk at `databasePath`, with `journal_mode=WAL` meaning committed data can additionally live in a `-wal` file alongside the main database file until `checkpoint()` or SQLite's own auto-checkpoint truncates it. Nothing in this file encrypts the file, redacts a `remote` URL that happens to embed user-info credentials, or restricts the file's POSIX permissions beyond whatever `FileManager.default.createDirectory` and `sqlite3_open_v2` default to.
- **Transmission**: None — `ProjectDatabase.swift` makes no network call; every method operates on the local file through the SQLite C API.
- **Retention**: Indefinite. A `git_repo` row, its settings, and its cascaded layout, tab, and pane rows persist until `delete(id:)` is called for that row (cascading via the foreign keys described in `delete-cascades`) or the file itself is removed by something outside this file; nothing in this file expires or prunes data on its own.

