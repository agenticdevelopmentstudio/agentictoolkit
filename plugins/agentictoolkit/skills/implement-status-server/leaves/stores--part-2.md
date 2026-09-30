<!-- leaf: implement-status-server/stores--part-2 · source: status-server-stores.md -->

# Status Server Stores — continued (part 2)

**Rules** (cite as `implement-status-server/stores--part-2#<slug>`):

- `storage-composition` MUST
- `connection-descriptor-scoping` MUST
- `user-lookup` MUST
- `create-user-defaults` MUST
- `role-listing-shape` MUST
- `last-admin-guard-update` MUST
- `last-admin-guard-delete` MUST
- `admin-count` MUST
- `session-lifecycle` MUST
- `mint-hash-only` MUST
- `validate-by-hash` MUST
- `token-listing-shape` MUST
- `revoke-vs-delete` MUST
- `hash-only-persistence` MUST
- `purge-expired` MUST
- `approve-status-guard` MUST
- `deny-status-guard` MUST
- `single-use-consume` MUST
- `mark-polled` MUST
- `role-and-expiry-lookup` MUST
- `latest-checks-batch` MUST
- `bad-run-onsets` MUST
- `record-checks-bulk` MUST
- `checks-summary` MUST
- `last-checked-at` MUST
- `newest-check-at` MUST
- `checks-for-window` MUST
- `daily-counts` MUST
- `response-buckets` MUST
- `list-open` MUST
- `insert-issue` MUST
- `update-issue` MUST
- `resolve-with-reason` MUST
- `bulk-resolve-unmonitored` MUST
- `streak-debounced-recording` MUST
- `vercel-staleness-upsert` MUST
- `tolerate-unmigrated-table` MUST

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

