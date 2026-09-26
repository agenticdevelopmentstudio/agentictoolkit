---
id: 1c240b7a-21b3-4a89-b24f-a5bf5cf5f37b
title: Status Server Storage Boundary
domain: agentictoolkit://cookbook/status-server/storage/ports
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Storage port interface for status-server: persists configuration, auth,
  health checks, deployments, issues, and telemetry via plain domain types.'
platforms:
- typescript
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Status Server Storage Boundary

## Overview

The storage boundary defines plain-domain-type interfaces through which every consumer (routes, monitor, board, MCP tools, peers, telemetry) reads and writes. The boundary accepts only domain types (no query builders, driver clients, or schema aliases); its libSQL/SQLite implementation is the sole adapter permitted to speak to the driver. Storage composes 13 specialized stores (Config, Auth, Token, Health, Deploy, Issues, Observations, Maintenance, Board, History, Device, Peer, Telemetry) into one object threaded through `createApp`.

## Behavioral Requirements

### Config Store

- **list-site-groups**: MUST return all `GroupRow` objects with no filtering.
- **create-group**: MUST accept `{ name, slug, retentionDays? }`, persist as a `GroupRow` with server-generated `id`, `createdAt`, `updatedAt`, and MUST return the persisted row.
- **update-group**: MUST accept `id` and a partial patch, MUST return the updated `GroupRow` or null if no row exists.
- **delete-group**: MUST accept `id` and remove the row. The libSQL adapter cascades in application code (libSQL over HTTP does not enforce ON DELETE CASCADE): it collects every endpoint of the group's sites, purges their history via `purgeEndpointHistory`, then deletes those endpoints, the sites, and finally the group.
- **list-sites**: MUST return all `SiteRow` objects with no filtering.
- **create-site**: MUST accept `{ name, slug, siteGroupId }`, MUST return a persisted `SiteRow` with server-generated `id`, `createdAt`, `updatedAt`.
- **update-site**: MUST accept `id` and a partial patch, MUST return updated `SiteRow` or null.
- **delete-site**: MUST accept `id` and remove the row. The adapter cascades in application code: it purges the site's endpoints' history, deletes those endpoints, then deletes the site.
- **list-endpoints**: MUST return all `EndpointRow` objects; if `siteId` is provided, MUST filter by `siteId`.
- **create-endpoint**: MUST accept required `siteId`, `url` and optional fields (kind, environment, platform, deployProject, deployProjectId, ignoreProjectWarning, expectedStatus, expectBody, dnsCheckA, dnsCheckAaaa, dnsCheckCname, checkIntervalSeconds, isActive, monitorHttp, monitorDeploys), MUST return persisted `EndpointRow` with defaults applied.
- **update-endpoint**: MUST accept `id` and a partial patch of the mutable endpoint fields (every `createEndpoint` field except `siteId`; `id`, `siteId` and the timestamps are not patchable), MUST stamp `updatedAt`, MUST return updated row or null.
- **delete-endpoint**: MUST accept `id` and remove the row only; it does not purge the endpoint's history or resolve its issues (`retireEndpoint` does).
- **purge-endpoint-history**: MUST accept array of endpoint ids, MUST delete all `health_checks` and `metrics_hourly` rows for those ids and MUST resolve (not delete) every still-open issue targeting those ids with reason 'unmonitored'; already-resolved issues keep their original `resolvedAt`. It is a no-op on an empty list. The three statements run sequentially, not in one transaction.
- **list-active-endpoints**: MUST return only `ConfiguredEndpoint` rows with `isActive: true`, flattened with site and group names via an inner join (an endpoint whose site or group is gone is dropped); each row's `slug` is the endpoint's row id, and a null `ignoreProjectWarning` reads as false.
- **reconcile-orphaned-endpoints**: MUST delete endpoints not owned by a configured site (a site joined to an existing group) and sites whose group is gone, and MUST return `{ endpoints: number, sites: number, prunedEndpointIds: string[] }` counted from the rows actually deleted. It MUST do nothing (return zero counts) when no orphans exist or when there are zero configured sites. A failure during the deletes is logged with `console.error` and the counts gathered so far are returned rather than thrown.
- **retire-endpoint**: MUST delete the endpoint, purge its history, then delete its parent site if and only if the site has no endpoints left (one conditional delete on fresh state), and MUST return `{ endpointDeleted: boolean, siteDeleted: boolean }`; an unknown id returns both false. The statements are not one transaction; the endpoint row is deleted first so a later failure leaves only orphaned history for the reconcile and retention prune to clean.
- **list-integrations**: MUST return all `IntegrationRow` objects.
- **create-integration**: MUST accept `{ platform, label, config?, tokenEnvVar?, secretRef?, isActive? }`, MUST return persisted `IntegrationRow`.
- **update-integration**: MUST accept `id` and partial patch, MUST return updated row or null.
- **delete-integration**: MUST accept `id` and remove the row. When the deleted row was the last active integration speaking for its platform-health source, the adapter also sets that source's `platform_health_state.configured` to false in the same `db.batch`, without touching `updatedAt`.
- **list-ignored-projects**: MUST return all `IgnoredProject` entries (platform, projectName); a missing table (error text matching no such table / does not exist / not found) reads as an empty list, and any other error is rethrown.
- **add-ignored-project**: MUST accept `platform` and `projectName`, MUST persist the entry; an existing entry is left as is (insert-or-ignore).
- **add-ignored-projects**: MUST accept array of `IgnoredProject` entries and persist all in one insert-or-ignore statement; a no-op on an empty array.
- **remove-ignored-project**: MUST accept `platform` and `projectName`, MUST remove the matching entry.
- **list-peers**: MUST return all `PeerRow` objects.
- **create-peer**: MUST accept `{ label, baseUrl, token?, isActive? }`, MUST store `baseUrl` normalized through `normalizePeerBaseUrl`, MUST return persisted `PeerRow`.
- **update-peer**: MUST accept `id` and partial patch (a supplied `baseUrl` is normalized through `normalizePeerBaseUrl`), MUST return updated row or null.
- **delete-peer**: MUST accept `id` and remove the row.

