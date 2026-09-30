<!-- leaf: implement-status-server/stores--logging · source: status-server-stores.md -->

# Status Server Stores

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
