<!-- leaf: implement-status-server/storage--part-3 · source: status-server-storage.md -->

# Status Server Storage Boundary — continued (part 3)

**Rules** (cite as `implement-status-server/storage--part-3#<slug>`):

- `upsert-deployments` MUST
- `learn-project-ids` MUST
- `prune-older-than-days` MUST
- `list-for-live-host-stamp` MUST
- `set-live-host` MUST
- `list-in-flight-candidates` MUST
- `mark-deploy-gone` MUST
- `mark-deploy-phases` MUST
- `expire-stale-in-flight` MUST
- `list-failed-without-error` MUST
- `set-error-text` MUST
- `upsert-project-meta` MUST
- `list-project-meta-names` MUST
- `list-project-meta` MUST
- `delete-project-meta` MUST
- `list-recent-owned` MUST
- `find-by-id` MUST
- `list-open` MUST
- `insert-issue` MUST
- `update-issue` MUST
- `resolve-issue` MUST
- `resolve-unmonitored-targets` MUST
- `record-observations` MUST
- `record-vercel-prod-states` MUST
- `rollup-metrics` MUST
- `run-maintenance` MUST
- `snapshot-if-due` MUST
- `read-roster` MUST
- `read-deploy-outcome-candidates` MUST
- `read-deploy-events` MUST
- `read-issue-events` MUST
- `read-open-issue-targets` MUST
- `read-platform-facts` MUST
- `read-stale-prod-facts` MUST
- `read-error-facts` MUST
- `read-deploy-activity-page` MUST
- `read-issue-opened-page` MUST
- `read-issue-resolved-page` MUST
- `newest-check-at` MUST
- `checks-for` MUST
- `daily-counts` MUST
- `response-buckets` MUST
- `purge-expired` MUST
- `create` MUST
- `find-by-device-code-hash` MUST
- `find-by-user-code-hash` MUST
- `delete-by-id` MUST
- `mark-polled` MUST
- `consume-approved` MUST
- `approve` MUST
- `deny` MUST
- `token-role-and-expiry` MUST
- `list-active` MUST
- `upsert-snapshot` MUST
- `list-snapshots` MUST

### Deploy Store

- **upsert-deployments**: MUST accept array of `DeployUpsertInput` and optional `{ source?: 'poll' | 'webhook' }`, MUST dedupe the batch by `id` (last wins), MUST drop (and log with `console.error`) any deploy whose `createdAt` is not a valid Date, and MUST upsert by `id`. A 'poll' (or unspecified) source overwrites both phases; a 'webhook' source keeps the stored phase when `webhookKeepsStoredSql` says so, so a webhook never walks a row backwards. `projectName` is overwritten, descriptive columns COALESCE (a null never erases a stored value), `createdAt` keeps the earliest value seen, and `fetchedAt` is restamped.
- **learn-project-ids**: MUST accept array of `{ platform, projectName, providerProjectId? }`, MUST backfill `deployProjectId` on any endpoint whose `deployProjectId` is null and whose canonical platform (`platformCanon`) and `deployProject` match a deploy carrying a `providerProjectId` (the first id seen per name wins), MUST never overwrite an existing id.
- **prune-older-than-days**: MUST accept `days` (number), MUST delete all `deployments` rows with `createdAt` older than that many days.
- **list-for-live-host-stamp**: MUST return every `deployments` row's `{ id, platform, providerProjectId, projectName, environment, liveHost }`.
- **set-live-host**: MUST accept deploy `id` and host string (or null), MUST persist it.
- **list-in-flight-candidates**: MUST accept `{ platforms: string[], excludeIds: string[], createdAfterMs: number, fetchedBeforeMs: number, limit: number }`, MUST return `DeployIdPlatformRow` entries for unconfirmed deploys within the time window, newest-created first, capped at limit.
- **mark-deploy-gone**: MUST accept deploy `id`, MUST collapse in-flight lifecycle to canceled/none.
- **mark-deploy-phases**: MUST accept `id` and `{ buildPhase, deployPhase }`, MUST overwrite both phases (new phases are authoritative).
- **expire-stale-in-flight**: MUST accept `olderThanMs`, MUST collapse every in-flight deploy unconfirmed for at least that duration to unknown/unknown, MUST return row count affected.
- **list-failed-without-error**: MUST accept `{ platforms: string[], createdAfterMs: number, limit: number }`, MUST return failed deploys with no error text yet.
- **set-error-text**: MUST accept deploy `id` and error text string, MUST persist it.
- **upsert-project-meta**: MUST accept array of `ProjectMetaInput` rows, MUST upsert in chunks internally.
- **list-project-meta-names**: MUST accept `platform` string, MUST return all project names stored for that platform.
- **list-project-meta**: MUST return every `ProjectMetaRow` across all platforms.
- **delete-project-meta**: MUST accept `platform` and array of project names, MUST delete matching rows in chunks.
- **list-recent-owned**: MUST accept `OwnedProjects` map and `limit` number, MUST return the `limit` most recent `DeploymentRow` entries that some live site monitors, newest-created first; crunchy clusters are always included.
- **find-by-id**: MUST accept deploy `id`, MUST return `DeployLogRow` (identity + persisted error summary) or null.

### Issue Store

- **list-open**: MUST return every currently-open `IssueRow`, oldest-first by `openedAt` then `id` (row 0 per target is canonical; rows after are shadows).
- **insert-issue**: MUST accept `IssueInsert`, MUST NOT alert, and MUST insert-or-ignore: when an open issue already exists for the target the partial unique index (one open issue per target) rejects the row and the call silently does nothing.
- **update-issue**: MUST accept `id` (number) and `IssuePatch`, MUST refresh derived fields in place and stamp `updatedAt`; an omitted `commitHash`/`commitMessage`/`commitRepo` is written as null.
- **resolve-issue**: MUST accept `id` (number) and `reason` ('recovered', 'unmonitored', 'duplicate'), MUST close the issue.
- **resolve-unmonitored-targets**: MUST accept array of target strings, MUST resolve all open issues for those targets as 'unmonitored', MUST be a no-op on empty array.

