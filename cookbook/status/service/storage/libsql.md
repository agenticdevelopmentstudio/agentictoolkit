---
id: 6bf27f64-59d0-4b2a-8715-92dba2856814
title: SQL Storage Layer
domain: agentictoolkit://cookbook/status/service/storage/libsql
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The status backend's SQLite/libSQL storage layer — connection open/tune/checkpoint
  operations and the persisted schema for health checks, deployments, issues, monitoring
  configuration, platform/peer state, errors, analytics, and authentication tables.
platforms:
- typescript
- web
tags:
- database
- sqlite
- persistence
- migrations
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/data/database
- agenticdevelopercookbook://guidelines/implementing/data/transactions-and-concurrency
- agenticdevelopercookbook://guidelines/implementing/data/foreign-keys
- agenticdevelopercookbook://guidelines/implementing/data/schema-evolution
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
related:
- agentictoolkit://cookbook/status/service/auth
references:
- packages/web/packages/status-server/src/libsql/client.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/schema.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/schema/index.ts (agentictoolkit)
- packages/web/packages/status-server/test/migrate-idempotent.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/migrations-immutable.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# SQL Storage Layer

## Overview

This is the status backend's SQLite/libSQL storage layer: the ONLY part of
the package that knows the driver, the schema, and the migrations. It
exposes five operations — opening a connection (from a URL and an optional
auth token), determining whether a connection points at a local embedded
file rather than a remote database, tuning an embedded-file connection for
concurrent access (journal mode, busy-timeout, and synchronous-write pragmas
for a file shared by two independent connections), checkpointing the
write-ahead log (reclaiming its on-disk footprint), and applying pending
migrations idempotently. The schema declares every table this backend
persists to: health-check history, hourly metric rollups, polled
deployments, derived issues, editable monitoring configuration (site groups
→ monitored sites → monitored endpoints), per-platform poll-health and
production-staleness state, peer fleet-view snapshots, polled error and
analytics summaries, and a self-contained user/session/API-token/
device-authorization authentication store — plus a re-export of three
tables from a shared deploy-platform package. Every table is a plain
relational row shape with no business logic of its own; the operations and
column defaults described here are the entire contract.

## Behavioral Requirements

### Connection

- **schema-type-alias**: the exported schema type MUST equal the full schema
  module's own namespace type.
- **db-type-alias**: the exported connection type MUST equal the underlying
  database-connection type, parameterized by the schema type.
- **connection-url-required**: the connection-opening operation MUST throw
  an error with message `"libsql connection url is empty (e.g. file:./status.db)"`
  when the connection URL is empty (falsy).
- **connection-construction**: the connection-opening operation MUST
  construct and return a connection object using the given URL and auth
  token for a non-empty URL, passing the auth token through unchanged
  (including when absent).
- **connection-per-caller**: the connection-opening operation MUST create a
  fresh connection on every call; the API server and the monitor worker each
  hold their own connection to the same file, and neither the connection
  layer nor the schema provides any cross-connection locking beyond the
  pragmas the concurrency-tuning operation applies.
- **embedded-file-detection**: the embedded-file check MUST return `true`
  if and only if the connection URL starts with the literal prefix
  `"file:"`, and MUST return `false` for every other value, including an
  `https://` or a remote-database URL.

### Concurrency Tuning

- **tune-noop-for-remote**: the concurrency-tuning operation MUST resolve
  without executing any PRAGMA when the connection is not an embedded file.
- **tune-wal-mode**: for an embedded-file connection, the concurrency-tuning
  operation MUST execute `PRAGMA journal_mode = WAL`.
- **tune-busy-timeout**: for an embedded-file connection, the
  concurrency-tuning operation MUST execute `PRAGMA busy_timeout = 5000`
  (5000 milliseconds).
- **tune-synchronous-normal**: for an embedded-file connection, the
  concurrency-tuning operation MUST execute `PRAGMA synchronous = NORMAL`,
  after the write-ahead-log and busy-timeout pragmas, in that order.
- **tune-idempotent-reapply**: re-invoking the concurrency-tuning operation
  against an already-tuned embedded-file connection MUST be safe to call
  again — write-ahead-log mode is a persistent property of the database
  file, so re-applying it is a no-op.

### Checkpoint

- **checkpoint-noop-for-remote**: the checkpoint operation MUST resolve
  `null` without executing any PRAGMA when the connection is not an
  embedded file.
