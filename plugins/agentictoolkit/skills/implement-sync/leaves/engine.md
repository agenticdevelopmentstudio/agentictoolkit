<!-- leaf: implement-sync/engine · source: sync-engine.md -->

# SyncEngine

## Overview

`SyncEngine` is the client half of an offline-first sync protocol: a Swift
`actor` that runs one *cycle* at a time — pull every page of server changes
into a local mirror, reconcile the server's resource manifest against what the
host has registered, then drain the local outbox to the server and adopt the
server's row on every conflict. It owns no storage, no network code and no
credentials: persistence is injected as a `SyncStore`, the wire as a
`SyncTransport`, and wake-ups as `SyncTriggerSource`s. Progress is reported
only through the `events` stream of `SyncEvent` values.

The recipe also covers the value types the engine's contract is written in:
the wire shapes in `SyncWire.swift` (`SyncCursor`, `SyncResource`,
`SyncChange`, `SyncPullResponse`, `SyncPushOp`, `SyncPushRequest`,
`SyncPushResult`, `SyncPushResponse`), the schema-flexible payload `JSONValue`,
the UUIDv7 generator `SyncID`, and the generated resource list
`ADHSyncCatalog`. The adh-specific enrollment and backend rules the engine
serves are specified in
ADH Offline Sync Client.

Use it when a host (an app or a daemon) keeps a local mirror of server rows,
lets the user edit offline, and needs those edits pushed later without ever
being lost.

