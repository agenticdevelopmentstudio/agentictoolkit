---
id: 82524881-6da8-42fe-85a9-388651ee085d
title: Status Server Stores
domain: agentictoolkit://cookbook/status-server/libsql/stores
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The status backend''s libSQL/Drizzle persistence layer: 13 store factories
  composed by `createLibsqlStorage`, plus one shared predicate helper, and the
  atomic guards, chunked bulk writes, and reconciliation sweeps that keep the
  schema honest under a monitor cycle that polls and a webhook that pushes
  concurrently.'
platforms:
- typescript
- web
tags:
- status-server
- libsql
- drizzle
- persistence
- storage-ports
depends-on:
- agenticdevelopercookbook://guidelines/implementing/data/database
- agenticdevelopercookbook://guidelines/implementing/data/transactions-and-concurrency
- agenticdevelopercookbook://guidelines/implementing/data/foreign-keys
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
related:
- agentictoolkit://cookbook/status-server/libsql
- agentictoolkit://cookbook/status-server/storage/ports
- agentictoolkit://cookbook/status-server/auth
references:
- packages/web/packages/status-server/src/libsql/stores/auth-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/token-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/device-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/health-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/history-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/issue-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/observation-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/owned-deploys.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/peer-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/deploy-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/board-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/config-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/maintenance-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/telemetry-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/index.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/issue-sources.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/test/last-admin-guard.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/upsert-deployments.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-upsert-guard.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/telemetry-errors-store.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/device-flow.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/site-delete-purge.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Stores

## Overview

