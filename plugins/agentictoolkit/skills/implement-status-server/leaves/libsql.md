<!-- leaf: implement-status-server/libsql · source: status-server-libsql.md -->

**Rules** (cite as `implement-status-server/libsql#<slug>`):

- `schema-type-alias` MUST
- `db-type-alias` MUST
- `connection-url-required` MUST
- `connection-construction` MUST
- `connection-per-caller` MUST
- `embedded-file-detection` MUST
- `tune-noop-for-remote` MUST
- `tune-wal-mode` MUST
- `tune-busy-timeout` MUST
- `tune-synchronous-normal` MUST
- `tune-idempotent-reapply` MUST
- `checkpoint-noop-for-remote` MUST
- `checkpoint-truncate` MUST
- `checkpoint-result-shape` MUST
- `checkpoint-fail-soft` MUST
- `package-root-resolution` MUST
- `migrations-folder-constant` MUST
- `migrate-default-folder` MUST
- `migrate-applies-pending` MUST
- `migrate-idempotent` MUST
- `migrations-immutable` MUST
- `health-check-row-shape` MUST
- `health-check-indexing` MUST
- `metrics-hourly-uniqueness` MUST
- `deployment-row-identity` MUST
- `deployment-project-identity-fallback` MUST
- `deployment-legacy-status-column` MUST
- `deployment-phase-defaults` MUST
- `deployment-created-indexing` MUST
- `deployment-inflight-index` MUST
- `issue-uniqueness-open` MUST
- `issue-resolution-reason` MUST
- `issue-history-indexing` MUST

# Status Server Libsql

## Overview

This is the status backend's libSQL/SQLite storage layer: two files under
`src/libsql/` that are the ONLY place in the package that know the driver,
the schema, and the migrations. `client.ts` exports the `Db`/`Schema` type
aliases and five functions: `openLibsql` (construct a connection from a
`{ url, authToken? }` pair), `isEmbeddedFile` (distinguish a local `file:`
database from a remote libsql/Turso one), `tuneDbForConcurrency` (WAL,
`busy_timeout`, `synchronous` pragmas for an embedded file shared by two
Node.js connections), `checkpointWal` (reclaim the WAL sidecar's disk
footprint), and `migrateDb` (apply pending Drizzle migrations, idempotently).
`schema.ts` declares every table this backend persists to, via
`drizzle-orm/sqlite-core`'s `sqliteTable`: health-check history, hourly
metric rollups, polled deployments, derived issues, editable monitoring
config (site groups → monitored sites → monitored endpoints), per-platform
poll-health and Vercel-production-staleness state, peer fleet-view
snapshots, polled error and analytics summaries, and a self-contained
user/session/API-token/device-authorization auth store — plus a re-export
of three deploy-platform tables from a shared package. Every table is a
plain relational row shape with no business logic of its own; the
functions and column defaults in these two files are the entire contract.

## Behavioral Requirements

### Connection (client.ts)

- **schema-type-alias**: the exported `Schema` type MUST equal
  `typeof schema` — the full module namespace `schema.ts` exports.
- **db-type-alias**: the exported `Db` type MUST equal
  `LibSQLDatabase<Schema>`.
- **connection-url-required**: `openLibsql` MUST throw an `Error` with
  message `"libsql connection url is empty (e.g. file:./status.db)"` when
  `conn.url` is falsy (the empty string).
- **connection-construction**: `openLibsql` MUST construct and return a
  `Db` via `drizzle({ connection: { url: conn.url, authToken: conn.authToken }, schema })`
  for a non-empty `conn.url`, passing `authToken` through unchanged
  (including `undefined`).
- **connection-per-caller**: `openLibsql` MUST create a fresh connection on
  every call; the source's own comment on `tuneDbForConcurrency` documents
  that the API server and the monitor worker each hold their own connection
  to the same file, and neither `client.ts` nor `schema.ts` provides any
  cross-connection locking beyond the pragmas `tuneDbForConcurrency` applies.
- **embedded-file-detection**: `isEmbeddedFile` MUST return `true` if and
  only if `conn.url` starts with the literal prefix `"file:"`, and MUST
  return `false` for every other value, including an `https://` or
  `libsql://` URL.

### Concurrency tuning (client.ts)

- **tune-noop-for-remote**: `tuneDbForConcurrency` MUST resolve without
  executing any PRAGMA when `isEmbeddedFile(conn)` is `false`.
- **tune-wal-mode**: for an embedded-file connection, `tuneDbForConcurrency`
  MUST execute `PRAGMA journal_mode = WAL`.
- **tune-busy-timeout**: for an embedded-file connection,
  `tuneDbForConcurrency` MUST execute `PRAGMA busy_timeout = 5000`
  (5000 milliseconds).
- **tune-synchronous-normal**: for an embedded-file connection,
  `tuneDbForConcurrency` MUST execute `PRAGMA synchronous = NORMAL`, after
  the WAL and `busy_timeout` pragmas, in that order.
- **tune-idempotent-reapply**: re-invoking `tuneDbForConcurrency` against an
  already-tuned embedded-file connection MUST be safe to call again — the
  source comment states WAL is a persistent property of the DB file, so
  re-applying it is a no-op.

### Checkpoint (client.ts)

- **checkpoint-noop-for-remote**: `checkpointWal` MUST resolve `null`
  without executing any PRAGMA when `isEmbeddedFile(conn)` is `false`.
- **checkpoint-truncate**: for an embedded-file connection, `checkpointWal`
  MUST execute `PRAGMA wal_checkpoint(TRUNCATE)` — the only checkpoint mode
  that returns the WAL sidecar's disk footprint to the volume, per the
  source's comment (a `PASSIVE`-mode `wal_autocheckpoint` resets the WAL
  without truncating it).