- **checkpoint-truncate**: for an embedded-file connection, the checkpoint
  operation MUST execute `PRAGMA wal_checkpoint(TRUNCATE)` — the only
  checkpoint mode that returns the write-ahead log's disk footprint to the
  volume (a passive-mode auto-checkpoint resets the log without truncating
  it).
- **checkpoint-result-shape**: the checkpoint operation MUST resolve a
  result shaped as `{ busy, frames }`, where `busy` is `true` exactly when
  the checkpoint query's first result row's `busy` field equals `1`, and
  `frames` is the numeric value of that row's `checkpointed` field,
  defaulting to `0` when the row or field is absent.
- **checkpoint-fail-soft**: the checkpoint operation MUST NOT throw when
  the checkpoint reports busy; a busy checkpoint MUST resolve
  `{ busy: true, frames }` — this is fail-soft by design: the database is
  left untouched and the next maintenance pass tries again.

### Package Root and Migrations

- **package-root-resolution**: the package-root resolution MUST locate this
  package's own installed root directory via the host runtime's own
  module-resolution mechanism, so it is correct whether the caller runs
  from source, from a built distribution, or from a host's vendored copy.
- **migrations-folder-constant**: the exported migrations-folder constant
  MUST equal the package root's `src/libsql/migrations` subdirectory.
- **migrate-default-folder**: the migration operation MUST use the
  migrations-folder constant as the migrations folder when the caller
  passes no explicit migrations-folder argument.
- **migrate-applies-pending**: the migration operation MUST apply, via the
  schema's own migration mechanism, every migration under the migrations
  folder not yet recorded in the migration-history table, in journal order.
- **migrate-idempotent**: the migration operation MUST be safe to call
  repeatedly against the same database — a second or third call after all
  migrations are applied MUST resolve without error and MUST leave the
  schema unchanged and queryable.
- **migrations-immutable**: every shipped migration file under the
  migrations folder MUST remain byte-for-byte unchanged once recorded in
  the migration journal — migrations are applied in production already and
  are immutable: never edit one, only add. A new migration MUST be added as
  a new file.

### Schema — health checks and metric rollups

- **health-check-row-shape**: `healthChecks` MUST persist one row per probe
  with `serviceSlug`, `status` (`'healthy' | 'degraded' | 'down'`), nullable
  `responseTimeMs`/`statusCode`/`error`, a `dnsOk` boolean defaulting
  `true`, and a `checkedAt` timestamp defaulting to the database's own
  current-time function.
- **health-check-indexing**: `healthChecks` MUST be indexed on
  `(serviceSlug, checkedAt)` for per-service lookups, and independently on
  `checkedAt` alone — the age-only retention prune (`where checked_at <
  cutoff`) cannot be served by the composite index, whose leading column is
  `serviceSlug`.
- **metrics-hourly-uniqueness**: `metricsHourly` MUST enforce at most one
  row per `(serviceSlug, hour)` pair via `uniq_metrics_service_hour`, and
  MUST be independently indexed on `hour` alone for the same age-only
  retention-prune reason as `healthChecks`.

### Schema — deployments and issues

- **deployment-row-identity**: `deployments.id` MUST be the primary key and
  MUST hold the platform-prefixed id format (`vc_<uid>` for Vercel,
  `cf_<id>` for Cloudflare Pages, `ry_<id>` for Railway).
- **deployment-project-identity-fallback**: `deployments.providerProjectId`
  MUST be nullable; when `null`, identity for that row falls back to
  `projectName`.
- **deployment-legacy-status-column**: `deployments.status` MUST remain a
  nullable column, retained only so a rolling deploy does not break
  still-live old code while migrations auto-apply; current code MUST
  derive status from `buildPhase`/`deployPhase`, never from `status` — the
  column is vestigial and slated for removal once every environment is cut
  over.
- **deployment-phase-defaults**: `deployments.deployPhase` MUST default to
  `'none'`; `deployments.buildPhase` MUST be nullable with no default.
- **deployment-created-indexing**: `deployments` MUST be indexed on
  `createdAt` (`idx_deploy_created`).