### Auth Store

- **find-user-by-email**: MUST accept an email string, MUST lowercase it before the lookup, MUST return `UserRecord` if found or undefined.
- **find-user-by-github-id**: MUST accept a GitHub id string, MUST return `UserRecord` if found or undefined.
- **get-user-by-id**: MUST accept a user id, MUST return `UserRecord` if found or undefined.
- **create-user**: MUST accept `{ email, displayName, role, passwordHash?, githubId? }`, MUST store the email lowercased, MUST return persisted `UserRecord` with server-generated `id`, `createdAt`. Role is typed as `UserRole` ('pending', 'viewer', 'admin'). A duplicate email or GitHub id raises the driver's unique-index error, which `isUniqueViolation` recognizes.
- **attach-github-id**: MUST accept `userId` and `githubId`, MUST return updated `UserRecord` or undefined if no such user.
- **list-users**: MUST return all users mapped to public `AuthUser` (no password hash).
- **set-user-role-guarded**: MUST accept `id` and new `role`, MUST atomically prevent demotion of the last admin, MUST return updated `AuthUser` or 'blocked' or undefined.
- **delete-user-guarded**: MUST accept `id`, MUST atomically prevent deletion of the last admin, MUST delete that user's sessions only after the guarded delete succeeded, MUST return true on success, 'blocked' if last admin, or false if no such user.
- **count-admins**: MUST return the number of users with role 'admin'.
- **create-session**: MUST accept `userId` and optional `ttlMs` (time-to-live milliseconds, default 30 days in the adapter), MUST return the raw opaque cookie token (32 random bytes as hex), MUST persist only its SHA256 hash.
- **resolve-session**: MUST accept an optional token string, MUST return the live `AuthUser` if valid and not expired, or null if the token is undefined/empty, unknown, expired, or its user no longer exists; an expired session row is deleted when encountered.
- **revoke-session**: MUST accept an optional token, MUST delete the session row so `resolveSession` returns null thereafter; a no-op on an undefined or empty token.

### Token Store

- **mint-api-token**: MUST accept `{ name, role, kind?, createdBy, expiresAt? }` where `role` is 'admin' or 'user' and `kind` is 'minted' or 'device', MUST return `{ meta: ApiTokenMeta, raw: string }` with the raw value shown exactly once; MUST persist only the SHA256 hash. Raw value MUST be `TOKEN_PREFIX` ('sts_') followed by 32 random bytes as hex; the first `PREFIX_LEN` (12) characters are stored as the display `prefix`; `kind` defaults to 'minted' and `expiresAt` to null.
- **validate-api-token**: MUST accept raw bearer token string, MUST return null without a lookup when it does not start with `TOKEN_PREFIX`, MUST return `TokenPrincipal` if found, not revoked, and not expired (`expiresAt` at or before now counts as expired), MUST bump `lastUsedAt` on success, MUST return null on validation failure.
- **list-api-tokens**: MUST return all `ApiTokenMeta` entries, newest first (no raw values or hashes).
- **revoke-api-token**: MUST accept token `id`, MUST soft-revoke by setting `revokedAt`, MUST return false if no such token; re-revoking an already-revoked token returns true and restamps `revokedAt`.
- **delete-api-token**: MUST accept token `id`, MUST hard-delete the row, MUST return false if no such token.

