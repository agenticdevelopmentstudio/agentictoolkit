<!-- leaf: implement-sync-engine/testing · source: sync-engine-testing.md -->

# Sync Engine Testing

## Overview

Sync Engine Testing is the pair of reference fakes that ship inside the
`AgenticToolkitSync` framework (the toolkit convention, per the source comment:
"fakes ship in the framework"), under `Sync/Testing/`:

- `InMemorySyncStore` — an `actor` conforming to `SyncStore` that keeps
  per-resource mirror rows, a cursor, an outbox, a conflict log and a
  quarantine list in memory. Its doc comments state that it mirrors
  `GRDBSyncStore` for registration, atomic apply, outbox coalescing, inflight
  replay, `newVersion` adoption and purge, "so the fakes don't lie" about the
  real store's behavior. It also exposes test conveniences (`rowCount`, `row`,
  `pendingOpId`).
- `ScriptedSyncTransport` — an `actor` conforming to `SyncTransport` that
  returns queued pull and push outcomes in FIFO order, records every request,
  and falls back to an empty pull or an all-applied push when its script is
  empty.
- `SyncStoreFailure` — the error enum both stores throw
  (`unknownResource`, `invalidChange`, `pullOnlyResource`).

Use them to drive SyncEngine in unit
tests and previews without SQLite or a network, and as the executable
specification a port's own store and transport fakes are checked against.

