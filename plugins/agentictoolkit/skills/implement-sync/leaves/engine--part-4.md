<!-- leaf: implement-sync/engine--part-4 · source: sync-engine.md -->

# SyncEngine — continued (part 4)

## Platform Notes

- **SwiftUI**: Source platform (`Sync/SyncEngine.swift`, `SyncEvents.swift`, `SyncProtocols.swift`, `SyncWire.swift`, `JSONValue.swift`, `SyncID.swift`, `ADHSyncCatalog.swift`). The engine is an `actor` using `CheckedContinuation` for waiters, `AsyncStream.makeStream(of:bufferingPolicy: .bufferingNewest(256))` for events, `Task.sleep(for:)` for backoff, and `Codable` for wire types. A SwiftUI host consumes `events` in a `.task` modifier and mirrors state into an `@Observable` model; `NSLock` plus `nonisolated(unsafe)` statics keep `SyncID.uuidV7` synchronous.
- **Compose**: Port the actor to a class whose methods run under a `Mutex` or a single-threaded `CoroutineDispatcher` (`limitedParallelism(1)`); note that coroutines, like Swift actors, interleave at suspension points. Events become a `MutableSharedFlow<SyncEvent>(extraBufferCapacity = 256, onBufferOverflow = DROP_OLDEST)`; waiters become `CompletableDeferred<Unit>`; backoff is `delay()` in a `Job` cancelled on reschedule; wire types use `kotlinx.serialization` with a `JsonElement` in place of `JSONValue`. `java.util.UUID` has no v7 generator, so port `SyncID` by hand.
- **React/Web**: Single-threaded JS gives the one-cycle-at-a-time rule for free between `await`s but not across them, so keep the explicit `running` flag and a promise-based waiter list. Events map to an `EventTarget` or a bounded array-backed emitter; backoff is `setTimeout` with `clearTimeout` on reschedule; `JSONValue` is plain `unknown` JSON, and numbers are IEEE doubles as in the source. Persistence would sit on IndexedDB behind the `SyncStore` interface; `fetch` implements `SyncTransport`.
- **AppKit / UIKit**: The same Swift sources apply unchanged (the target is Foundation-only and daemon-safe). A UIKit or AppKit host iterates `events` in a `Task` owned by its controller, calls `pause()` before a sign-out purge, and uses `BGTaskScheduler` (iOS) or a launchd timer (macOS daemon) as a `SyncTriggerSource` that yields `.periodic`.
- **WinUI 3**: Port the actor to a class that serialises cycles with a `SemaphoreSlim(1, 1)` or a dedicated single-threaded `TaskScheduler`; `await` interleaving means the `running`/`pendingReason` coalescing logic must be kept, not replaced by the lock. Waiters become `TaskCompletionSource` instances completed at cycle end; events become a `System.Threading.Channels.Channel<SyncEvent>` created with `BoundedChannelOptions(256) { FullMode = BoundedChannelFullMode.DropOldest }`, which the UI marshals to its thread through `DispatcherQueue.TryEnqueue` before updating an `INotifyPropertyChanged` view model or `ObservableCollection`. Backoff is `Task.Delay` with a `CancellationTokenSource` replaced on each reschedule. `HttpClient` implements `SyncTransport` (map `HttpStatusCode.Unauthorized` and `Gone` to the two special errors); `System.Text.Json` with `JsonNode`/`JsonElement` replaces `JSONValue` and wire `Codable`, with `JsonSerializerOptions` camelCase naming to match the Swift property names. The store would sit on SQLite (`Microsoft.Data.Sqlite`) under `Windows.Storage.ApplicationData.Current.LocalFolder`. `Guid.CreateVersion7()` (.NET 9) produces v7 ids but does not guarantee same-millisecond monotonic ordering, so port `SyncID`'s counter logic if ordering matters.

## Design Decisions

### Server manifest is authoritative and complete

**Decision**: Every pull page's manifest is treated as the full enrollment set; a registered resource missing from it is disabled on that page.

**Rationale**: The source comment (fix B1) states the client cannot distinguish "server dropped it" from "server forgot it", so omission is the signal and the server must send the full manifest every page.

**Approved**: pending

### Schema downgrade is a bump

**Decision**: `bumped` uses a not-equal comparison, so a lower manifest `schemaVersion` purges and resyncs exactly like a higher one.

**Rationale**: Per fix A2, mirror rows written under one schema cannot be trusted under another in either direction.

**Approved**: pending

### Unadoptable conflicts quarantine

**Decision**: A conflict with no `current`, or with a `sync_version` that cannot become an integer, is recorded as `.rejected` so the store quarantines it.

**Rationale**: Fixes p2-Minor9 and A3: the old behaviour either dropped the op silently or let `store.apply` throw before `complete`, re-pushing the op every cycle.

**Approved**: pending

### Bounded loops everywhere

**Decision**: Pull no-progress (2), reconcile resets per cycle (3), nested 410 resyncs (1 immediate) and push no-progress all convert a potential hot loop into a regular failure with backoff.

**Rationale**: Each guards a misbehaving or lagging server (the source cites a cohort stall guard and a moving GC horizon); failing into backoff keeps the outbox intact while giving the server time to catch up.

**Approved**: pending

### Joining `syncNow` waits; `kick` does not

**Decision**: A `syncNow` that coalesces into a running cycle suspends until that cycle ends, while `kick` returns at once.

**Rationale**: The doc comment makes `syncNow` an honest "a sync just ran" signal for pull-to-refresh spinners and background-task completion handlers.

**Approved**: pending

### Pause buffers nothing

**Decision**: Kicks during `pause()` are dropped and a pending reason is cleared when a cycle ends paused; `resume()` does not sync.

**Rationale**: `pause()` exists for identity-boundary operations such as a sign-out purge; resurrecting a reason queued before the purge would sync the wrong identity's state.

**Approved**: pending

### Event buffer of 256 newest

**Decision**: `events` buffers the newest 256 events instead of an unbounded buffer.

**Rationale**: The init comment calls it a backstop against a host that never subscribes; both shipped hosts drain continuously, and the obligation to drain still stands.

**Approved**: pending

### Snapshot registrations once per cycle

**Decision**: Registrations are read once per cycle and `prepare` is skipped when the snapshot already covers the effective set (fix H5+H1).

**Rationale**: Avoids a store read and a no-op store write on every steady-state page.

**Approved**: pending