- **deployment-inflight-index**: `deployments` MUST carry a partial index
  (`idx_deploy_inflight`) on `fetchedAt`, scoped to rows matching a shared
  in-flight-detection predicate used elsewhere in this backend, so both the
  reconcile candidate query and the expiry sweep seek a small index every
  tick instead of scanning the full retained deploy history — this is
  tied directly to a production incident where the equivalent unindexed
  scan on `health_checks` took the container down.
- **issue-uniqueness-open**: `issues` MUST enforce at most one open row per
  `target` via `uniq_open_issue_per_target`, a unique index scoped to
  `resolved_at is null`, so the database itself rejects a second
  concurrently-open issue for the same target.
- **issue-resolution-reason**: `issues.resolvedReason` MUST be nullable
  and, when set, MUST hold either `'recovered'` or `'unmonitored'`; only a
  `'recovered'` close is eligible to become an activity-feed entry.
- **issue-history-indexing**: `issues` MUST be indexed independently on
  `resolvedAt` (`idx_issue_resolved`), on `source` (`idx_issue_source`), and
  on `openedAt` (`idx_issue_opened`) — the last serving a 90-day paged
  activity-history read ordered by `openedAt`, for the same
  scan-grows-with-history reason as `idx_deploy_inflight`.

### Schema — monitoring configuration

- **site-group-uniqueness**: `siteGroups.slug` MUST be unique
  (`uniq_site_group_slug`); `retentionDays` MUST default to `14`.
- **monitored-site-uniqueness**: `monitoredSites` MUST enforce uniqueness
  of `(siteGroupId, slug)` via `uniq_site_group_site_slug`, and MUST
  declare a foreign key to `siteGroups.id` with cascading delete.
- **monitored-endpoint-fk**: `monitoredEndpoints.siteId` MUST declare a
  foreign key to `monitoredSites.id` with cascading delete, and MUST be
  indexed (`idx_endpoint_site`) for per-site lookup.
- **fk-cascade-not-enforced-over-http**: the cascading-delete declarations
  on `monitoredSites` and `monitoredEndpoints` MUST be understood as
  documentation of intent only — this storage layer's remote transport does
  not enforce foreign-key constraints over that transport, so deleting a
  group or a site (external to this recipe) cascades in application code,
  never by relying on the database to do it.
- **endpoint-check-defaults**: `monitoredEndpoints` MUST default `kind` to
  `'http'`, `expectedStatus` to `200`, `checkIntervalSeconds` to `60`,
  `dnsCheckA`/`dnsCheckAaaa`/`dnsCheckCname` to `true`, `isActive` to
  `true`, `monitorHttp` to `true`, `monitorDeploys` to `true`, and
  `ignoreProjectWarning` to `false`.
- **endpoint-per-signal-toggles**: `monitoredEndpoints.monitorHttp` and
  `monitoredEndpoints.monitorDeploys` MUST be independent of `isActive` and
  of each other — turning one signal off removes only that signal's
  problems from the board while the master switch and the other signal
  remain unaffected.
- **endpoint-deploy-project-id-write-once**: `monitoredEndpoints.deployProjectId`
  MUST be nullable, with `null` meaning not yet learned; once a value is
  learned it is never overwritten automatically, so an operator-entered
  value always wins. The schema itself declares no trigger or default
  enforcing this — it is a documented invariant of the column's meaning
  that the calling code (external to this recipe) is responsible for
  upholding, the same way fk-cascade-not-enforced-over-http is.
- **deploy-platform-tables-reexported**: `deployIntegrations`,
  `deployProjectMeta`, and `ignoredDeployProjects` MUST be re-exported from
  a shared deploy-platform package rather than declared locally, so every
  existing importer's schema-module path continues to resolve them.

### Schema — platform and peer state

- **platform-health-state-shape**: `platformHealthState` MUST key one row
  per `source` (platform identifier), tracking `consecutiveFailures`
  (default `0`), `configured` (default `true`), and `reachable` (default
  `true`); both boolean defaults are documented as deliberate, benign
  guesses about pre-existing rows, not facts.
- **vercel-prod-state-shape**: `vercelProdState` MUST key one row per
  `projectName`, with `stale` defaulting to `false`; the row is replaced
  wholesale on every complete read, never merged field-by-field.
- **peer-uniqueness**: `peers.baseUrl` MUST be unique
  (`uniq_peer_base_url`); `peers.token` MUST be nullable, with `null`
  meaning the peer's own reads are public (no bearer required).
