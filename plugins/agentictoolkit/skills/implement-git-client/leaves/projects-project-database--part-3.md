<!-- leaf: implement-git-client/projects-project-database--part-3 · source: git-client-projects-project-database.md -->

# ProjectDatabase — continued (part 3)

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
