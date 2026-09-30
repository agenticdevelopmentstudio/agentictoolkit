<!-- leaf: implement-sync-engine/sync-grdb · source: sync-engine-sync-grdb.md -->

# GRDBSyncStore

## Overview

`GRDBSyncStore` is the durable implementation of the `SyncStore` protocol that `SyncEngine` drives (see SyncEngine). It sits on a `BoundedDatabase` (a GRDB WAL pool with per-operation deadlines) and keeps four bookkeeping tables plus one mirror table per registered resource:

- `_sync_state` — the single-row pull cursor.
- `_sync_resources` — the registered resource names and their schema versions.
- `_sync_outbox` — local mutations owed to the server, each `pending`, `inflight` or `quarantined`.
- `_sync_conflicts` — an append-only audit of conflicted pushes.
- one mirror table per resource — `(id, sync_version, deleted_at, data)` with the row's fields stored as a JSON blob in `data`.

An optional `SyncMirrorProjection` can claim a subset of resources and store them in typed tables instead of the JSON mirror; every mirror-touching operation asks the projection first and falls through to the JSON mirror for unclaimed resources.

Use it when a host needs the offline mirror and outbox to survive restarts. Beyond the `SyncStore` contract it offers synchronous read helpers (`liveRows`, `liveRow`, `registeredResources`, `status`) for a daemon or UI, and transaction-joining overloads (`prepare(resources:in:)`, `stage(_:in:)`) for a store layered on top of it.