- **peer-snapshot-fk**: `peerSnapshots.peerId` MUST be the primary key and
  MUST declare a foreign key to `peers.id` with cascading delete;
  `peerSnapshots.reachable` MUST default to `false`.

### Schema — errors and analytics

- **error-row-uniqueness**: `errors.issueKey` MUST be unique
  (`uniq_error_issue`) — one row per external issue id, upserted by callers
  external to this recipe; `errors` MUST be indexed on `lastSeen`
  (`idx_error_last_seen`); `count` and `userCount` MUST each default to
  `0`, and `resolved` MUST default to `false`.
- **analytics-metrics-indexing**: `analyticsMetrics` MUST be indexed on the
  composite `(metric, window, scope, capturedAt)`
  (`idx_analytics_metric_time`) for the dashboard's latest-value/trend
  reads, and independently on `capturedAt` alone
  (`idx_analytics_captured`) for the same age-only retention-prune reason
  as `healthChecks`; `scope` MUST default to `'all'`.

### Schema — authentication and tokens

- **user-uniqueness**: `users.email` and `users.githubId` MUST each be
  unique (`uniq_user_email`, `uniq_user_github`); `role` MUST default to
  `'pending'`; `passwordHash` and `githubId` MUST each be independently
  nullable, supporting OAuth-only and password-only accounts respectively.
- **session-token-hash-only**: `sessions` MUST persist only `tokenHash`
  (unique, `uniq_session_token`), never a raw session token — so a database
  leak cannot reconstruct live cookies; `sessions.userId` MUST declare a
  foreign key to `users.id` with cascading delete, and MUST be indexed
  (`idx_session_user`).