This is the status backend's storage-port implementation layer: 14 files under
`src/libsql/stores/` that are the ONLY code in the package allowed to import
Drizzle's query builder or the driver types alongside `src/storage/ports.ts`'s
plain-domain interfaces. Thirteen of the files each export one
`createXStore(db, ...)` factory returning a port object (`AuthStore`,
`TokenStore`, `DeviceStore`, `HealthStore`, `HistoryStore`, `IssueStore`,
`ObservationStore`, `PeerStore`, `DeployStore`, `BoardStore`, `ConfigStore`,
`MaintenanceStore`, `TelemetryStore`); `src/libsql/index.ts`'s
`createLibsqlStorage(db, conn?)` composes all 13 into one `Storage` object,
passing `conn` only to `createMaintenanceStore`. The fourteenth file,
`owned-deploys.ts`, is not a store — it exports `ownedDeploysWhere(projects)`,
a shared SQL-predicate helper that `deploy-store.ts` and `board-store.ts` both
call to scope a query to a caller's owned platform/project set. Every method
on every port either returns a plain domain type from `ports.ts` or resolves
`void`/`boolean`/`number` — no query-builder or driver type crosses back out
of this layer. The methods embed atomic guards directly in SQL WHERE/subquery
clauses rather than reading then writing, to close race windows a monitor
cycle (polling) and a webhook route (pushing) can otherwise open against the
same row concurrently: the last-admin guard (`auth-store.ts`), the
webhook-vs-poll ordering guard (`deploy-store.ts`), the TOCTOU-safe
conditional deletes (`config-store.ts`), and the single-use atomic
delete-returning device-grant consumption (`device-store.ts`). Bulk writes
are chunked to stay under SQLite's per-statement parameter-count limit and
keep individual transactions small (`deploy-store.ts`'s
`UPSERT_CHUNK_PROJECTS`, `config-store.ts`'s `DELETE_CHUNK_NAMES`,
`maintenance-store.ts`'s `PRUNE_CHUNK_ROWS`/`PRUNE_MAX_ROWS_PER_RUN`), and
several failure paths are deliberately fail-soft (WAL checkpoint, DB
snapshot, orphan reconcile) so that a maintenance side-effect can never fail
the monitor cycle it rides along with. Secrets are hash-only at rest across
`auth-store.ts`, `token-store.ts`, and `device-store.ts`, with one documented,
time-boxed exception. `telemetry-store.ts` reconciles a polled "currently
unresolved" set against the stored table rather than only appending to it,
so an issue that stops being reported is swept closed instead of staying
open forever.

## Behavioral Requirements

### Composition (index.ts)

- **storage-composition**: `createLibsqlStorage(db, conn?)` MUST return a
  `Storage` object with exactly these 13 keys, each built by calling the
  matching factory once: `config`, `auth`, `tokens`, `health`, `deploy`,
  `issues`, `observations`, `maintenance`, `board`, `history`, `device`,
  `peers`, `telemetry`.
- **connection-descriptor-scoping**: the optional `conn` (a
  `LibsqlConnection`) MUST be passed only to `createMaintenanceStore(db,
  conn)`; no other factory receives it. Omitting `conn` MUST still produce a
  complete `Storage` object — `createMaintenanceStore` treats a missing
  `conn` as "storage was built without a connection descriptor" (see
  `no-conn-degrades-maintenance` below), not as a construction error.

### Auth (auth-store.ts)

- **user-lookup**: `findUserByEmail`, `findUserByGithubId`, and
  `getUserById` MUST each return `undefined` (never throw, never a
  sentinel row) when no matching `users` row exists, and MUST return a
  `UserRecord` (including its stored password hash) when one does.
- **create-user-defaults**: `createUser` MUST insert a new `users` row and
  return the created `UserRecord`; a duplicate email or GitHub id MUST
  reject with the underlying unique-constraint violation rather than being
  pre-checked and swallowed.
- **role-listing-shape**: `listUsers` MUST return `AuthUser[]` (the
  password-hash-free, role-carrying projection), never the raw
  `UserRecord[]`.
- **last-admin-guard-update**: `setUserRoleGuarded(id, role)` MUST perform
  the role change and the "is this the last admin" check as one atomic
  UPDATE whose WHERE clause is `(role != 'admin' OR :role = 'admin' OR
  (select count(*) from users where role = 'admin') > 1)`, and MUST return
  the literal string `"blocked"` (not a thrown error, not `undefined`) when
  that WHERE clause excludes every row because the target is the sole
  remaining admin being demoted.
- **last-admin-guard-delete**: `deleteUserGuarded(id)` MUST apply the same
  atomic last-admin predicate to its DELETE, returning `"blocked"` when the
  target is the sole remaining admin, `true` when a row was deleted, and
  `false` when no row matched the id at all (a third, distinguishable
  outcome from `"blocked"`).
- **admin-count**: `countAdmins` MUST return the current count of `users`
  rows with `role = 'admin'` as a plain `number`.
- **session-lifecycle**: `createSession(userId, ttlMs = SESSION_TTL_MS)`
  MUST generate a fresh random token, persist only `tokenHash` (never the
  raw token) plus `expiresAt = now + ttlMs`, and return the one-time raw
  token to the caller; `resolveSession(token)` MUST hash the presented
  token, look up a non-expired `sessions` row by that hash, and return the
  owning user's `AuthUser` or `null` for a missing/expired/`undefined`
  token; `revokeSession(token)` MUST delete the matching row and MUST
  resolve without error when `token` is `undefined` or matches no row.

### API tokens (token-store.ts)

- **mint-hash-only**: `mintApiToken(input)` MUST generate a raw bearer
  token, persist only its `tokenHash` and a display-only `prefix` (the
  first `PREFIX_LEN` characters, `sts_`-namespaced via `TOKEN_PREFIX`), and
  return `{ meta, raw }` where `raw` is returned exactly once and is never
  written to storage in full.
- **validate-by-hash**: `validateApiToken(raw)` MUST hash the presented raw
  token and look up a non-revoked, non-expired `apiTokens` row by that
  hash, returning a `TokenPrincipal` on a match and `null` otherwise —
  including for an expired row, a revoked row, and a hash with no match.
- **token-listing-shape**: `listApiTokens` MUST return `ApiTokenMeta[]`
  (prefix and metadata only), never a raw or hashed token value.
- **revoke-vs-delete**: `revokeApiToken(id)` MUST mark the row revoked
  in place (kept for audit) and return `true` iff a row with that id
  existed; `deleteApiToken(id)` MUST remove the row entirely and return
  `true` iff a row with that id existed. Both MUST return `false`, not
  throw, for an id that matches no row.

### Device authorization (device-store.ts)

- **hash-only-persistence**: `create(input)` MUST persist
  `deviceCodeHash`/`userCodeHash` only — never the raw device or user code
  — alongside `status: "pending"` and an `expiresAt`.
  `findByDeviceCodeHash`/`findByUserCodeHash` MUST look up by the
  precomputed hash the caller supplies and return `null` for no match.
- **purge-expired**: `purgeExpired` MUST delete every `deviceAuthorizations`
  row whose `expiresAt` is in the past, and MUST resolve even when no row
  is expired.
- **approve-status-guard**: `approve(id, patch)` MUST update the row's
  status to `"approved"` (applying `patch`) only when its current status
  is `"pending"`, and MUST return `false` — not throw — when the row is
  missing or already in any other status, so a code that is polled,
  approved, and re-approved cannot silently re-run the approval side
  effects.
- **deny-status-guard**: `deny(id)` MUST apply the same "only from
  `pending`" guard as `approve`, setting status to `"denied"` and
  returning `false` for a non-`pending` or missing row.
- **single-use-consume**: `consumeApproved(id)` MUST atomically read and
  clear the row's one-time `tokenRaw`/`tokenId` in a single
  delete-returning statement scoped to `status = 'approved'`, returning
  `{ tokenRaw, tokenId }` exactly once for a given approved grant and
  `null` on every subsequent call for the same id (whether because it was
  already consumed or never approved) — this is the source's documented
  single-use, TOCTOU-safe consumption path, not a read-then-delete.
- **mark-polled**: `markPolled(id)` MUST update the row's last-polled
  timestamp and MUST resolve without error for a missing id (a poll racing
  a delete is not a fault).
- **role-and-expiry-lookup**: `tokenRoleAndExpiry(tokenId)` MUST return
  `{ role, expiresAt }` for a minted token id or `null` when the id is
  unknown.

### Health checks (health-store.ts)

- **latest-checks-batch**: `latestChecks(slugs)` MUST return one
  `LatestCheckRow` per slug in `slugs` that has at least one recorded
  check, using the single query `latestCheckBySlugSql(slugs)` — never one
  query per slug.
- **bad-run-onsets**: `badRunOnsets(slugs)` MUST return, per slug, the
  timestamp at which its current unbroken run of failing checks began, or
  omit the slug when its latest check is passing.
- **record-checks-bulk**: `recordChecks(checks)` MUST insert every
  `HealthCheckInput` in `checks` as its own `health_checks` row (append,
  never upsert — history is the point) and MUST resolve as a no-op for an
  empty array without issuing a statement.
- **checks-summary**: `checksSummary` MUST return the total sample count
  and the distinct-service count across all recorded checks.
- **last-checked-at**: `lastCheckedAtMs` MUST return the most recent
  check's timestamp in epoch milliseconds, or `null` when no check has
  ever been recorded.

### History and rollups (history-store.ts)

- **newest-check-at**: `newestCheckAt` MUST return the most recent
  `health_checks.checkedAt` across all services, or `null` for an empty
  table.
- **checks-for-window**: `checksFor(slug, hours)` MUST return every
  `health_checks` row for `slug` within the trailing `hours`-hour window,
  ordered so the caller can read it as a timeline.
- **daily-counts**: `dailyCounts(slug, days)` MUST return one
  `DailyCountsRow` per calendar day in the trailing `days`-day window for
  `slug`, including days with zero checks (a sparse day is a fact, not an
  absent row).
- **response-buckets**: `responseBuckets(hours, buckets)` MUST divide the
  trailing `hours`-hour window into exactly `buckets` equal-width
  sub-windows and return one average-or-`null` response value per bucket,
  `null` for a bucket with no checks in it.

### Issues (issue-store.ts)

- **list-open**: `listOpen` MUST return every `issues` row not yet
  resolved, as `IssueRow[]`.
- **insert-issue**: `insertIssue(input)` MUST insert a new open issue from
  an `IssueInsert`; the schema's own `uniq_open_issue_per_target` unique
  index (external to this file) is what prevents two simultaneously-open
  issues for the same target — `insertIssue` itself performs no
  pre-check, relying on that constraint to reject a duplicate.
- **update-issue**: `updateIssue(id, patch)` MUST apply `patch`'s fields
  to the row with that id and MUST resolve without error if no row
  matches (an issue closed by a concurrent resolve is not a fault for the
  update to report).
- **resolve-with-reason**: `resolveIssue(id, reason)` MUST mark the issue
  resolved, recording `reason` as one of the literal values
  `"recovered"`, `"unmonitored"`, or `"duplicate"`.
- **bulk-resolve-unmonitored**: `resolveUnmonitoredTargets(targets)` MUST
  resolve every currently-open issue whose target is in `targets` with
  reason `"unmonitored"`, and MUST resolve as a no-op for an empty
  `targets` array without issuing a statement whose `IN ()` would be
  invalid SQLite syntax.

### Platform observations (observation-store.ts)

- **streak-debounced-recording**: `recordObservations(observations)` MUST,
  per `PlatformObservationInput`, read the row's current
  `consecutiveFailures`, compute the next streak and "bad" verdict via
  `nextPlatformStreak(prevStreak, failing)` (imported from
  `monitor/issue-sources.ts`; a single passing poll resets the streak to
  `0` immediately, while a `bad` verdict requires the failure streak to
  reach the threshold), and upsert `platformHealthState` with the computed
  `consecutiveFailures`/`reachable`. The source comment states this
  function is the ONLY writer of `consecutiveFailures` in the codebase —
  a precondition on the wider system's call discipline, not a rule this
  file enforces on its own callers.
- **vercel-staleness-upsert**: `recordVercelProdStates(states)` MUST
  upsert one `platformHealthState`-adjacent row per state in `states` on
  conflict, then MUST delete every previously-stored row for a platform
  not present in the new `states` list for that call, so a project that
  stops being reported as a Vercel prod target stops being tracked as one.
- **tolerate-unmigrated-table**: any read that hits a
  not-yet-migrated table MUST distinguish a driver error whose message
  matches `/no such table|does not exist|not found/i` (tolerated, treated
  as "no data yet") from every other driver error (rethrown) — this is the
  same pattern `config-store.ts`'s `listIgnoredProjects` uses, not unique
  to this file.

### Owned-project predicate (owned-deploys.ts)

- **owned-scope-predicate**: `ownedDeploysWhere(projects)` MUST return a
  Drizzle `SQL` fragment (or `undefined`) that scopes a `deployments` query
  to exactly the platform/project-name pairs named in an `OwnedProjects`
  set, and MUST return `undefined` — not a fragment that matches nothing
  or everything — when `projects` denotes no scoping at all, so a caller
  can splice the result into a WHERE clause unconditionally.
- **shared-not-duplicated**: `deploy-store.ts`'s `listRecentOwned` and
  `board-store.ts`'s `readDeployEvents`/`readDeployActivityPage` MUST each
  call this one exported function rather than re-deriving their own
  platform/project predicate, so the definition of "owned" cannot drift
  between the deploy log and the board.

### Peer fleet-view (peer-store.ts)

- **active-peer-listing**: `listActive` MUST return every `peers` row
  currently marked active, as `PeerRow[]`, with no redaction applied in
  this file — `redactPeer()` (defined in `ports.ts`, external to this
  file) is the documented redaction step, applied by a caller outside
  this store before a peer row reaches an untrusted audience.
- **snapshot-upsert**: `upsertSnapshot(row)` MUST insert a new
  `peerSnapshots` row or overwrite the existing one for that peer on
  conflict, so only the latest snapshot per peer is ever retained by this
  method.
- **snapshot-listing**: `listSnapshots` MUST return the current
  one-row-per-peer snapshot set as `PeerSnapshotRow[]`.

### Deployments (deploy-store.ts)

- **chunked-upsert**: `upsertDeployments(deploys, opts?)` MUST upsert in
  batches no larger than `UPSERT_CHUNK_PROJECTS` deployments per
  statement, to stay under SQLite's bound parameter-count limit.
- **invalid-createdat-dropped-not-failed**: a deployment in the input
  array whose `createdAt` fails validation MUST be dropped from that
  chunk's statement (logged via `console.error` with the message
  `` `[sync] deploy ${d.id} has an invalid createdAt — dropping it
  (fetcher should have caught this)` ``) rather than failing the whole
  batch — one bad row from an upstream fetcher MUST NOT block every valid
  row alongside it from being stored.
