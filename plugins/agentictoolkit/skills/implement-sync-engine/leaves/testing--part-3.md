<!-- leaf: implement-sync-engine/testing--part-3 · source: sync-engine-testing.md -->

# Sync Engine Testing — continued (part 3)

## Localization

The fakes have no localized strings. The only human-readable text is the hardcoded English `invalidChange` payload `"unparseable syncVersion: <value>"`; `SyncStoreFailure` has no `LocalizedError` conformance.

## Privacy

- **Data collected**: Only the row payloads, ops and requests a test supplies.
- **Storage**: In actor memory only (`resourceStates`, `outbox`, `quarantined`, `conflictLog`, `pullCursors`, `pushedRequests`).
- **Transmission**: None; `ScriptedSyncTransport` makes no network call.
- **Retention**: Until the instance is released; nothing is persisted.

## Platform Notes

- **SwiftUI**: Source platform (`Sync/Testing/InMemorySyncStore.swift`, `Sync/Testing/ScriptedSyncTransport.swift`, compiled into the `AgenticToolkitSync` framework, not a test target). Both are `actor`s, so tests `await` even the synchronous conveniences. `SyncID.uuidV7()` supplies opIds; `Dictionary.merging(_:uniquingKeysWith:)` implements the coalescing merge. A SwiftUI preview can seed an `InMemorySyncStore` and a `ScriptedSyncTransport` to render sync UI with no backend.
- **Compose**: Write the store as a class guarding its maps with a `kotlinx.coroutines.sync.Mutex` (or confine it to `Dispatchers.Default.limitedParallelism(1)`) so `suspend` methods serialize like the actor. Use `LinkedHashMap` for rows and a `MutableList` for the outbox to keep FIFO order; stage `apply` into a copy and swap it in for atomicity. The transport becomes an `ArrayDeque<Result<T>>` per script. Test with `kotlinx-coroutines-test` `runTest`; `java.util.UUID` has no v7 generator, so port `SyncID`.
- **React/Web**: Single-threaded JS makes each synchronous method atomic without a lock, but async methods interleave across `await`, so keep method bodies free of `await` as the source does. Use `Map` (insertion-ordered) for rows and an array for the outbox; deep-copy the resource map with `structuredClone` before applying a batch. The transport is two arrays shifted per call. `Number.parseInt` accepts trailing garbage, so validate `syncVersion` with a digits-only check instead.
- **AppKit / UIKit**: The same Swift sources apply unchanged; the framework is Foundation-only, so AppKit and UIKit hosts and XCTest bundles use the fakes directly.
- **WinUI 3**: Write the store as a class whose `Task`-returning methods take a `SemaphoreSlim(1, 1)` (or keep bodies synchronous and use `lock`), with `Dictionary<string, ResourceState>` for rows and `List<OutboxEntry>` for the outbox; copy the dictionary before applying a batch to keep `apply` atomic. The transport holds two `Queue<Outcome<T>>` and returns `Task.FromResult` or `Task.FromException`. Record requests in `List<T>` exposed as `IReadOnlyList<T>`. Wire types use `System.Text.Json` with `JsonNode` in place of `JSONValue`. For the `syncVersion` check use `int.TryParse` with `NumberStyles.AllowLeadingSign` and `CultureInfo.InvariantCulture`, which matches Swift's `Int(_:)` (sign allowed, whitespace rejected); the default `NumberStyles.Integer` also accepts surrounding whitespace. `Guid.CreateVersion7()` (.NET 9) supplies opIds but does not guarantee same-millisecond ordering. A view model bound to `ObservableCollection` can read the fakes in XAML previews, but tests need no `INotifyPropertyChanged`.

## Design Decisions

### Fakes ship in the framework

**Decision**: The fakes live in the production `AgenticToolkitSync` target under `Sync/Testing/`, not in a test target.

**Rationale**: The source comment names this the toolkit convention (see `Core/Chat/MockChatSession.swift`), so host apps' tests and previews can use the same fakes as the toolkit's own tests.

**Approved**: pending

### Parity with GRDBSyncStore

**Decision**: `InMemorySyncStore` reproduces `GRDBSyncStore`'s atomic apply, `syncVersion` validation, coalescing, inflight replay, unparseable-`newVersion` skipping and unregistered-purge no-op.

**Rationale**: The doc comments say the fakes must not "lie" about the real store (sync fix-wave items p2a, p2o, A5, E3/F5), so engine tests run against the fake predict behavior on SQLite.

**Approved**: pending

### One entry for registration and rows

**Decision**: Schema version and rows are held in one `ResourceState` value per resource.

**Rationale**: The source comment says key presence IS the registration truth, replacing two dictionaries that had to be kept in step by hand.

**Approved**: pending

### Inflight ops are replayed, never coalesced

**Decision**: `pendingOps` marks ops inflight and returns them again; `stage` never edits an inflight op.

**Rationale**: A push that never completed must be retried under the same opId, because the server ledgers results per opId; editing an op already sent would change what that opId means.

**Approved**: pending

### Default transport responses

**Decision**: An empty script yields an empty pull echoing the cursor (or "empty") and an all-applied push.

**Rationale**: Tests script only the calls they care about; every other cycle step succeeds quietly.

**Approved**: pending