- **api-token-hash-only**: `apiTokens` MUST persist only `tokenHash`
  (unique, `uniq_api_token_hash`) plus a display-only `prefix` (the raw
  value's leading 12 characters), never the raw bearer value; `role` MUST
  be `'admin' | 'user'`; `kind` MUST default to `'minted'`; `createdBy`
  MUST declare a foreign key to `users.id` with cascading delete;
  revocation MUST be represented by setting `revokedAt`, never by deleting
  the row.
- **api-token-created-at-app-default**: `apiTokens.createdAt` and
  `deviceAuthorizations.createdAt` MUST be populated by application code at
  insert time (a computed default evaluated by the calling program) rather
  than by a database-level default — unlike every other timestamp column in
  this schema, which defaults via the database's own current-time function.
  A row inserted through raw SQL that bypasses the normal insert path would
  leave these two columns null-violating, since both are required with no
  database-level default.
- **device-auth-hash-only-except-raw**: `deviceAuthorizations` MUST persist
  only `deviceCodeHash` and `userCodeHash` (each unique, `uniq_device_code`
  and `uniq_user_code`), never the plaintext device or user code;
  `tokenRaw` MUST be the one column in this schema documented to briefly
  hold a plaintext secret, and only between approval and the single
  successful poll — the row is then deleted (single-use) by code external
  to this recipe, and `tokenRaw` is never selected in any list path.
- **device-auth-status**: `deviceAuthorizations.status` MUST default to
  `'pending'` and be one of `'pending' | 'approved' | 'denied'`; `tokenId`
  MUST declare a foreign key to `apiTokens.id` that nulls out on delete;
  `approvedBy` MUST declare a foreign key to `users.id` that nulls out on
  delete.
- **exported-row-types**: the schema MUST export public type aliases for a
  user row, a new-user insert shape, and a session row, each mechanically
  derived from the corresponding table's own column definitions, so the
  alias always matches the table exactly with no hand-maintained duplicate
  shape.

## Appearance

Not applicable — this is a server-side database module (connection
helpers and a persisted schema), not a visual component.

## States

Not applicable — this is a server-side database module, not a visual component; its runtime behavior is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side database module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-libsql-001 | schema-type-alias, db-type-alias | A static type-level check of the exported schema type and connection type | The schema type type-checks as the full schema module's own namespace type; the connection type type-checks as the underlying database-connection type parameterized by it — a compile-time contract, verified by the package's own type-checking build |
| status-server-libsql-002 | connection-url-required | The connection-opening operation called with an empty URL | Throws an error with message `'libsql connection url is empty (e.g. file:./status.db)'` |
| status-server-libsql-003 | connection-construction, embedded-file-detection | The connection-opening operation called with the URL `file:./status.db`, then the embedded-file check called with the same URL | Returns a connection object; the embedded-file check returns `true` |
| status-server-libsql-004 | embedded-file-detection | The embedded-file check called with `https://example.turso.io` and separately with `libsql://example` | Both return `false` |
| status-server-libsql-005 | connection-per-caller | Boot the API server and the monitor worker, each calling the connection-opening operation with the same embedded-file connection details | Two independent connection objects are created; neither call reuses the other's connection object |
| status-server-libsql-006 | tune-noop-for-remote, checkpoint-noop-for-remote | The concurrency-tuning operation and, separately, the checkpoint operation, each called against a remote-database connection (`libsql://x`) | Neither issues a PRAGMA; the checkpoint operation resolves `null` |
| status-server-libsql-007 | tune-wal-mode, tune-busy-timeout, tune-synchronous-normal | The concurrency-tuning operation called against an embedded-file connection (`file:./status.db`), observed against a spy-wrapped query execution | Exactly three PRAGMA statements run, in order: `journal_mode = WAL`, `busy_timeout = 5000`, `synchronous = NORMAL` |
| status-server-libsql-008 | tune-idempotent-reapply | The concurrency-tuning operation called twice against the same embedded connection | The second call re-issues the same three PRAGMAs without erroring; querying `PRAGMA journal_mode` still returns `'wal'` |
| status-server-libsql-009 | checkpoint-truncate, checkpoint-result-shape | The checkpoint operation called against an embedded connection (`file:./status.db`) with no pending readers | Resolves a result with `busy: false` and a `frames` count equal to the checkpointed frame count |
| status-server-libsql-010 | checkpoint-fail-soft | The checkpoint operation invoked while a second connection holds an open read transaction against the same write-ahead log | Resolves a result with `busy: true` and a `frames` count; does not throw |
| status-server-libsql-011 | package-root-resolution, migrations-folder-constant | The migrations-folder constant read from the package's source form, from a built distribution, and from a host's vendored copy | All three resolve to that build's own `src/libsql/migrations` directory, never another build's |
| status-server-libsql-012 | migrate-default-folder, migrate-applies-pending | The migration operation called against a fresh, empty in-memory database, with no explicit migrations-folder argument | The migration-history table contains one row per journal entry; `site_groups` and the other declared tables exist and are queryable |
| status-server-libsql-013 | migrate-idempotent | The migration operation called a second and third time against the same, already-migrated database | Both calls resolve with no error; the migration-history table's rows are unchanged after the second call — re-running against an already-migrated database is a no-op, and a third run still leaves the schema queryable |
| status-server-libsql-014 | migrations-immutable | Hash each migration file named in the migration journal, under the migrations folder | Every hash matches its pinned value |
| status-server-libsql-015 | health-check-row-shape, health-check-indexing | Insert a health-check row supplying only `serviceSlug` and `status` | `dnsOk` reads back `true`, `checkedAt` reads back within the current second; a query plan for a `service_slug`+`checked_at` filter and for a `checked_at`-only filter each use one of the two declared indexes |
| status-server-libsql-016 | metrics-hourly-uniqueness | Insert two hourly-metric rows with the same `(serviceSlug, hour)` pair | The second insert violates `uniq_metrics_service_hour` and rejects |
| status-server-libsql-017 | deployment-row-identity, deployment-phase-defaults | Insert a deployment row with `id: 'vc_abc'`, no `deployPhase` supplied | Insert succeeds; `deployPhase` reads back `'none'` |
| status-server-libsql-018 | deployment-project-identity-fallback, deployment-legacy-status-column | Insert a deployment row with `providerProjectId: null` and `status: null` | Both persist as `null`; a caller identifies the row by `projectName` alone, and no code path in the schema derives a value for `status` |
| status-server-libsql-019 | deployment-created-indexing, deployment-inflight-index | A query plan for a select ordered by `createdAt`, and separately for a select filtered by the in-flight predicate | The first uses `idx_deploy_created`; the second uses `idx_deploy_inflight`, not a full table scan |
| status-server-libsql-020 | issue-uniqueness-open | Insert two issue rows for the same `target` with `resolvedAt: null` | The second insert violates `uniq_open_issue_per_target` and rejects; a third insert for the same `target` after the first is resolved (`resolvedAt` set) succeeds |
| status-server-libsql-021 | issue-resolution-reason, issue-history-indexing | Resolve an issue row with `resolvedReason: 'unmonitored'`, then a separate row with `'recovered'` | Both persist verbatim; a query plan for a paged read ordered by `openedAt` uses `idx_issue_opened`, not a full scan |
| status-server-libsql-022 | site-group-uniqueness | Insert a site-group row supplying only `slug` and `name` | `retentionDays` reads back `14`; a second insert with the same `slug` violates `uniq_site_group_slug` |
| status-server-libsql-023 | monitored-site-uniqueness, monitored-endpoint-fk, fk-cascade-not-enforced-over-http | Delete a site-group row owning child monitored-site/monitored-endpoint rows, via a raw connection accessed over the remote transport | The child rows are NOT removed by the database; they remain until application code deletes them explicitly |
| status-server-libsql-024 | endpoint-check-defaults, endpoint-per-signal-toggles | Insert a monitored-endpoint row supplying only `siteId` and `url` | `dnsCheckA`/`dnsCheckAaaa`/`dnsCheckCname`/`isActive`/`monitorHttp`/`monitorDeploys` all read back `true`; `ignoreProjectWarning` reads back `false`; `expectedStatus` reads back `200` |
| status-server-libsql-025 | endpoint-deploy-project-id-write-once | Set a monitored-endpoint's `deployProjectId` once, then run an external write path that only writes when the column is currently `null` | The stored value is unchanged on the second run; the schema itself enforces nothing here — the write-once behavior is the calling code's discipline |
| status-server-libsql-026 | deploy-platform-tables-reexported | Import the re-exported deploy-integrations table from this schema | Resolves the same table object exported by the shared deploy-platform package, not a locally redeclared table |
| status-server-libsql-027 | platform-health-state-shape, vercel-prod-state-shape | Insert one platform-health-state row and one production-staleness-state row supplying only their primary keys | `consecutiveFailures` reads back `0`; `configured` and `reachable` read back `true`; `stale` reads back `false` |
| status-server-libsql-028 | peer-uniqueness, peer-snapshot-fk | Insert two peer rows with the same `baseUrl` | The second insert violates `uniq_peer_base_url` and rejects; deleting a peer row cascades to delete its snapshot row |
| status-server-libsql-029 | error-row-uniqueness | Upsert two error rows with the same `issueKey` | The row is updated in place, not duplicated; `count`/`userCount` default to `0` and `resolved` to `false` on first insert |
| status-server-libsql-030 | analytics-metrics-indexing | A query plan for a select filtered by `metric`/`window`/`scope` and ordered by `capturedAt`, and separately for a prune filtered by `capturedAt < cutoff` alone | The first uses `idx_analytics_metric_time`; the second uses `idx_analytics_captured`, not a full scan |
| status-server-libsql-031 | user-uniqueness | Insert a user row with `passwordHash: null` and a distinct `githubId` | Insert succeeds (an OAuth-only account) with `role` reading back `'pending'`; a second insert with the same `email` violates `uniq_user_email` |
| status-server-libsql-032 | session-token-hash-only, api-token-hash-only, device-auth-hash-only-except-raw | Read the session, API-token, and device-authorization table definitions | None declares a column for a raw session token or raw API bearer; the device-authorization table's raw-token column is the only column of the three tables typed to hold a plaintext secret |
| status-server-libsql-033 | api-token-created-at-app-default | Insert an API-token row via raw SQL, omitting `created_at` | The insert fails a NOT NULL constraint, because `createdAt` has no database-level default — unlike the site-group table's `createdAt`, whose equivalent raw-SQL insert succeeds via the database's own current-time function |
| status-server-libsql-034 | device-auth-status | Insert a device-authorization row supplying only its required fields | `status` reads back `'pending'`, `cliLabel` reads back `''`; a `tokenId` referencing a deleted API-token row is set to `null` rather than blocking the delete |
| status-server-libsql-035 | exported-row-types | Import the exported user, new-user, and session row types from the schema | Each type-checks against the shape produced by the user table's own select/insert column definitions and the session table's own select column definitions |

## Edge Cases

- **Null and empty input**: an empty connection URL is rejected explicitly
  by connection-url-required, the one input validation this storage layer
  performs; every other "missing" value in the schema (a nullable column
  with no default — `providerProjectId`, `error`, `resolvedReason`,
  `deployProjectId`, `token`) is a first-class, documented `null`, not an
  unhandled gap.
- **Boundary values**: the checkpoint operation's `frames` count defaults
  to `0` when the checkpoint result row or its `checkpointed` field is
  absent (checkpoint-result-shape) — the fallback is a boundary case
  handled explicitly, not an unguarded read. `metricsHourly.hour` and
  `analyticsMetrics.capturedAt` are unix-second timestamps truncated to
  their aggregation boundary by callers external to this storage layer
  (the schema itself carries no truncation logic).
- **Concurrent access**: the entire concurrency-tuning half of this storage
  layer (tune-wal-mode, tune-busy-timeout, tune-synchronous-normal) exists
  because the API server and the monitor worker hold independent
  connections to the same embedded file. `uniq_open_issue_per_target` and
  `uniq_metrics_service_hour` are the schema's own concurrency guards — a
  losing concurrent insert is rejected by the database itself, not
  silently merged. The checkpoint operation's fail-soft `busy` result is
  the documented outcome when a checkpoint races a live reader.
- **Error states**: the connection-opening operation throws synchronously
  for the one input it validates (an empty URL); every unique-index and
  foreign-key violation in the schema (issue-uniqueness-open,
  metrics-hourly-uniqueness, peer-uniqueness, user-uniqueness,
  session-token-hash-only, api-token-hash-only,
  device-auth-hash-only-except-raw) surfaces as a rejected promise from the
  underlying database driver — nothing in this storage layer wraps or
  swallows a driver rejection anywhere.
- **Offline / disconnected state**: a remote connection going unreachable
  is not handled by this storage layer directly — the embedded-file check
  routes all tuning and checkpointing around remote connections
  specifically because a remote database manages its own journaling,
  durability, and storage. Reconnection, retry, and backoff for a remote
  connection are the responsibility of the underlying database driver,
  external to this storage layer.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| connection URL | a string | required | The one validated input to the connection-opening operation; a `file:` prefix selects the embedded-file/WAL/checkpoint code paths, anything else a remote-database connection. |
| connection auth token | an optional string | absent | Passed through unchanged to the underlying connection; irrelevant for an embedded file, required by a remote database that enforces one. |
| migrations folder | a string | the migrations-folder constant | Overridable only for tests; production callers always take the default. |
| migrations-folder constant | a module-level constant | the package's own `src/libsql/migrations` subdirectory | The migrations this package ships, resolved via the host runtime's own module-resolution mechanism (see Platform Notes). |

## Deep Linking

Not applicable: this storage layer defines no application URL scheme; it is a database connection and schema module, not a routable surface.

## Localization

Not applicable: this storage layer emits no user-facing string. Every text value it defines (`'healthy' | 'degraded' | 'down'`, platform-id prefixes, `'pending' | 'viewer' | 'admin'`, and so on) is an internal enum literal or SQL identifier consumed by other backend code, never displayed directly.

## Accessibility Options

Not applicable: this storage layer has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this storage layer consults no feature-flag system.

## Analytics

Not applicable: this storage layer emits no analytics or telemetry event; `analyticsMetrics` and `errors` are this backend's own STORAGE for analytics/error summaries polled from elsewhere, not a source of outbound analytics about this module itself.

## Privacy

- **Data collected**: `users` stores an email, an optional bcrypt password
  hash, an optional external-identity id, and a display name (identity
  data); `sessions`/`apiTokens`/`deviceAuthorizations` store only the
  sha256 hash of a session token, API bearer, device code, and user code —
  never the raw secret at rest — with `deviceAuthorizations.tokenRaw` as
  the one documented, time-boxed exception (held only between approval and
  the single successful poll, then the row is deleted by code external to
  this recipe). `errors` and `analyticsMetrics` store polled, aggregate
  summaries (issue titles/culprits, pageview/visitor counts), not raw
  end-user request data.
- **Storage**: everything in this recipe's scope is persisted in the same
  embedded database file (or remote database) the connection-opening
  operation connects to. No table writes to a second store.
- **Transmission**: this storage layer performs no network calls of its
  own for an embedded-file connection; a remote connection's transport
  security is the underlying driver's responsibility, external to this
  recipe. The auth token is passed to that driver unchanged, never logged
  or persisted here.
- **Retention**: `healthChecks`, `metricsHourly`, `issues`,
  `analyticsMetrics`, and `deployments` are pruned/aged out by callers
  external to this recipe; several of the schema's own secondary indexes
  (`idx_health_checked`, `idx_metrics_hour`, `idx_issue_opened`,
  `idx_analytics_captured`, `idx_deploy_inflight`) exist specifically to
  make that external age-based pruning cheap. `deviceAuthorizations` rows
  are opportunistically reaped on a time-to-live (`expires_at`) — also
  external to this recipe. This storage layer itself deletes no row.

## Logging

Not applicable: this storage layer contains no logging call at any level.

## Platform Notes

- **React/Web** (source platform): the two files live under
  `packages/web/packages/status-server/src/libsql/`, on top of
  `drizzle-orm/sqlite-core` and `drizzle-orm/libsql` (including its
  `migrator` submodule), Node's built-in `node:module`
  (`createRequire`) and `node:path`/`node:crypto`, and the
  `@agentic-toolkit/deploy-platform/schema` and `../monitor/deploy-status`
  siblings the schema re-exports from and builds its partial index against
  (the partial index's predicate calls `inFlightSql('')` from
  `../monitor/deploy-status`). The package's own root directory is
  resolved via `createRequire(import.meta.url).resolve('@agentic-toolkit/status-server/package.json')`,
  so `MIGRATIONS_FOLDER` is correct whether the caller runs from `src/`,
  from a built `dist/` chunk, or from a host's vendored `node_modules`
  copy; migrations apply through `drizzle-orm/libsql/migrator`'s
  `migrate`, recording each in a `__drizzle_migrations` bookkeeping table.
  `apiTokens.createdAt` and `deviceAuthorizations.createdAt` are populated
  via a Drizzle `$defaultFn` (`() => new Date()`) rather than a SQL-level
  `DEFAULT`, unlike every other timestamp column in this schema, which
  defaults via Drizzle's `.default(now)` (a SQL `unixepoch()` default).
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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/libsql/client.ts` |
| web | `packages/web/packages/status-server/src/libsql/schema.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | Reliability |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |

`separation-of-concerns` passes: `client.ts` owns the connection lifecycle
(open, tune, checkpoint, migrate) and `schema.ts` owns only the table
shapes; neither file contains a query, a route, or a probe — those live in
sibling modules (`db/config.ts`, `monitor/`, the Hono routes) that import
these two files rather than being imported by them. `unit-test-coverage`
passes: the sibling `test/` suite exercises `migrateDb`'s idempotency
(`migrate-idempotent.int.test.ts`) and pins every shipped migration's hash
(`migrations-immutable.test.ts`); the schema's own constraints
(unique indexes, foreign keys) are exercised indirectly by the integration
tests of the modules that write through them. `explicit-error-handling`
passes: `openLibsql`'s one validated input throws synchronously with a
specific message, and every unique-index/foreign-key violation propagates
as a rejected promise from the underlying driver — neither file wraps or
swallows a failure anywhere. `data-integrity` passes: seven unique indexes
(`uniq_metrics_service_hour`, `uniq_open_issue_per_target`,
`uniq_site_group_slug`, `uniq_site_group_site_slug`, `uniq_peer_base_url`,
`uniq_error_issue`, `uniq_user_email`/`uniq_user_github`,
`uniq_session_token`, `uniq_api_token_hash`, `uniq_device_code`/`uniq_user_code`)
and six foreign keys enforce the schema's own invariants at the database
layer rather than trusting callers to. `idempotent-operations` passes:
`migrateDb` is explicitly designed and tested to be safe to call
repeatedly (migrate-idempotent), and `tuneDbForConcurrency`'s pragmas are
documented as safe to re-apply. `state-recovery` passes: `peerSnapshots`
and `platformHealthState` exist specifically so a restarted, stateless
serverless process recovers its last-known fleet/platform state from disk
rather than starting blank, per their table comments. `timeout-handling`
is `partial`: `busy_timeout=5000` bounds how long a second writer waits on
`SQLITE_BUSY` for an embedded file, but neither file applies any
timeout to a remote libsql/Turso connection's network calls — that is left
entirely to the `@libsql/client` driver `drizzle()` wraps, external to
these two files. `secure-storage` passes: every credential-shaped column
in `sessions`/`apiTokens`/`deviceAuthorizations` stores a sha256 hash, with
`tokenRaw` as the one explicitly time-boxed, single-use, never-listed
exception documented in its own column comment.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/storage/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