- **created-at-minimum**: on conflict, `createdAt` MUST be updated to
  `min(excluded.created_at, created_at)` — never overwritten upward —
  because a webhook event's timestamp is emission time, always at or after
  true creation time.
- **fetched-at-advances**: on conflict, `fetchedAt` MUST be updated to the
  time of this upsert (advances monotonically), independent of
  `createdAt`'s minimum rule.
- **webhook-poll-ordering-guard**: on conflict, columns governed by
  `webhookKeepsStoredSql`/`columnOverwritableSql` (imported from
  `monitor/deploy-status.ts`) MUST NOT let a stale webhook event regress a
  column past either (a) an already-settled verdict or (b) a phase later
  in `IN_FLIGHT_BUILD_ORDER` than the one the event reports, while a poll
  (`opts.source` unset or not `"webhook"`) MUST be allowed to move the
  same column backward to in-flight, because a poll's by-id read is
  current truth rather than a possibly-reordered event.
- **project-name-refreshed**: on conflict, `projectName` MUST be
  overwritten unconditionally (never frozen at insert), so a project
  rename upstream is reflected rather than leaving the row keyed to a
  stale name in every subsequent `groupBy(platform, projectName,
  environment)` read.
- **provider-project-id-non-erasing**: on conflict,
  `providerProjectId` MUST be updated via COALESCE-style
  keep-if-sparser-source logic — a sparser source (for example a webhook
  payload with no id) MUST NOT erase an already-stored value; a richer
  source with a new id MUST overwrite it.
- **learn-project-ids-chunked**: `learnProjectIds(...)` MUST also chunk
  its writes and MUST only ever narrow `providerProjectId` from unset to
  set, never overwrite an already-set value with a different one.
- **prune-by-age**: `pruneOlderThanDays(days)` MUST delete every
  `deployments` row older than `days` days.
- **in-flight-expiry**: `expireStaleInFlight(olderThanMs)` MUST move every
  deployment whose build/deploy phase is in-flight (per `isInFlight` from
  `monitor/deploy-status.ts`) and whose last update predates
  `olderThanMs` to a terminal "gone/unknown" phase via
  `collapseInFlightBuildSql`/`collapseInFlightDeploySql`, and MUST return
  the count of rows it changed.
- **mark-gone-and-phases**: `markDeployGone(id)` and
  `markDeployPhases(id, phases)` MUST each update exactly the row matching
  `id`, resolving without error if no row matches.
- **error-text-set-once-elsewhere**: `setErrorText(id, text)` MUST set the
  stored error text for a deployment; `listFailedWithoutError(input)` MUST
  return only failed deployments whose error text is still unset, so a
  caller can target enrichment at exactly the rows that need it.
- **project-meta-crud**: `upsertProjectMeta`, `listProjectMetaNames`,
  `listProjectMeta`, and `deleteProjectMeta` MUST manage the
  `deploy_project_meta` table keyed by `(platform, name)`;
  `deleteProjectMeta(platform, names)` MUST chunk its deletion no larger
  than `DELETE_CHUNK_NAMES` names per statement and MUST no-op for an
  empty `names` array rather than issue an invalid empty `IN ()`.
- **owned-scoped-listing**: `listRecentOwned(owned, limit)` MUST scope its
  query with `ownedDeploysWhere(owned)` and MUST return at most `limit`
  rows, most-recent first.
- **find-by-id**: `findById(id)` MUST return the full `DeployLogRow` for
  `id` or `null` when no such deployment exists.

### Board read model (board-store.ts)

- **shared-lifecycle-predicates**: every read that classifies a deployment
  as concluded, in-flight, having an outcome, or lacking a lifecycle MUST
  use the module's shared `CONCLUDED`/`IN_FLIGHT`/`HAS_OUTCOME`/
  `NO_LIFECYCLE` SQL predicates rather than re-deriving equivalent
  conditions per method, so the board's definition of each state cannot
  drift between `readRoster`, `readDeployOutcomeCandidates`, and the
  paginated readers.