### Health Store

- **latest-checks**: MUST accept array of endpoint slugs, MUST return the most recent `LatestCheckRow` per slug (with `checked_at` in epoch SECONDS, `dns_ok` as 0 or 1).
- **bad-run-onsets**: MUST accept array of slugs, MUST return one `BadRunOnsetRow` per slug that has a current unbroken bad run, `since` being the epoch-SECONDS timestamp of the oldest check newer than the slug's last healthy check (a slug never healthy starts at its first check). A slug with no bad run, or no checks, contributes no row.
- **record-checks**: MUST accept array of `HealthCheckInput` objects, MUST persist each as one `health_checks` row; a no-op on an empty array.
- **checks-summary**: MUST return `{ samples: number, services: number }` — total checks recorded and distinct services ever checked.
- **last-checked-at-ms**: MUST return epoch milliseconds of the most recent check's `checked_at`, or null if no checks exist.

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

### Pure Helpers

- **redact-peer**: `redactPeer(peer)` MUST return the peer without `token` plus `hasToken`, true only when `token` is a non-empty string.
- **is-unique-violation**: `isUniqueViolation(err)` MUST walk the Error `.cause` chain and return true when any message matches UNIQUE constraint failed (case-insensitive); a non-Error returns false.
- **to-auth-user**: `toAuthUser(record)` MUST project `UserRecord` to `{ id, email, displayName, role }`, dropping `passwordHash`, `githubId` and `createdAt`; an unknown role string coerces to 'pending' (fail safe).
- **role-for-email**: `roleForEmail(email, config)` MUST return 'admin' when the lowercased email is in `config.adminEmails`, else 'pending'.
- **token-constants**: `TOKEN_PREFIX` MUST be 'sts_' and `PREFIX_LEN` MUST be 12.

### Telemetry Store

- **errors**: MUST be a `Store<ErrorDTO>` for persisted GlitchTip error streams.
- **analytics**: MUST be a `Store<AnalyticsMetricDTO>` for persisted PostHog analytics streams.

## Appearance

Not applicable — this is a storage interface, not a visual component.

## States

Not applicable — this is a storage interface with no visual states.

## Accessibility

Not applicable — this is a storage interface, not a visual component.

## Conformance Test Vectors

| ID | Requirement | Input | Expected Output | Notes |
|----|-------------|-------|-----------------|-------|
| storage-001 | list-site-groups | (none) | Array of all GroupRow entries, possibly empty | empty array when no groups created |
| storage-002 | create-group | `{ name: "Production", slug: "prod" }` | GroupRow with generated id, createdAt, updatedAt | slug and name persisted verbatim |
| storage-003 | create-endpoint | `{ siteId: "site1", url: "https://example.com", expectedStatus: 200 }` | EndpointRow with all fields, defaults applied to omitted optional fields | isActive defaults to true |
| storage-004 | list-active-endpoints | (none) | ConfiguredEndpoint[] with only isActive: true rows, flattened with group and site names | empty if no active endpoints |
| storage-005 | find-user-by-email | email string "User@Example.com" | UserRecord stored as "user@example.com" if exists, undefined if not | input lowercased before lookup; createUser stores lowercased |
| storage-006 | create-user | `{ email: "new@example.com", displayName: "New User", role: "pending" }` | UserRecord with generated id and createdAt | role is typed UserRole |
| storage-007 | mint-api-token | `{ name: "CLI", role: "user", createdBy: "admin1" }` | `{ meta: ApiTokenMeta, raw: string }` where raw starts with "sts_" | raw shown exactly once; hash only persisted |
| storage-008 | validate-api-token | valid raw token string | TokenPrincipal with id, name, role, expiresAt | lastUsedAt is bumped on success |
| storage-009 | validate-api-token | revoked or expired token | null | does not throw; returns null |
| storage-010 | record-checks | `[{ serviceSlug: "api", status: "up", responseTimeMs: 150, statusCode: 200, ... }]` | (void) | health_checks row persisted |
| storage-011 | latest-checks | `["api", "web"]` | LatestCheckRow[] with most recent per slug | checked_at in epoch SECONDS |
| storage-012 | upsert-deployments | `[{ id: "d1", platform: "vercel", projectName: "proj", deployPhase: "building", ... }]` | (void) | deployment row upserted by id |
| storage-013 | list-open | (none) | IssueRow[] sorted oldest-first by openedAt then id | empty if no open issues |
| storage-014 | insert-issue | IssueInsert for a target that already has an open issue | (void), no new row | insert-or-ignore on the one-open-issue-per-target index |
| storage-015 | purge-endpoint-history | `["endpoint1"]` | (void) | health_checks and metrics_hourly deleted; open issues resolved as unmonitored |
| storage-016 | role-for-email | "BOSS@example.com" with the admin in ADMIN_EMAILS | 'admin' | from auth-store.int.test.ts |
| storage-017 | role-for-email | "rando@x.com" | 'pending' | from auth-store.int.test.ts |
| storage-018 | redact-peer | `{ id: "p1", token: "" }` | `{ id: "p1", hasToken: false }` | empty string counts as no token |
| storage-019 | is-unique-violation | Error whose `.cause` message is "UNIQUE constraint failed: users.email" | true | walks the cause chain |
| storage-020 | delete-user-guarded | unknown id | false | not undefined |

