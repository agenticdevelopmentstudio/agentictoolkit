<!-- leaf: implement-sync-engine/database · source: sync-engine-database.md -->

# Sync Engine Database

## Overview

The `AgenticToolkitDatabase` module is the storage floor the sync stack and
the app's other stores sit on. It has two parts:

- `BoundedDatabase` wraps a GRDB `DatabasePool` (or a serial `DatabaseQueue`
  for `:memory:`) with two guarantees so a runaway query can never wedge the
  process: a **bulkhead** (one writer plus N readers on WAL, so reads never
  queue behind the writer) and **ejection** (every `read`/`write` carries a
  monotonic deadline; a SQLite progress handler aborts any statement that
  passes it, surfaced as `BoundedDatabaseError.deadlineExceeded`). It keeps
  per-lane latency and eviction counters exposed as `stats`, and it is
  reentrant, so a code base can keep one `read`/`write` chokepoint instead of
  threading a `Database` handle everywhere.
- `AppStorageLocation` derives where an app keeps its files — a dotfolder in
  the home directory — from the bundle's display name, reduced to characters a
  path can hold.

Consumers include `GRDBSyncStore` (see
ADH Offline Sync Client),
`MarkdownStore` (see Markdown Core),
and `ProjectDatabase` (see
Project Database),
which names its file inside `AppStorageLocation.directory`.