- **read-only-surface**: `readRoster`, `readDeployOutcomeCandidates`,
  `readDeployEvents`, `readIssueEvents`, `readOpenIssueTargets`,
  `readPlatformFacts`, `readStaleProdFacts`, and `readErrorFacts` MUST
  each be a pure read with no side effect on the underlying tables — this
  store never writes.
- **owned-scoped-deploy-events**: `readDeployEvents(sinceMs, owned)` MUST
  scope with `ownedDeploysWhere(owned)` and MUST return only events at or
  after `sinceMs`.
- **tie-safe-pagination**: `readDeployActivityPage(cursor, owned)`,
  `readIssueOpenedPage(cursor, targets)`, and `readIssueResolvedPage(cursor,
  targets)` MUST each accept a `PageCursor` and return a `SourcePage<T>`
  whose `beforePredicate` breaks ties on a secondary key (not timestamp
  alone), so two rows with the same timestamp are never silently dropped
  or duplicated across a page boundary.

### Monitoring configuration (config-store.ts)

- **group-crud**: `listSiteGroups`, `createGroup`, `updateGroup`, and
  `deleteGroup` MUST manage `site_groups`; `deleteGroup` MUST also delete
  every `monitored_sites`/`monitored_endpoints` row scoped under that
  group and every `health_checks`/`issues` row for those endpoints in the
  same call, so deleting a group MUST NOT leave orphaned history or open
  issues behind it.
- **site-crud-cascade**: `createSite`, `updateSite`, and `deleteSite`
  parallel the group operations one level down; `deleteSite` MUST cascade
  the same history/issue purge for the endpoints under that site.
- **endpoint-crud-cascade**: `createEndpoint`, `updateEndpoint`, and
  `deleteEndpoint` MUST manage `monitored_endpoints`; `deleteEndpoint`
  MUST purge that endpoint's `health_checks` and resolve its open
  `issues` via `purgeEndpointHistory`.
- **atomic-two-statement-write**: any create/update path here that must
  write two related statements as one unit (for example inserting a row
  and its default child rows) MUST use `db.batch(...)`, never
  `db.transaction(...)` — the source comment documents that this driver's
  `transaction()` hands off the connection and nulls its own handle, so
  against a `:memory:` database the next statement after a
  `db.transaction()` call lazily opens a brand-new, empty in-memory
  database instead of continuing the one just written to.
- **active-endpoints-listing**: `listActiveEndpoints` MUST return every
  endpoint eligible to be polled right now, as `ConfiguredEndpoint[]`,
  joined up through its site and group.
- **toctou-safe-retire**: `retireEndpoint(id)` MUST perform its
  conditional delete as a single statement whose WHERE clause includes a
  `NOT EXISTS` subquery re-evaluated at delete time (never a separate
  read-then-delete), so a row that became newly ineligible between a
  caller's check and this call is still handled correctly rather than
  raced.
- **fresh-subquery-orphan-reconcile**: `reconcileOrphanedEndpoints` MUST
  recompute its orphan set as a subquery evaluated at delete time (not
  from a previously-read id list), and MUST log via `console.error` with
  the prefix `[config] orphan endpoint/site reconcile failed:` and return
  a partial `{ endpoints, sites, prunedEndpointIds }` result reflecting
  whatever portion of the two-step delete actually completed, rather than
  letting a failure partway through the reconcile propagate uncaught.
- **integration-crud**: `listIntegrations`, `createIntegration`, and
  `updateIntegration` MUST manage the `integrations` table.
- **delete-integration-one-directional**: `deleteIntegration(id)` MUST
  delete the integration and MUST set
  `platformHealthState.configured = false` for its platform as part of
  the same statement, but MUST NEVER itself set `configured = true` — the
  source comment states the monitor cycle is the only thing allowed to
  make that determination, and this method can only ever weaken it toward
  `false`, one-directionally.
- **ignored-projects-tolerant-read**: `listIgnoredProjects` MUST tolerate
  a not-yet-migrated `ignored_projects` table by treating a driver error
  matching `/no such table|does not exist|not found/i` as "no ignored
  projects yet" and rethrowing every other error unchanged.
- **ignored-projects-write**: `addIgnoredProject`,
  `addIgnoredProjects` (chunked bulk form), and `removeIgnoredProject`
  MUST manage the `ignored_projects` table by `(platform, projectName)`.