## Edge Cases

- **Null or empty inputs**: Empty array inputs (list-active-endpoints with no active endpoints, record-observations with empty array, record-vercel-prod-states) MUST return empty result or be a no-op without error.
- **Nonexistent ids**: update methods return null, find/get user methods return undefined, delete methods returning void do nothing, `deleteUserGuarded`/`revokeApiToken`/`deleteApiToken` return false, and `retireEndpoint` returns both flags false — none throw.
- **Concurrent writes to same row**: Database schema enforces uniqueness (e.g., the partial unique index allowing one open issue per target). The adapter's own transaction handling governs atomicity; this interface does not expose transaction objects. Clients MUST NOT assume any ordering of concurrent writes.
- **Expired sessions and tokens**: resolveSession and validateApiToken with expired credentials MUST return null (not throw).
- **Last admin protection**: setUserRoleGuarded demoting the last admin and deleteUserGuarded deleting the last admin MUST return 'blocked' and MUST not proceed.
- **Cascading deletes**: deleteGroup and deleteSite cascade in application code and purge endpoint history; deleteEndpoint deletes only its own row; deleteUserGuarded deletes that user's sessions after the guarded delete succeeds.
- **Missing deploy project on endpoint**: An endpoint with a wired deployProject but no corresponding deploy row is a valid state; the adapter makes no automatic backfill.
- **Webhook regression guard**: upsertDeployments from 'webhook' source MUST never roll back phases; see libsql implementation for COALESCE details.
- **Pagination with stalled cursor**: a `PageCursor` with `strict: true` (the empty-id sentinel a stalled page mints) reads strictly before `beforeMs`, an ordinary cursor reads at-or-before it; when a page's LIMIT cuts through a group of rows sharing one timestamp, the page readers re-read that tie group in full, and `floorMs` is null when the page exhausted the source.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| db connection url | string | (required) | libSQL connection string held by the adapter; only `SnapshotOptions.dbUrl` (tests) overrides it |
| session TTL | number (ms) | 30 days | `createSession` default when `ttlMs` is omitted |
| `TOKEN_PREFIX` | string | 'sts_' | Prefix of every raw API token |
| `PREFIX_LEN` | number | 12 | Leading characters stored as the token display prefix |
| admin emails | string[] | from ADMIN_EMAILS | `StatusConfig.adminEmails`; `roleForEmail` makes a matching email 'admin' on first account |

## Deep Linking

Not applicable — this is a storage interface, not a user-facing route or component.

## Localization

Not applicable — this interface defines no user-facing strings. Error messages and labels are generated by consuming routes and the board.

## Accessibility Options

Not applicable — this is a storage interface with no user-facing display.

## Feature Flags

Not applicable — this interface defines no feature flags.

## Analytics

Not applicable — this interface does not emit analytics events.

## Privacy

