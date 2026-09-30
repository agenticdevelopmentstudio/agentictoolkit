<!-- leaf: implement-general-1/adh-offline-sync-client--edge-cases · source: adh-offline-sync-client.md -->

# ADH Offline Sync Client

## Edge Cases

- **Fresh-cursor initial sync — no resync.** On a cold store the cursor is nil,
  so the first pull covers every effective resource with no gap; appearances on
  a nil cursor are *not* treated as a resync (they cannot be behind a cursor
  that does not exist yet). Verified by
  `SyncEngineTests.testFreshCursorInitialSyncDoesNotResync`.
- **Manifest flapping bound.** A manifest that flaps a resource in and out (or
  keeps bumping its schema version) faster than a resync can settle is bounded:
  after `maxReconcileResyncsPerCycle` (3) mirror resets in one cycle the engine
  surfaces `SyncEngineError.manifestUnstable` (a `.failed` event) and backs off,
  rather than hot-looping reset + re-pull forever. Verified by
  `SyncEngineTests.testFlappingManifestTripsReconcileResyncBoundAndFails`.
- **Conflict without `current`.** A `conflict` result carrying no `current` row
  has nothing to adopt; it is treated as a rejection — the op is quarantined
  (reason preserved), never silently dropped. Verified by
  `SyncEngineTests.testConflictWithoutCurrentIsQuarantinedNotSilentlyDropped`.
- **Unparseable server `sync_version` ⇒ terminal quarantine.** A conflict whose
  `current.sync_version` cannot yield a numeric version — a non-finite or
  out-of-`Int64`-range number, OR a non-numeric string (the conflict `current`
  is `z.unknown()` on the wire, so it is NOT schema-validated to `/^\d+$/`) — is
  unadoptable: the server row can't be mirrored. The op is routed to the SAME
  terminal quarantine path as an explicit `rejected` (never retried under its
  original opId; a fixed retry must re-`stage` for a fresh one), and the rest of
  the push batch still `complete`s so the loop makes progress. This replaces the
  earlier "skip adoption but resolve" behavior, under which a non-numeric string
  was handed to `apply` verbatim, threw before `complete()`, and re-pushed the
  op forever. Verified by
  `SyncEngineTests.testConflictWithUnrepresentableSyncVersionQuarantines` (number)
  and `testConflictWithNonNumericStringSyncVersionQuarantinesWithoutWedging`
  (string, plus a sibling op that still completes).
- **Re-enable after disable.** A resource disabled and later re-enabled comes
  back through the appearance rule (full resync on a non-fresh cursor), not as a
  silent resumption — its rows changed while it was outside the effective set
  and are behind the single cursor stream.
- **Enrollment disable racing an in-flight push.** If enrollment for a resource
  is disabled while a push for it is outstanding, the server answers that op with
  `rejected/not_enrolled`; the client quarantines it — the same terminal
  quarantine state the local disable transition (`disappearance-quarantines-outbox`)
  would have produced. The op is never pushed under a stale enrollment.