- **peer-crud**: `listPeers`, `createPeer`, `updatePeer`, and `deletePeer`
  MUST manage the `peers` table used by config-side peer administration
  (distinct from `peer-store.ts`'s fleet-view snapshot reads).

### Maintenance (maintenance-store.ts)

- **rollup-metrics**: `rollupMetrics(serviceSlugs)` MUST recompute and
  upsert `metrics_hourly` buckets for every hour touched by
  `health_checks` rows for `serviceSlugs`, via the exported
  `rollupMetricsSql(serviceSlugs)` fragment.
- **budgeted-chunked-prune**: the retention prune inside `runMaintenance`
  MUST delete in batches no larger than `PRUNE_CHUNK_ROWS` rows per
  statement and MUST stop once it has deleted `PRUNE_MAX_ROWS_PER_RUN`
  rows in a single call, deferring any remaining backlog to the next
  scheduled run rather than running one unbounded delete.
- **fail-soft-checkpoint**: `runMaintenance`'s WAL-checkpoint step MUST
  catch any error from `checkpointWal` and log it via `console.error` with
  the message `` `[maintenance] wal checkpoint failed: ${message}` ``
  rather than letting a checkpoint failure abort the rest of the
  maintenance cycle.
- **no-conn-degrades-maintenance**: when `createMaintenanceStore` was
  built without a `conn`, the WAL-checkpoint and DB-snapshot steps MUST
  be skipped rather than throw; the first time either step is skipped,
  `warnNoConn(step)` MUST log exactly once per store instance via
  `console.warn` with the message `` `[maintenance] ${step} skipped:
  storage was built without a connection descriptor
  (createLibsqlStorage(db, conn)) — WAL checkpoint and DB snapshots are
  disabled` `` — every later skip in the same store instance MUST NOT
  log again.
- **snapshot-fail-soft**: `snapshotIfDue(opts?)` MUST catch any error
  from the VACUUM-INTO snapshot attempt, log it via `console.error` with
  the message `` `[snapshot] failed: ${message}` ``, and resolve `{
  created: false }` rather than reject — a failing backup MUST NOT fail
  the maintenance cycle it rides along with.
- **snapshot-success-logged**: on a successful snapshot,
  `snapshotIfDue` MUST log via `console.log` with the message
  `` `[snapshot] wrote ${finalPath}` `` and resolve `{ created: true,
  path: finalPath }`.

### Telemetry (telemetry-store.ts)

- **errors-reconcile-not-append**: `errorsStore.save(items, opts?)` MUST
  upsert every item in `items` by `issueKey` and MUST then resolve every
  currently-unresolved row NOT present in `items` to `resolved = true`,
  UNLESS `opts.complete === false`, in which case the sweep MUST be
  skipped entirely for that call — an item present in `items` but not
  seen on a prior call MUST also be reopened (`resolved` reset to
  `false`) via the upsert's own `excluded.resolved` conflict clause.
- **empty-poll-resolves-all**: an empty `items` array with
  `opts.complete !== false` MUST resolve every still-open row, and MUST
  do so via a branch that does not compile to `NOT IN ()` (invalid SQLite
  syntax for an empty exclusion list) — this is the case
  `notInArray` cannot express directly and the store MUST route around
  it explicitly.
- **fetched-at-not-restamped-on-sweep**: a row resolved by the sweep
  (because it was absent from the poll) MUST NOT have its `fetchedAt`
  updated — `fetchedAt` records when a row was last actually seen, and a
  swept row was, by definition, not seen this poll.
- **truncated-poll-logged-not-swept**: when the upstream poll itself was
  truncated (a full page with no confirmation the answer is complete),
  `save` MUST upsert whatever it saw and MUST skip the sweep, logging via
  `console.warn` with the message `` `[telemetry] GlitchTip returned a
  full page (${items.length}); the unresolved set is truncated, so no
  rows were swept this poll` `` — sweeping a partial page would resolve
  everything past its edge and cause a flap between open and resolved on
  every subsequent poll for a project whose issue count straddles the
  page boundary.
- **project-refreshed-on-conflict**: on conflict, `project` MUST be
  overwritten (never frozen at first insert) — `project` is the field the
  board mints its issue-ledger key from, so a stale value would derive a
  target no current fact mentions.
- **analytics-append-only**: `analyticsStore.save(items)` MUST plain
  insert every item with no conflict handling — analytics rows are
  point-in-time samples, never upserted or reconciled the way errors are.
- **errors-and-analytics-load**: `errorsStore.load()` MUST return only
  currently-unresolved rows; `analyticsStore.load()` MUST return every
  stored sample.

## Appearance

Not applicable — this is a persistence layer, not a visual component.

## States

Not applicable — this is a persistence layer, not a visual component.

## Accessibility

Not applicable — this is a persistence layer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-stores-001 | last-admin-guard-update, last-admin-guard-delete | A single admin's `id`; `setUserRoleGuarded(id, 'user')` | Returns `"blocked"`; the row's role is unchanged — `last-admin-guard.int.test.ts` |
| status-server-stores-002 | last-admin-guard-update | Two admins; demote one via `setUserRoleGuarded` | Succeeds (returns the updated `AuthUser`); the demoted user's role becomes `'user'` — `last-admin-guard.int.test.ts` |
| status-server-stores-003 | provider-project-id-non-erasing | Upsert a deploy with `providerProjectId: 'prj_abc'`, then upsert the same id from a webhook with `providerProjectId: null` | Stored `providerProjectId` remains `'prj_abc'` — `upsert-deployments.test.ts` › "sets provider_project_id on insert and refreshes it on conflict" |
| status-server-stores-004 | project-name-refreshed | Upsert a deploy under `projectName: 'hub-help-testing'`, then re-upsert the same id under `projectName: 'hub-help'` | Stored `projectName` becomes `'hub-help'` — `upsert-deployments.test.ts` › "follows an upstream RENAME" |
| status-server-stores-005 | webhook-poll-ordering-guard | Upsert `{ buildPhase: 'failed', deployPhase: 'none' }`, then upsert the same id from a webhook with `{ buildPhase: 'building', deployPhase: 'none' }` | Stored `buildPhase` remains `'failed'` — `upsert-deployments.test.ts` › "a stale in-flight WEBHOOK does not regress a stored verdict" |
| status-server-stores-006 | webhook-poll-ordering-guard | Upsert `{ buildPhase: 'built', deployPhase: 'deployed' }`, then upsert the same id from a poll (no `opts.source`) with `{ buildPhase: 'built', deployPhase: 'deploying' }` | Stored `deployPhase` becomes `'deploying'` — `upsert-deployments.test.ts` › "a POLL may move a row back to in-flight" |
| status-server-stores-007 | created-at-minimum, fetched-at-advances | Upsert `createdAt: 2026-08-02T10:00:00Z`, then upsert the same id from a webhook with `createdAt: 2026-08-02T11:00:00Z` | Stored `createdAt` stays `2026-08-02T10:00:00.000Z`; `fetchedAt` advances — `upsert-deployments.test.ts` › "createdAt takes the MINIMUM and fetchedAt advances" |
| status-server-stores-008 | invalid-createdat-dropped-not-failed | One upsert call with a valid deploy and a second deploy whose `createdAt` is `new Date('nonsense')` | Only the valid deploy's row exists afterward; the batch does not reject — `upsert-deployments.test.ts` › "drops a row with an invalid createdAt instead of failing the batch" |
| status-server-stores-009 | errors-reconcile-not-append | `errorsStore.save([a, b])`, then `errorsStore.save([b])` | `load()` returns only `b`; the underlying row for `a` has `resolved = true` (kept, not deleted) — `telemetry-errors-store.int.test.ts` › "resolves an issue that VANISHED from the next poll, keeping the row" |
| status-server-stores-010 | empty-poll-resolves-all | `errorsStore.save([a, b])`, then `errorsStore.save([])` | `load()` returns `[]`; every stored row has `resolved = true` — `telemetry-errors-store.int.test.ts` › "an EMPTY poll resolves everything still open" |
| status-server-stores-011 | errors-reconcile-not-append | `errorsStore.save([a])`, `errorsStore.save([])`, then `errorsStore.save([a])` again | The row for `a` reopens (`resolved` becomes `false`) rather than staying resolved — `telemetry-errors-store.int.test.ts` › "REOPENS a swept issue when it fires again" |
| status-server-stores-012 | fetched-at-not-restamped-on-sweep | Age a stored row's `fetchedAt` by an hour, then sweep it via an empty `save([])` | The row's `fetchedAt` stays at the aged timestamp, not `now` — `telemetry-errors-store.int.test.ts` › "does not restamp fetchedAt on the rows it sweeps" |
| status-server-stores-013 | truncated-poll-logged-not-swept | `save([a, b])`, then `save([a with count:99], { complete: false })` | Both `a` and `b` remain in `load()`; `a`'s `count` updates to `99`; `b` stays unresolved — `telemetry-errors-store.int.test.ts` › "upserts what it saw and sweeps NOTHING" |
| status-server-stores-014 | project-refreshed-on-conflict | `save([err({ project: 'adh' })])`, then `save([err({ project: 'adh-web' })])` | The one stored row's `project` becomes `'adh-web'` — `telemetry-errors-store.int.test.ts` › "refreshes the project when the issue moves or the project is renamed" |
| status-server-stores-015 | single-use-consume | `create` a device grant, `approve` it, then call `consumeApproved(id)` twice | First call returns `{ tokenRaw, tokenId }`; second call returns `null` — `device-flow.int.test.ts` |
| status-server-stores-016 | approve-status-guard, deny-status-guard | `approve(id, patch)` on a grant already in status `"denied"` | Returns `false`; the row's status remains `"denied"` — `device-flow.int.test.ts` |
| status-server-stores-017 | mint-hash-only, validate-by-hash | `mintApiToken(input)`, then `validateApiToken(raw)` with the returned `raw` | `validateApiToken` returns a matching `TokenPrincipal`; the stored `apiTokens` row has no plaintext token column — `device-flow.int.test.ts` (token-store exercised via the device-flow route) |
| status-server-stores-018 | group-crud, site-crud-cascade, endpoint-crud-cascade | `createGroup` → `createSite` → `createEndpoint` → `recordChecks` a check for that endpoint → `deleteSite(siteId)` | The site, its endpoints, and their `health_checks`/`issues` rows are all gone; the parent group is untouched — `site-delete-purge.int.test.ts` |
| status-server-stores-019 | toctou-safe-retire | `retireEndpoint(id)` for an endpoint that is the only one under its site and is not referenced elsewhere | The endpoint row is deleted in the same call whose `NOT EXISTS` subquery re-checked eligibility, not from a separately-read id — `site-delete-purge.int.test.ts` |
| status-server-stores-020 | bulk-resolve-unmonitored | `resolveUnmonitoredTargets([])` | Resolves as a no-op; no statement with an empty `IN ()` is issued (mirrors the `notInArray`-on-empty pattern pinned for `errorsStore.save` in `telemetry-errors-store.int.test.ts`) |
| status-server-stores-021 | no-conn-degrades-maintenance | `createLibsqlStorage(db)` (no `conn`), then `maintenance.runMaintenance()` twice | Neither call throws; `console.warn` fires exactly once across both calls, on the first skipped step |
| status-server-stores-022 | fail-soft-checkpoint, snapshot-fail-soft | Force the WAL-checkpoint or VACUUM-INTO step to reject inside `runMaintenance`/`snapshotIfDue` | The surrounding call still resolves (`{ created: false }` for the snapshot case); the error is logged via `console.error`, not thrown |

## Edge Cases

- **Null and empty input**: `recordChecks([])`, `resolveUnmonitoredTargets([])`,
  `deleteProjectMeta(platform, [])`, and `errorsStore.save([])` (with
  `complete !== false`) MUST each be handled by an explicit empty-input
  branch rather than compiling to an invalid empty `IN ()`/`NOT IN ()`
  SQLite statement. `resolveSession(undefined)` and `revokeSession(undefined)`
  MUST resolve `null`/void respectively, not throw.
- **Boundary values**: a device grant exactly at its `expiresAt` boundary
  is a fact resolved by `purgeExpired`'s own comparison, external to any
  store method's return value; `expireStaleInFlight(olderThanMs)`'s
  boundary (a deployment whose last update is exactly `olderThanMs` old)
  is decided by the SQL comparison in `collapseInFlightBuildSql`/
  `collapseInFlightDeploySql`, not restated here. `PRUNE_MAX_ROWS_PER_RUN`
  being reached mid-run is not an error: the prune simply stops and
  leaves the remainder for the next scheduled `runMaintenance` call.
- **Concurrent access**: the last-admin guard (`setUserRoleGuarded`,
  `deleteUserGuarded`) and the single-use device-grant consumption
  (`consumeApproved`) are the two places two concurrent callers racing
  the same row is an expected, correctly-handled case — both resolve the
  race inside one SQL statement's WHERE/subquery rather than via a
  read-then-write round trip in application code. `deploy-store.ts`'s
  webhook-vs-poll ordering guard is the same pattern applied to a
  different race: a webhook event and a poll result for the same
  deployment id arriving out of order. `recordObservations` being "the
  ONLY writer" of `consecutiveFailures` is a documented precondition on
  the wider system (only one monitor cycle runs at a time), not a lock
  this file itself takes.
- **Error states**: `observation-store.ts`'s and `config-store.ts`'s
  not-yet-migrated-table tolerance (`listIgnoredProjects`,
  `platformFailureCounts`-style reads) rethrows every driver error except
  one matching `/no such table|does not exist|not found/i`, so a real
  connectivity or syntax error is never mistaken for "no data yet."
  `deploy-store.ts` drops a single invalid-`createdAt` row from a batch
  (logged) rather than failing every valid row alongside it.
  `config-store.ts`'s `reconcileOrphanedEndpoints` and
  `maintenance-store.ts`'s `runMaintenance`/`snapshotIfDue` each log and
  continue past a failure in one step rather than letting it abort the
  whole call.
- **Offline or disconnected state**: not applicable at this layer — every
  method here assumes an already-open `Db` handle; connection
  establishment, retry, and offline detection belong to `client.ts`
  (external to these 14 files, covered by the `status-server-libsql`
  recipe) and to the caller that constructs `conn` before calling
  `createLibsqlStorage`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `conn` | `LibsqlConnection \| undefined` | `undefined` | Passed to `createLibsqlStorage(db, conn)`; forwarded only to `createMaintenanceStore`. Omitting it degrades `runMaintenance`/`snapshotIfDue` to a logged no-op for their checkpoint/snapshot steps rather than failing construction. |
| `SESSION_TTL_MS` | `number` (module constant, `auth-store.ts`) | source-defined | Session lifetime passed to `createSession`'s default `ttlMs` parameter when a caller does not override it. |
| `UPSERT_CHUNK_PROJECTS` | `number` (module constant, `deploy-store.ts`) | `200` | Maximum deployments per upsert statement in `upsertDeployments`/`learnProjectIds`. |
| `DELETE_CHUNK_NAMES` | `number` (module constant, `config-store.ts`/`deploy-store.ts`) | `500` | Maximum names per chunked delete statement (`deleteProjectMeta`, ignored-project bulk deletes). |
| `PRUNE_CHUNK_ROWS` | `number` (module constant, `maintenance-store.ts`) | `25_000` | Maximum rows deleted per statement inside the retention prune. |
| `PRUNE_MAX_ROWS_PER_RUN` | `number` (module constant, `maintenance-store.ts`) | `100_000` | Total row-delete budget per `runMaintenance` call before the remaining backlog is deferred to the next run. |
| `opts.source` | `"webhook" \| undefined` | `undefined` | `upsertDeployments(deploys, opts)`'s discriminator between a webhook push (ordering-guarded) and a poll (treated as current truth). |
| `opts.complete` | `boolean \| undefined` | `undefined` (treated as `true`) | `errorsStore.save(items, opts)`'s discriminator for whether `items` is a whole answer (sweep runs) or a truncated page (sweep skipped). |
| `SnapshotOptions` fields | object | source-defined | Passed to `snapshotIfDue(opts)` to control snapshot cadence/destination; an omitted option set uses the store's built-in defaults. |
| `TOKEN_PREFIX` / `PREFIX_LEN` | `string` / `number` (module constants, `token-store.ts`) | `'sts_'` / source-defined | Display-only API-token prefix format; never affects the hashed value used for validation. |

## Deep Linking

Not applicable: none of these 14 files construct, parse, or resolve a URL or app link — they accept plain domain values and rows, traced across every method signature captured above.

## Localization

Not applicable: the only user-observable strings this layer produces are internal log lines (see Logging) and error-code-shaped return values (`"blocked"`, `false`, `null`); none of the 14 files formats end-user-facing copy.

## Accessibility Options

Not applicable — this is a persistence layer with no rendered surface for an accessibility setting to affect.

## Feature Flags

Not applicable: no file in this layer branches on a feature-flag value; every conditional traced above (`opts.source`, `opts.complete`, `conn` presence) is an explicit caller-supplied parameter, not a flag.

## Analytics

Not applicable to this layer's own operation: `telemetry-store.ts`'s `analyticsStore` persists analytics data collected by a fetcher external to these 14 files, but none of the 14 files emits telemetry about its own calls, latency, or usage.

## Privacy

- **Data collected**: `auth-store.ts` persists an email, optional password
  hash, optional GitHub id, and role per user. `token-store.ts` persists
  only a `tokenHash` and a display-only `prefix` per API token — never the
  raw bearer. `device-store.ts` persists only `deviceCodeHash`/
  `userCodeHash` per grant, with `tokenRaw` as the one documented,
  time-boxed exception: held in the row only between `approve` and the
  single successful `consumeApproved` call, which clears it as part of
  the same atomic statement. `telemetry-store.ts` persists polled,
  aggregate third-party data (GlitchTip issue titles/culprits/counts,
  analytics pageview/visitor counts) — not raw end-user request data.
- **Storage**: every store in this layer persists through the single `Db`
  handle it is constructed with; none opens a second connection or writes
  to a second store.
- **Transmission**: none of these 14 files performs a network call —
  `validateApiToken`, `resolveSession`, and every other lookup compare
  only locally-computed hashes against stored hashes; the raw secret a
  caller presents is hashed in-process and never re-transmitted or logged
  by this layer.
- **Retention**: `pruneOlderThanDays` (deploy-store.ts), the retention
  prune inside `runMaintenance` (maintenance-store.ts), and `purgeExpired`
  (device-store.ts) are this layer's own retention mechanisms;
  `deleteGroup`/`deleteSite`/`deleteEndpoint`'s history/issue cascades
  (config-store.ts) are retention triggered by an explicit administrative
  delete rather than age. No other file in this layer deletes a row on a
  schedule of its own.

## Logging

This layer logs at six call sites, all via the global `console` object —
never a structured logger, and never a secret value:

- `deploy-store.ts`'s `upsertDeployments` logs `console.error` with
  `` `[sync] deploy ${d.id} has an invalid createdAt — dropping it
  (fetcher should have caught this)` `` when it drops an invalid row.
- `config-store.ts`'s `reconcileOrphanedEndpoints` logs `console.error`
  with the prefix `[config] orphan endpoint/site reconcile failed:`
  followed by the caught error.
- `maintenance-store.ts` logs `console.warn` once per store instance (via
  `warnNoConn`) with the message `` `[maintenance] ${step} skipped:
  storage was built without a connection descriptor
  (createLibsqlStorage(db, conn)) — WAL checkpoint and DB snapshots are
  disabled` ``, `console.error` on a failed WAL checkpoint with
  `` `[maintenance] wal checkpoint failed: ${message}` ``, and both
  `console.log` (`` `[snapshot] wrote ${finalPath}` ``) and
  `console.error` (`` `[snapshot] failed: ${message}` ``) around the
  VACUUM-INTO snapshot attempt.
- `telemetry-store.ts`'s `errorsStore.save` logs `console.warn` with
  `` `[telemetry] GlitchTip returned a full page (${items.length}); the
  unresolved set is truncated, so no rows were swept this poll` `` when a
  poll is truncated.

No other file in this layer contains a logging call; `auth-store.ts`,
`token-store.ts`, and `device-store.ts` in particular log nothing, so a
hash comparison's success or failure never appears in a log line.

## Platform Notes

- **TypeScript / Node (source)**: this layer is written directly against
  Drizzle ORM's query builder over `@libsql/client`; every atomic guard is
  expressed as a single SQL statement's WHERE/subquery/`ON CONFLICT`
  clause rather than an application-level lock, which is what makes the
  guards safe under Node's single-threaded, interleaved-`await` execution
  model.
- **SwiftUI / AppKit / UIKit**: a client consuming this same contract
  would model each store as a small `actor` (or a `@MainActor`-isolated
  service) exposing `async throws` methods mirroring the port signatures;
  a device-grant's single-use consumption (`consumeApproved`) maps to a
  server round trip whose response is only ever accepted once client-side
  too — the client MUST NOT infer "not consumed yet" from a `nil`
  response without a fresh request, since the guard's authority is the
  server's atomic statement, not client-side caching.
- **Jetpack Compose (Kotlin)**: model each store as a `class` exposing
  `suspend fun` methods returning sealed result types (mirroring
  `"blocked"`/`true`/`false`/`null` as a sealed class rather than a raw
  boolean-or-string union), backed by a Retrofit/Ktor client; the
  webhook-vs-poll ordering guard has no client-side analog — a Compose
  client only ever sees the server's already-reconciled state and MUST
  NOT attempt to re-derive the ordering rule locally.
- **WinUI 3**: model each store as a service class using `HttpClient` for
  the network hop and `System.Text.Json` for (de)serializing the same
  plain domain shapes `ports.ts` defines, with results surfaced through an
  `ObservableCollection<T>` (for list-shaped reads like `listActive`,
  `listOpen`, `listRecentOwned`) and `INotifyPropertyChanged` for
  single-row state (a resolved session, a consumed device grant); every
  method should be `async Task<T>`, and a `"blocked"`/`false`/`null`
  outcome should surface as a discriminated result type rather than a
  thrown exception, matching this layer's own use of return values (not
  throws) for an expected "guard tripped" outcome.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/libsql/stores/` |

## Design Decisions

- **Decision**: embed the last-admin check inside the same UPDATE/DELETE
  statement that performs the role change or deletion, instead of a
  separate `countAdmins` read followed by a conditional write.
  **Rationale**: a read-then-write split leaves a window in which two
  concurrent requests can each read "more than one admin remains" and
  then both demote/delete, leaving zero admins; folding the count into
  the statement's own WHERE clause makes the check and the write atomic
  under SQLite's single-statement execution, with no window between them.
  **Approved**: pending
- **Decision**: use `db.batch(...)` rather than `db.transaction(...)` for
  every atomic multi-statement write in `config-store.ts`.
  **Rationale**: the source comment documents that this driver's
  `transaction()` hands off the connection to a transaction-scoped handle
  and nulls its own, so the very next statement issued against the
  original handle lazily reopens a brand-new, empty `:memory:` database
  instead of continuing the one already written to — a behavior specific
  to the in-memory driver mode this backend's test suite relies on.
  `db.batch(...)` sends all statements in one round trip without that
  handle hand-off, so it is the only multi-statement primitive that stays
  correct against both a `:memory:` database and a persistent one.
  **Approved**: pending
- **Decision**: let a poll move a deployment's phase backward to
  in-flight while blocking a webhook from doing the same.
  **Rationale**: `monitor/deploy-status.ts`'s `webhookKeepsStoredSql`
  comment documents two failure modes a webhook is uniquely exposed to —
  a stale event overwriting an already-settled verdict, and a stale event
  overwriting a later in-flight phase — because webhook delivery order is
  not guaranteed. A poll has no such ordering problem: it reads the
  provider's current by-id state directly, so its result is definitionally
  current truth and applying it is always correct, including moving a
  phase backward.
  **Approved**: pending
- **Decision**: chunk every bulk write (`UPSERT_CHUNK_PROJECTS`,
  `DELETE_CHUNK_NAMES`, `PRUNE_CHUNK_ROWS`) and cap total prune work per
  call (`PRUNE_MAX_ROWS_PER_RUN`).
  **Rationale**: SQLite/libSQL bounds the number of parameters a single
  statement may bind; chunking keeps every generated statement under that
  bound regardless of input size, and capping the prune's total row
  budget per call keeps any single `runMaintenance` invocation's
  transaction small and bounded rather than proportional to however large
  the backlog has grown, deferring the remainder to the next scheduled run.
  **Approved**: pending
- **Decision**: make the WAL checkpoint and DB snapshot steps fail-soft
  (`try`/`catch` + `console.error`/`console.warn`, never a rethrow) inside
  `maintenance-store.ts`.
  **Rationale**: both are secondary, disk-housekeeping side effects
  riding along with the maintenance cycle; a failure in either MUST NOT
  prevent the rest of the cycle (the retention prune, the metrics rollup)
  from completing, and both failures are still visible operationally
  because each is logged, not silently discarded.
  **Approved**: pending
- **Decision**: recompute `config-store.ts`'s orphan set and
  `retireEndpoint`'s eligibility check as a subquery evaluated at delete
  time, rather than reading a set of ids first and deleting by that list.
  **Rationale**: a read-then-delete-by-id-list has a TOCTOU window in
  which the set changes between the read and the delete (another request
  reactivates an endpoint the reconcile is about to remove); a subquery
  re-evaluated as part of the DELETE statement itself closes that window
  because the eligibility check and the delete are the same atomic
  operation.
  **Approved**: pending
- **Decision**: make `errorsStore.save` a full reconciliation of the
  polled "currently unresolved" set — upserting what is present and
  sweeping to `resolved = true` whatever previously-open row is absent —
  instead of only ever appending or upserting-without-sweeping.
  **Rationale**: the source's own test-file comment documents the
  regression this closes: before the sweep existed, nothing in the
  codebase ever wrote `resolved = true`, so an issue that stopped being
  reported by the upstream poll stayed open in this table forever and a
  problem built on it could go red and never go green. Gating the sweep
  on `opts.complete !== false` prevents the same reconciliation from
  wrongly resolving rows past the edge of a truncated (paginated) poll.
  **Approved**: pending
- **Decision**: store only `tokenHash`/`deviceCodeHash`/`userCodeHash`
  across `auth-store.ts`, `token-store.ts`, and `device-store.ts`, with
  `deviceAuthorizations.tokenRaw` as the sole exception, held only between
  `approve` and the single successful `consumeApproved` call.
  **Rationale**: hashing every long-lived secret at rest means a database
  read (a backup, a leaked snapshot, an operator query) never yields a
  usable credential; the one raw-value exception is scoped as narrowly as
  the device-authorization flow allows — it exists only in the short
  window between a human approving a device and that device's single
  poll consuming the result, and `consumeApproved`'s delete-returning
  statement clears it as part of the same atomic read that hands it out.
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
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`separation-of-concerns` passes: each of the 13 store files owns exactly one
port's implementation against the driver, `owned-deploys.ts` owns exactly
one shared predicate, and none of the 14 files contains a route handler,
an HTTP concern, or a monitor-cycle scheduling decision — those live in
sibling modules that import this layer rather than being imported by it.
`unit-test-coverage` passes: the sibling `test/` suite exercises the
last-admin guard (`last-admin-guard.int.test.ts`), the upsert ordering and
minimum/COALESCE rules (`upsert-deployments.test.ts`,
`deploy-upsert-guard.test.ts`), the errors-reconciliation sweep
(`telemetry-errors-store.int.test.ts`), the device-authorization flow
(`device-flow.int.test.ts`), and the group/site/endpoint delete cascade
(`site-delete-purge.int.test.ts`) — each targeting exactly the atomic-guard
or reconciliation behavior that would be easiest to silently regress.
`explicit-error-handling` passes: every tolerated failure path in this
layer (the not-yet-migrated-table checks, the fail-soft checkpoint and
snapshot, the orphan-reconcile catch) matches a specific, narrow error
signature or is logged before being swallowed — none of the 14 files
contains a bare catch that discards an error with no signal at all.
`data-integrity` passes: every atomic guard in this recipe (last-admin,
device-grant single-use, TOCTOU-safe conditional deletes, webhook-vs-poll
ordering) is expressed as a single SQL statement rather than a
read-then-write pair, so the invariant it protects cannot be violated by
an interleaving of two concurrent calls. `idempotent-operations` passes:
`upsertDeployments`, `errorsStore.save`, `recordVercelProdStates`, and
every peer-snapshot/project-meta upsert are all safe to call repeatedly
with the same or updated input, converging on the latest state rather
than accumulating duplicates. `state-recovery` passes: `peer-store.ts`'s
snapshot table and `observation-store.ts`'s platform-health state exist
specifically so a restarted process recovers the fleet's last-known state
from disk rather than starting blank, mirroring the same pattern the
`status-server-libsql` recipe documents for the schema those tables
belong to. `secure-storage` passes: `auth-store.ts`, `token-store.ts`, and
`device-store.ts` persist a hash, never a raw secret, with exactly one
documented, time-boxed, single-use exception (`tokenRaw` in
`device-store.ts`, cleared atomically by `consumeApproved`).
`no-pii-in-logs` passes: every logged message identified in this recipe's
Logging section names a deployment id, a step name, a file path, or a
row count — never an email, a password hash, a session/API/device-code
hash, or a `tokenRaw` value.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
