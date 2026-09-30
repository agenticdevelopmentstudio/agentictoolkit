<!-- leaf: implement-status-server/libsql--part-3 · source: status-server-libsql.md -->

# Status Server Libsql — continued (part 3)

## Platform Notes

- **React/Web** (source platform): the two files live under
  `packages/web/packages/status-server/src/libsql/`, on top of
  `drizzle-orm/sqlite-core` and `drizzle-orm/libsql` (including its
  `migrator` submodule), Node's built-in `node:module`
  (`createRequire`) and `node:path`/`node:crypto`, and the
  `@agentic-toolkit/deploy-platform/schema` and `../monitor/deploy-status`
  siblings the schema re-exports from and builds its partial index against.
  The Hono routes and the monitor worker that call `openLibsql`,
  `tuneDbForConcurrency`, and `migrateDb` live outside this recipe's two
  files.
- **SwiftUI / AppKit / UIKit**: an Apple client of this backend is a
  consumer of the HTTP API this schema and its migrations power, not a
  re-implementer of it — it never opens this database directly. If a
  future product needed a companion Swift backend with an equivalent
  embedded store (a Vapor or Hummingbird service, for example), model each
  table as a `Codable` `struct` mirroring its columns 1:1, open the file
  with `GRDB.swift` or `SQLite.swift` rather than Core Data/SwiftData (this
  schema is relational rows with explicit indexes and partial-index
  predicates, not an object graph), issue the same `PRAGMA journal_mode=WAL`,
  `PRAGMA busy_timeout=5000`, and `PRAGMA synchronous=NORMAL` immediately
  after opening, and run migrations inside one transaction, checking for
  each table's existence the way `migrateDb` checks `__drizzle_migrations`.
- **Compose**: same client relationship as SwiftUI/AppKit/UIKit — an
  Android client calls the backend's HTTP API directly; it has no local
  copy of this schema to port. A hypothetical Kotlin backend port would use
  `androidx.sqlite` (or `SQLiteOpenHelper`/`SQLiteDatabase` directly),
  re-issuing the same three pragmas per connection and modeling each table
  as a Kotlin `data class`.
- **WinUI 3**: a WinUI 3 desktop app is likewise an HTTP client of this
  backend, never a direct reader of its database file. If a future product
  needed to reimplement this schema and its concurrency tuning on a .NET
  backend (ASP.NET Core Minimal API over SQLite), port it with
  `Microsoft.Data.Sqlite` rather than `Windows.Storage`'s settings APIs —
  this is relational rows with foreign keys and partial indexes, not
  key-value storage. Open the connection, then issue
  `PRAGMA journal_mode=WAL;`, `PRAGMA busy_timeout=5000;`, and
  `PRAGMA synchronous=NORMAL;` as raw command text exactly as
  `tuneDbForConcurrency` does; run `PRAGMA wal_checkpoint(TRUNCATE);` on the
  same maintenance cadence `checkpointWal` documents. Model `users`,
  `sessions`, and `apiTokens` as EF Core entities (or raw `Microsoft.Data.Sqlite`
  commands, for closer fidelity to this file's own driver-level style) with
  the sha256-hash-only-at-rest columns preserved verbatim, and run each
  migration inside a transaction opened with `BEGIN IMMEDIATE;` the way
  `migrate()`'s own transaction wrapping does, tracking applied migrations
  in a table equivalent to `__drizzle_migrations`.

## Design Decisions

- **Decision**: tune WAL, a 5-second `busy_timeout`, and `synchronous = NORMAL`
  for every embedded-file connection, never for a remote libsql/Turso one.
  **Rationale**: the source comment states this directly — WAL lets the
  monitor worker write while the API server reads (and vice versa) instead
  of the default rollback journal's whole-file locking; `busy_timeout`
  makes a second writer wait instead of failing `SQLITE_BUSY` on
  contention; `NORMAL` pairs with WAL to fsync on checkpoint rather than
  per-commit, trading a small durability window against app crashes for
  avoiding per-insert fsyncs under the monitor's write volume. A remote
  connection manages its own journaling, so applying any of this to it
  would be a no-op at best and a wrong assumption at worst.
  **Approved**: pending
- **Decision**: make `checkpointWal` fail-soft (`busy: true`, no throw)
  rather than retry or force a checkpoint through a live reader.
  **Rationale**: the source's own multi-paragraph comment documents the
  production incident this addresses — a checkpointed-but-never-shrunk WAL
  sidecar can sit at a high-water mark set by the largest transaction ever
  run (a multi-million-row retention sweep, in this case), and only
  `TRUNCATE` mode reclaims that disk space; but a `busy` result means a
  live reader (the API server's own connection) still holds the old WAL,
  so forcing the issue would risk breaking that reader rather than simply
  waiting for the next maintenance pass to try again.
  **Approved**: pending
- **Decision**: keep `deployments.status` as a nullable, otherwise-unused
  column instead of dropping it in this migration.
  **Rationale**: the column comment states the reason directly — dropping
  it immediately would break still-live old code mid-rollout, during the
  window where migrations auto-apply ahead of every instance being updated
  to read `buildPhase`/`deployPhase` instead; the comment marks it for
  removal "in a later migration" once that cutover is complete.
  **Approved**: pending
- **Decision**: declare `onDelete: 'cascade'` foreign keys on
  `monitoredSites`/`monitoredEndpoints` even though libSQL over HTTP does
  not enforce them.
  **Rationale**: the schema comment states this is deliberate
  documentation of intent for a future connection mode that would enforce
  it, while today's application code (`db/config.ts`, external to these
  two files) performs the cascading delete itself; declaring the
  relationship in the schema keeps the intent visible and the relational
  query builder aware of the join, even though SQLite-over-HTTP will not
  act on it.
  **Approved**: pending
- **Decision**: default `platformHealthState.configured`/`reachable` and
  `deployments`/`monitoredEndpoints` boolean flags to `true` rather than
  leaving them nullable or defaulting to `false`.
  **Rationale**: each default-`true` column's comment frames it as a
  deliberate, low-risk guess about rows that predate the column, not a
  claimed fact — an unconfigured platform being guessed "reachable" only
  delays a poll from correcting it, and the `reachable` migration
  specifically backfills `false` where `consecutiveFailures > 0` to avoid
  suppressing a live incident. This is recorded here as the tradeoff it
  is, not defended as free of cost.
  **Approved**: pending
