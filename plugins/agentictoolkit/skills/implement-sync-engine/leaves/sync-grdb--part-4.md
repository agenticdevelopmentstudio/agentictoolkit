<!-- leaf: implement-sync-engine/sync-grdb--part-4 · source: sync-engine-sync-grdb.md -->

# GRDBSyncStore — continued (part 4)

## Platform Notes

- **SwiftUI**: Source platform (`SyncGRDB/GRDBSyncStore.swift`, `SyncGRDB/SyncMirrorProjection.swift`). The store uses GRDB (`Database`, `Row`, `StatementArguments`) through `BoundedDatabase`, a private serial `DispatchQueue` bridged to async with `withCheckedThrowingContinuation`, `JSONEncoder`/`JSONDecoder` built per call, and `SyncID.uuidV7()` for op ids. A SwiftUI host reads `liveRows` or `status()` from a model refreshed on `SyncEngine` events; GRDB's `ValueObservation` on the mirror table is the natural live-update source.
- **Compose**: Start from Room or SQLDelight on the Android SQLite driver with WAL enabled (`enableWriteAheadLogging`). Run async operations on `Dispatchers.IO.limitedParallelism(1)` inside `withTransaction`/`transaction {}`; keep the table-name allow-list check because Room's `@RawQuery` and SQLDelight dynamic SQL also cannot bind identifiers. Store `data` as a `kotlinx.serialization` `JsonObject` string; port `SyncMirrorProjection` as an interface taking a `SupportSQLiteDatabase`.
- **React/Web**: Start from IndexedDB (via `idb`) or SQLite-WASM (`@sqlite.org/sqlite-wasm` with OPFS). IndexedDB replaces tables with object stores — one per resource plus `outbox`, `state`, `resources`, `conflicts` — and a single `readwrite` transaction over all touched stores gives the same atomicity; `rowid` order becomes an auto-increment key. JS is single-threaded, so the serial queue becomes a promise chain; there are no identifiers to inject with IndexedDB, but a SQLite-WASM port keeps the allow-list.
- **AppKit / UIKit**: The same Swift sources apply unchanged; the target depends only on Foundation, GRDB and the toolkit's `Database` and `Sync` modules. Place the database file under Application Support and, on iOS, set `FileProtectionType.completeUntilFirstUserAuthentication` so a background sync can open it.
- **WinUI 3**: Start from `Microsoft.Data.Sqlite` with `PRAGMA journal_mode=WAL`, one writer `SqliteConnection` plus pooled readers, and the file under `Windows.Storage.ApplicationData.Current.LocalFolder`. Serialise async operations with a `SemaphoreSlim(1, 1)` and run each inside `connection.BeginTransaction()`, exposing `Task`-returning `async` methods; the synchronous read helpers use their own reader connection. `System.Text.Json` `JsonObject`/`JsonNode` replaces `[String: JSONValue]` for `data` and payloads; `JsonSerializer.Serialize` replaces the per-call encoder (`JsonSerializerOptions` is thread-safe once frozen, so sharing one is fine in .NET). `SqliteCommand` parameters cannot bind table names either, so keep the lowercase/digit/underscore/period allow-list before interpolating. Op ids need a monotonic UUIDv7 port (`Guid.CreateVersion7()` lacks same-millisecond ordering). Cancellation differs: .NET APIs take a `CancellationToken`, and passing one would let a queued operation abort, which the source never does. A UI observing `status()` marshals updates through `DispatcherQueue.TryEnqueue` into an `INotifyPropertyChanged` view model; mirror rows for a list bind through `ObservableCollection<T>`.

## Design Decisions

### Coalesce into a pending op, never an inflight one

**Decision**: A second local edit to a row with a `pending` op updates that op in place, keeping its `op_id` and original `base_version`; an `inflight` op is never modified.

**Rationale**: The `stage` doc comment (sync fix-wave item p2a) records that two ops with the same base version make the server apply the first and stale-conflict the second, silently dropping the newer edit. An inflight op may already be at the server, and its replay under the same `op_id` must carry the same content.

**Approved**: pending

### Strict parsing on pull, lenient on completion

**Decision**: An unparseable `syncVersion` in `apply` throws `invalidChange`, but an unparseable `newVersion` in `complete` is skipped silently while the outbox row is still deleted.

**Rationale**: The source comments explain that coercing to 0 would corrupt version ordering, so `apply` fails loudly; but throwing inside `complete` would roll back the outbox deletion and wedge the op on replay even though the server already applied it.

**Approved**: pending

### Inflight ops are replayed until completed

**Decision**: `pendingOps` returns `inflight` ops again on every call.

**Rationale**: The `pendingOps` doc comment states that replaying the same opIds after a crash or an unfinished round-trip is covered by the server contract's idempotency guarantee, so re-sending is safe and nothing is stranded.

**Approved**: pending

### Identity change clears the outbox; resync does not

**Decision**: `resetForResync` keeps every outbox op; `purgeForIdentityChange` deletes all of them, including quarantined ones, and asks the projection to drop its local-only state.

**Rationale**: The `purgeForIdentityChange` doc comment explains that a resync keeps the same identity, which still owes the server its queued edits, while pushing a departing identity's ops under new credentials would misattribute them; `MarkdownProjection`'s sidecar outbox is the cited case for `purgeIdentityState`.

**Approved**: pending

### Registrations and the conflict audit survive every purge

**Decision**: No purge path deletes `_sync_conflicts`, and only `purgeResources` deletes registrations.

**Rationale**: The doc comments call registrations app-level rather than per-identity state (so the next identity need not re-`prepare`), and call the conflict audit a historical record never read back into a sync decision.

**Approved**: pending

### Offset pagination on the mirror

**Decision**: `liveRows` pages with `LIMIT`/`OFFSET` ordered by `id`.

**Rationale**: The `liveRows` doc comment says the mirror shadows the backend's own offset/limit REST contract because the daemon is a transparent proxy; the `O(offset)` cost is bounded by callers capping `limit` (`MirrorServer`'s `listLimit`, 200).

**Approved**: pending

### Projections see a whole purge batch at once

**Decision**: Every truncation hands all claimed resources to `truncate(resources:in:)` in one call.

**Rationale**: The `deleteMirrorRows` comment explains that a projection with foreign keys between its own tables can only tell a legal whole-family purge from an orphaning partial one by seeing the whole batch.

**Approved**: pending

### SyncMirrorProjection

**Decision**: Typed storage is opt-in per resource through a projection, and the `isFullRow:` and `purgeIdentityState` requirements have defaults.

**Rationale**: The protocol doc says the JSON mirror survives schema evolution without migrations and is the right default, while indexed or foreign-keyed local storage needs real columns; the defaults keep projections written before those requirements existed source-compatible.

**Approved**: pending
