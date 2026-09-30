<!-- leaf: implement-status-server/stores--part-3 · source: status-server-stores.md -->

# Status Server Stores — continued (part 3)

**Rules** (cite as `implement-status-server/stores--part-3#<slug>`):

- `owned-scope-predicate` MUST
- `shared-not-duplicated` MUST
- `active-peer-listing` MUST
- `snapshot-upsert` MUST
- `snapshot-listing` MUST
- `chunked-upsert` MUST
- `invalid-createdat-dropped-not-failed` MUST
- `created-at-minimum` MUST
- `fetched-at-advances` MUST
- `webhook-poll-ordering-guard` MUST
- `project-name-refreshed` MUST
- `provider-project-id-non-erasing` MUST
- `learn-project-ids-chunked` MUST
- `prune-by-age` MUST
- `in-flight-expiry` MUST
- `mark-gone-and-phases` MUST
- `error-text-set-once-elsewhere` MUST
- `project-meta-crud` MUST
- `owned-scoped-listing` MUST
- `find-by-id` MUST
- `shared-lifecycle-predicates` MUST
- `read-only-surface` MUST
- `owned-scoped-deploy-events` MUST
- `tie-safe-pagination` MUST
- `group-crud` MUST
- `site-crud-cascade` MUST
- `endpoint-crud-cascade` MUST
- `atomic-two-statement-write` MUST
- `active-endpoints-listing` MUST
- `toctou-safe-retire` MUST
- `fresh-subquery-orphan-reconcile` MUST
- `integration-crud` MUST
- `delete-integration-one-directional` MUST
- `ignored-projects-tolerant-read` MUST
- `ignored-projects-write` MUST
- `peer-crud` MUST

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