- **Sensitive fields**: `UserRecord.passwordHash` (never read back to clients), `PeerRow.token` (redacted by `redactPeer` helper; MUST NOT leave the process), `ApiTokenMeta` (never includes hash or raw value), the `raw` value returned by `mintApiToken` (shown to caller exactly once), and `DeviceGrantRow` (omits `deviceCodeHash`, `userCodeHash`, `tokenRaw`).
- **Token storage**: Session tokens and API tokens are persisted as SHA256 hashes only. The one exception is a device grant: `approve` stashes the minted token's raw value (`tokenRaw`) on the grant row until `consumeApproved` deletes it.
- **Credential redaction**: The `redactPeer` helper projects `PeerRow` to omit `token` and add `hasToken: boolean`; per its doc comment, whether a token is set is all any read surface (REST GET/POST/PATCH, MCP `list_peers`/`add_peer`) may know.

## Logging

`ports.ts` itself emits no logs. The libSQL adapter logs with `console.error` in two places: a failed `reconcileOrphanedEndpoints` delete, and a deploy dropped by `upsertDeployments` for an invalid `createdAt`.

## Platform Notes

- **TypeScript/Web (libSQL)**: Storage is implemented via `createLibsqlStorage` in `../libsql/stores/`. It is the sole adapter permitted to speak to the libSQL driver and to query objects. Types like `GroupRow`, `UserRecord`, `DeploymentRow` are domain types that never reference the driver, connection handle, or generated row-inference aliases. Schema enforcement, unique-index guards, and retention pruning are adapter responsibilities. The adapter does not use `db.transaction` (unavailable over the HTTP connection mode); multi-statement operations rely on statement order or `db.batch`, and the last-admin and device-approve guards live inside single conditional statements. WAL checkpointing happens inside `runMaintenance` and is not exposed by this interface.
- **Swift**: Not implemented in source; this component is web-only (status-server is Node.js/libSQL).
- **Kotlin**: Not implemented in source; this component is web-only.
- **C#/WinUI 3**: Not implemented in source. Port via Windows App SDK `HttpClient` for any peer polling, `System.Text.Json` for serialization, `Windows.Storage` for local snapshots (if needed), `ObservableCollection` and `INotifyPropertyChanged` for reactive stores if binding to UI (not required by this interface). Use SqlClient or Entity Framework Core for SQL Server or SQLite; map domain types onto EF entities; expose stores as properties/methods on a composed class. Unlike libSQL's schema-as-contract approach, EF migrations govern schema change; ensure all domain-type fields have corresponding columns.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/storage/ports.ts` |

## Design Decisions

**Decision**: Stores are named for the concern the existing code expresses (Config, Auth, Token, Health, etc.) rather than an invented grouping.

**Rationale**: Each store is a discrete concern with its own contract; naming by concern makes the interface self-documenting and helps porting teams map their own persistence layer.

**Approved**: pending

---

**Decision**: Token and session storage is hash-only; raw values are shown to callers exactly once and never persisted, except the device grant's `tokenRaw`, held on the grant row only until the single-use consume.

**Rationale**: Hashing by default prevents accidental logging or leakage of secrets in error messages, logs, or database dumps. The caller is responsible for storing the raw value (e.g., as an Authorization header) immediately after mint.

**Approved**: pending

---

**Decision**: Page readers (readDeployActivityPage, readIssueOpenedPage) return `SourcePage<T>` with `floorMs` to handle pagination boundaries that cross multiple rows with the same timestamp.

**Rationale**: A LIMIT cut may split a tie group; the reader re-reads that group in full so a partial instant is never returned, and `floorMs` (null when the source is exhausted) informs the next cursor. This is a storage concern, not a caller concern.

**Approved**: pending

---

**Decision**: Last-admin protection is atomic; setUserRoleGuarded and deleteUserGuarded return 'blocked' rather than throwing.

**Rationale**: Race-free protection without requiring callers to catch exceptions; the return value signals the guard was hit.

**Approved**: pending

---

**Decision**: ConfiguredEndpoint is a flattened type combining endpoint, site, and group data; callers do not reconstruct it.

**Rationale**: Probes and the /api/live endpoint read this shape; the adapter performs the endpoint-site-group inner join once in `listActiveEndpoints`, so no caller repeats it.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |

**Separation of Concerns**: The interface defines only the data contract and operation signatures; implementation is isolated in the libSQL adapter. Consumers depend only on these types and method contracts, never on driver details or schema.

**Unit Test Coverage**: The adapter and helpers are exercised by the package's `test/` suite (for example `auth-store.int.test.ts` covers `roleForEmail`, `last-admin-guard.int.test.ts`, `api-tokens.int.test.ts`, `device-flow.int.test.ts`, `config-store.test.ts`, `deploy-upsert-guard.test.ts`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Claude Haiku 4.5 | Initial creation from ports.ts |