### Observation Store

- **record-observations**: MUST accept array of `PlatformObservationInput` (each with `source` string, `configured` boolean, `reachable` boolean), MUST persist and track consecutive-failure streak.
- **record-vercel-prod-states**: MUST accept array of `VercelProdStateInput`, MUST replace the Vercel stale-production mirror entirely; projects absent from the input MUST be deleted; MUST be a no-op on empty array (the caller must pass only a complete read). On conflict `stale` and `detail` are overwritten while a null `sourceUrl`/`liveUrl` keeps the stored link.

### Maintenance Store

- **rollup-metrics**: MUST accept array of service slugs, MUST aggregate `metrics_hourly` for each service's current hour bucket.
- **run-maintenance**: MUST accept optional `{ maxRows?, chunkRows? }`, MUST prune retention across all accruing tables, MUST WAL-checkpoint when adapter has live connection, MUST return `{ deleted: number, done: boolean }`.
- **snapshot-if-due**: MUST accept optional `SnapshotOptions { dbUrl?, intervalMs?, keep?, now? }`, MUST VACUUM INTO a rotated on-volume snapshot if configured interval elapsed, MUST use adapter's connection url unless overridden, MUST return `{ created: boolean, path?: string }`.

### Board Store

- **read-roster**: MUST return all monitored endpoints with columns ownership resolves from.
- **read-deploy-outcome-candidates**: MUST return every concluded or in-flight deploy (one per platform, projectName, environment group); binning by outcome is pure logic in caller.
- **read-deploy-events**: MUST accept `sinceMs` (epoch ms) and `OwnedProjects`, MUST return all ungrouped deploys some live site monitors inside the window, newest-first, capped at MAX_ACTIVITY_ROWS.
- **read-issue-events**: MUST accept `sinceMs`, MUST return issues that opened OR closed inside the window, newest-event-first, capped.
- **read-open-issue-targets**: MUST return every currently-open issue's target + onset — the ledger continuity floor.
- **read-platform-facts**: MUST return the platform-health mirror, one row per polled platform.
- **read-stale-prod-facts**: MUST return Vercel projects whose live production deploy is stale.
- **read-error-facts**: MUST return unresolved GlitchTip error groups, newest activity first, capped at MAX_ERROR_FACTS.
- **read-deploy-activity-page**: MUST accept `PageCursor { beforeMs, strict, limit }` and `OwnedProjects`, MUST return one page of the deploy-activity feed, owned-narrowed, as `SourcePage<DeployFact>`.
- **read-issue-opened-page**: MUST accept `PageCursor` and array of target strings, MUST return one page of issues by `openedAt` narrowed to targets.
- **read-issue-resolved-page**: MUST accept `PageCursor` and array of targets, MUST return one page of issues by `resolvedAt` narrowed to targets.

### History Store

- **newest-check-at**: MUST return the newest `checked_at` across all history as a Date, or null if no checks exist — the poller's "last ran" clock.
- **checks-for**: MUST accept endpoint `slug` and `hours` number, MUST return that endpoint's samples within the last `hours` as ascending `HistoryCheckRow` array.
- **daily-counts**: MUST accept `slug` and `days` number, MUST return per-UTC-day counts over the last `days` as ascending `DailyCountsRow` array (total, healthy, degraded, down).
- **response-buckets**: MUST accept `hours` and `buckets` number, MUST return portfolio-wide response-time sparkline as array of length `buckets` over the last `hours` (oldest → newest), each entry the average response time of UP checks or null if no data.

### Device Store (RFC 8628 device-authorization grants)

- **purge-expired**: MUST delete every grant past its expiry; run opportunistically before minting a new one.
- **create**: MUST accept `{ deviceCodeHash, userCodeHash, cliLabel, expiresAt }`, MUST insert a freshly-requested grant.
- **find-by-device-code-hash**: MUST accept hash string, MUST return `DeviceGrantRow` or null.
- **find-by-user-code-hash**: MUST accept hash string, MUST return `DeviceGrantRow` or null.
- **delete-by-id**: MUST accept `id`, MUST remove the grant.
- **mark-polled**: MUST accept `id`, MUST stamp `lastPollAt`. The port documents it for a still-pending grant; the adapter does not check status, so calling it only on a pending grant is a caller precondition.
- **consume-approved**: MUST accept grant `id`, MUST delete the row and read its stashed secret in one delete-returning statement, returning `{ tokenRaw, tokenId }`; MUST return null if the row is gone or carries no stashed token. The adapter deletes the row whatever its status, so a caller consumes only after seeing the grant approved.
- **approve**: MUST accept `id` and `{ tokenId, tokenRaw, approvedBy }`, MUST mark still-pending grant approved, guarded on status so racing approvers cannot both win, MUST return false if status guard did not match.
- **deny**: MUST accept `id`, MUST mark still-pending grant denied, guarded on status, MUST return false if guard did not match.
- **token-role-and-expiry**: MUST accept `tokenId`, MUST return `{ role, expiresAt }` or null.

### Peer Store

- **list-active**: MUST return active `PeerRow` entries only — the roster both poller and fleet reader use.
- **upsert-snapshot**: MUST accept `PeerSnapshotUpsert { peerId, fetchedAt, payload, overall, reachable, error }`, MUST upsert one peer's snapshot by peerId.
- **list-snapshots**: MUST return every stored `PeerSnapshotRow`, one per peer.

