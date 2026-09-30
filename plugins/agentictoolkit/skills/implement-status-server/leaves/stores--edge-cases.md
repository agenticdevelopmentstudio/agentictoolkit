<!-- leaf: implement-status-server/stores--edge-cases · source: status-server-stores.md -->

# Status Server Stores

**Rules** (cite as `implement-status-server/stores--edge-cases#<slug>`):

- `null-and-empty-input` MUST — recordChecks([]), resolveUnmonitoredTargets([]), deleteProjectMeta(platform, []), and errorsStore.save([]) (with …

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