- **checkpoint-result-shape**: `checkpointWal` MUST resolve
  `{ busy, frames }`, where `busy` is `true` exactly when the checkpoint
  query's first result row's `busy` field equals `1`, and `frames` is the
  numeric value of that row's `checkpointed` field, defaulting to `0` when
  the row or field is absent.
- **checkpoint-fail-soft**: `checkpointWal` MUST NOT throw when the
  checkpoint reports busy; a busy checkpoint MUST resolve
  `{ busy: true, frames }`, per the source's documented "fail-soft by
  design" comment — the DB is left untouched and the next maintenance pass
  tries again.

### Package root and migrations (client.ts)

- **package-root-resolution**: `packageRoot` MUST resolve this package's
  own root directory via
  `createRequire(import.meta.url).resolve('@agentic-toolkit/status-server/package.json')`,
  so it is correct whether the caller runs from `src/`, from a built
  `dist/` chunk, or from a host's vendored `node_modules` copy.
- **migrations-folder-constant**: the exported `MIGRATIONS_FOLDER` MUST
  equal `join(packageRoot(), "src", "libsql", "migrations")`.
- **migrate-default-folder**: `migrateDb` MUST use `MIGRATIONS_FOLDER` as
  the migrations folder when the caller passes no `migrationsFolder`
  argument.
- **migrate-applies-pending**: `migrateDb` MUST apply, via
  `drizzle-orm/libsql/migrator`'s `migrate`, every migration under the
  migrations folder not yet recorded in `__drizzle_migrations`, in journal
  order.
- **migrate-idempotent**: `migrateDb` MUST be safe to call repeatedly
  against the same database — a second or third call after all migrations
  are applied MUST resolve without error and MUST leave the schema
  unchanged and queryable. Traced to `migrate-idempotent.int.test.ts` ›
  "re-running against an already-migrated DB is a no-op" and "a third run
  still leaves the schema queryable".
- **migrations-immutable**: every shipped migration file under
  `MIGRATIONS_FOLDER` MUST remain byte-for-byte unchanged once recorded in
  the journal — the source's own comment states migrations "are applied in
  production already and are immutable: never edit one, only add." A new
  migration MUST be added as a new file. Traced to
  `migrations-immutable.test.ts` › "matches its pinned hash" (per migration)
  and "every pinned hash still names a migration the journal knows about".

### Schema — health checks and metric rollups

- **health-check-row-shape**: `healthChecks` MUST persist one row per probe
  with `serviceSlug`, `status` (`'healthy' | 'degraded' | 'down'`), nullable
  `responseTimeMs`/`statusCode`/`error`, a `dnsOk` boolean defaulting
  `true`, and a `checkedAt` timestamp defaulting to `unixepoch()`.
- **health-check-indexing**: `healthChecks` MUST be indexed on
  `(serviceSlug, checkedAt)` for per-service lookups, and independently on
  `checkedAt` alone — the source comment explains the age-only retention
  prune (`where checked_at < cutoff`) cannot be served by the composite
  index, whose leading column is `serviceSlug`.
- **metrics-hourly-uniqueness**: `metricsHourly` MUST enforce at most one
  row per `(serviceSlug, hour)` pair via `uniq_metrics_service_hour`, and
  MUST be independently indexed on `hour` alone for the same age-only
  retention-prune reason as `healthChecks`.

### Schema — deployments and issues

- **deployment-row-identity**: `deployments.id` MUST be the primary key and
  MUST hold the platform-prefixed id format (`vc_<uid>` for Vercel,
  `cf_<id>` for Cloudflare Pages, `ry_<id>` for Railway), per the column's
  own comment.
- **deployment-project-identity-fallback**: `deployments.providerProjectId`
  MUST be nullable; when `null`, identity for that row falls back to
  `projectName`, per the column's comment.
- **deployment-legacy-status-column**: `deployments.status` MUST remain a
  nullable column, retained only so a rolling deploy does not break
  still-live old code while migrations auto-apply; current code MUST
  derive status from `buildPhase`/`deployPhase`, never from `status` — the
  column's own comment marks it "vestigial" and slated for removal once
  every environment is cut over.
- **deployment-phase-defaults**: `deployments.deployPhase` MUST default to
  `'none'`; `deployments.buildPhase` MUST be nullable with no default.
- **deployment-created-indexing**: `deployments` MUST be indexed on
  `createdAt` (`idx_deploy_created`).
- **deployment-inflight-index**: `deployments` MUST carry a partial index
  (`idx_deploy_inflight`) on `fetchedAt`, scoped to rows matching
  `inFlightSql('')` from `../monitor/deploy-status`, so both the reconcile
  candidate query and the expiry sweep seek a small index every tick
  instead of scanning the full retained deploy history — the source
  comment ties this directly to a production incident where the equivalent
  unindexed scan on `health_checks` took the container down.
- **issue-uniqueness-open**: `issues` MUST enforce at most one open row per
  `target` via `uniq_open_issue_per_target`, a unique index scoped to
  `resolved_at is null`, so the database itself rejects a second
  concurrently-open issue for the same target.
- **issue-resolution-reason**: `issues.resolvedReason` MUST be nullable
  and, when set, MUST hold either `'recovered'` or `'unmonitored'`; per the
  column's comment, only a `'recovered'` close is eligible to become an
  activity-feed entry.
- **issue-history-indexing**: `issues` MUST be indexed independently on
  `resolvedAt` (`idx_issue_resolved`), on `source` (`idx_issue_source`), and
  on `openedAt` (`idx_issue_opened`) — the last serving a 90-day paged
  activity-history read ordered by `openedAt`, for the same
  scan-grows-with-history reason as `idx_deploy_inflight`.

