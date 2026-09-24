---
id: df9b416b-ba3d-430a-a82d-e39b11a55f2d
title: Status Web Stores
domain: agentictoolkit://recipes/status-web-stores
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: localStorage SnapshotCache adapter that persists the last telemetry snapshot
  and reads it back through a defensive, shape-gated parse
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-telemetry
- agentictoolkit://recipes/status-server-telemetry
references: []
approved-by: ''
approved-date: ''
---

# Status Web Stores

## Overview

The client-side store of the status dashboard's telemetry subsystem. It is the `localStorage` adapter of the `SnapshotCache` port (`telemetry/ports.ts`): it keeps the latest `TelemetrySnapshot` so the production-visibility band "paints instantly on reload and shows a last-known view while the source is briefly unreachable" (source comment in `stores/local-cache.ts`).

The module exports two things:

- `parseSnapshot(raw: string | null): TelemetrySnapshot | null` — a pure, browser-free parse that turns a stored string back into a snapshot, or `null` when anything about it is off.
- `localCache: SnapshotCache` — an object with `load()` and `save(snapshot)` that adds only the `window.localStorage` I/O around `parseSnapshot` and `JSON.stringify`.

The composition root `telemetry/client.ts` wires it as `export const cache: SnapshotCache = localCache;`, and the `useTelemetry` hook calls `cache.load()` once after mount and `cache.save(query.data)` whenever fresh data arrives (see [Status Web Hooks Use Telemetry](agentictoolkit://recipes/status-web-hooks-use-telemetry)). Swapping the adapter is a one-line change at that root; nothing above the port moves.

Use it when a browser client needs a last-known copy of a small JSON snapshot that survives reload, where losing the copy is harmless because the live query is the source of truth.

## Behavioral Requirements

### Data shape

- **snapshot-shape**: A `TelemetrySnapshot` MUST have exactly the fields `generatedAt: string` (ISO timestamp), `errors: ErrorDTO[]` and `analytics: AnalyticsMetricDTO[]`, as declared in `telemetry/types.ts`.
- **storage-key**: The adapter MUST store the snapshot under the single `localStorage` key `adh-telemetry-v1` (the module constant `KEY`).
- **single-slot**: The adapter MUST hold at most one snapshot; there is no history, list or per-source slot.

### Port contract

- **port-conformance**: `localCache` MUST implement the `SnapshotCache` interface: a synchronous `load(): TelemetrySnapshot | null` and a synchronous `save(snapshot: TelemetrySnapshot): void`.
- **synchronous-api**: `load` and `save` MUST NOT return a promise; both complete before returning to the caller.

### parseSnapshot

- **parse-null-empty**: `parseSnapshot` MUST return `null` when `raw` is `null` or the empty string, without attempting to parse.
- **parse-malformed-json**: `parseSnapshot` MUST return `null` when `raw` is not valid JSON; the `JSON.parse` exception MUST NOT propagate to the caller.
- **parse-json-null**: `parseSnapshot` MUST return `null` when `raw` parses to the JSON value `null`.
- **parse-generated-at-gate**: `parseSnapshot` MUST return `null` when the parsed value's `generatedAt` is not of type string.
- **parse-errors-gate**: `parseSnapshot` MUST return `null` when the parsed value's `errors` is not an array.
- **parse-analytics-gate**: `parseSnapshot` MUST return `null` when the parsed value's `analytics` is not an array.
- **parse-projection**: When all gates pass, `parseSnapshot` MUST return a new object containing only `generatedAt`, `errors` and `analytics`, dropping every other top-level key of the parsed value.
- **parse-shallow**: `parseSnapshot` MUST NOT validate the elements of `errors` or `analytics`; array contents are passed through as parsed.
- **parse-pure**: `parseSnapshot` MUST have no side effects and MUST NOT touch `window` or `localStorage`, so it runs outside a browser.

### load

- **load-no-window**: `localCache.load()` MUST return `null` when `window` is undefined (server render or non-browser runtime), without touching storage.
- **load-reads-key**: In a browser, `localCache.load()` MUST read `localStorage.getItem("adh-telemetry-v1")` and return `parseSnapshot` of that value.
- **load-missing-key**: `localCache.load()` MUST return `null` when the key is absent (`getItem` returns `null`).
- **load-storage-throws**: `localCache.load()` MUST return `null` when accessing `window.localStorage` or calling `getItem` throws (for example storage disabled by browser policy); the exception MUST NOT propagate.
- **load-no-cleanup**: `localCache.load()` MUST NOT remove or rewrite a stored value that fails the parse; the invalid value stays until the next `save` overwrites it.

### save

- **save-no-window**: `localCache.save(snapshot)` MUST do nothing when `window` is undefined.
- **save-format**: In a browser, `localCache.save(snapshot)` MUST write `JSON.stringify(snapshot)` to `localStorage` under the key `adh-telemetry-v1`.
- **save-overwrites**: Each `save` MUST replace the previously stored value in full; there is no merge with the old snapshot.
- **save-no-projection**: `save` MUST serialize the snapshot object as given, including any extra top-level keys the caller attached; only `parseSnapshot` on the read path drops them.
- **save-best-effort**: `localCache.save` MUST swallow any exception from accessing `localStorage` or from `setItem` (for example a quota-exceeded error), returning normally; the source comment declares this "best-effort — the in-memory query result is the live truth".
- **save-no-validation**: `save` MUST NOT validate the snapshot before writing; the `TelemetrySnapshot` parameter type is the caller's precondition.

### Durability

- **durability-reload**: A saved snapshot MUST survive a page reload and a browser restart for the same origin, for as long as the browser retains that origin's `localStorage`.
- **durability-loss-harmless**: Loss of the stored snapshot (cleared site data, private window, quota) MUST NOT be reported to the caller; `load` then returns `null` and the live query repopulates it.
- **no-expiry**: The adapter MUST NOT expire, age out or timestamp-check the stored snapshot; staleness is judged by consumers from `generatedAt`.

### Concurrency and side effects

- **single-threaded**: `load` and `save` MUST run synchronously on the browser's main JavaScript thread; calls from one page cannot interleave, and the last `save` to return is the stored value.
- **cross-tab-last-write**: Two tabs of the same origin share the one key; the adapter MUST NOT coordinate between them, so the value stored is whichever tab called `save` last.
- **only-side-effect**: The adapter's only side effect MUST be the read and write of the one `localStorage` key; it performs no network, logging, events or timers.

## Appearance

Not applicable — this is a browser storage adapter, not a visual component.

## States

Not applicable — this is a browser storage adapter, not a visual component.

## Accessibility

Not applicable — this is a browser storage adapter, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| stores-001 | parse-projection, snapshot-shape | `parseSnapshot(JSON.stringify(snap))` where `snap` has `generatedAt: "2026-06-13T12:00:00.000Z"`, one error (`id: "1"`, `project: "hub"`, `title: "boom"`, `count: 3`) and one analytics metric (`pageviews`, `24h`, `all`, `10`) (from `local-cache.test.ts`) | Result deep-equals `snap` |
| stores-002 | parse-null-empty | `parseSnapshot(null)` and `parseSnapshot("")` (from `local-cache.test.ts`) | Both return `null` |
| stores-003 | parse-malformed-json | `parseSnapshot("{not json")` (from `local-cache.test.ts`) | Returns `null`; no exception thrown |
| stores-004 | parse-json-null | `parseSnapshot(JSON.stringify(null))` (from `local-cache.test.ts`) | Returns `null` |
| stores-005 | parse-errors-gate, parse-analytics-gate | `parseSnapshot(JSON.stringify({ generatedAt: "x" }))` (from `local-cache.test.ts`) | Returns `null` |
| stores-006 | parse-generated-at-gate | `parseSnapshot(JSON.stringify({ generatedAt: 1, errors: [], analytics: [] }))` (from `local-cache.test.ts`) | Returns `null` |
| stores-007 | parse-errors-gate | `parseSnapshot(JSON.stringify({ generatedAt: "x", errors: "nope", analytics: [] }))` (from `local-cache.test.ts`) | Returns `null` |
| stores-008 | parse-analytics-gate | `parseSnapshot('{"generatedAt":"x","errors":[],"analytics":{}}')` | Returns `null` |
| stores-009 | parse-projection | `parseSnapshot('{"generatedAt":"x","errors":[],"analytics":[],"extra":1}')` | Returns `{ generatedAt: "x", errors: [], analytics: [] }` with no `extra` key |
| stores-010 | parse-shallow | `parseSnapshot('{"generatedAt":"x","errors":[42],"analytics":["y"]}')` | Returns `{ generatedAt: "x", errors: [42], analytics: ["y"] }` |
| stores-011 | parse-generated-at-gate | `parseSnapshot('{"generatedAt":"","errors":[],"analytics":[]}')` | Returns `{ generatedAt: "", errors: [], analytics: [] }` (empty string is still a string) |
| stores-012 | save-format, load-reads-key, durability-reload | In a browser with empty storage, `localCache.save(snap)` then `localCache.load()` | `localStorage.getItem("adh-telemetry-v1")` equals `JSON.stringify(snap)`; `load()` deep-equals `snap` |
| stores-013 | load-missing-key | Browser storage with no `adh-telemetry-v1` key; call `localCache.load()` | Returns `null` |
| stores-014 | save-overwrites | `save(a)` then `save(b)`; call `load()` | Returns `b`; nothing of `a` remains |
| stores-015 | load-no-window, save-no-window | Runtime where `typeof window === "undefined"`; call `localCache.load()` and `localCache.save(snap)` | `load` returns `null`; `save` returns without throwing and writes nothing |
| stores-016 | load-storage-throws | `window.localStorage.getItem` stubbed to throw; call `localCache.load()` | Returns `null`; no exception propagates |
| stores-017 | save-best-effort | `window.localStorage.setItem` stubbed to throw a quota error; call `localCache.save(snap)` | Returns normally; no exception propagates; stored value unchanged |
| stores-018 | load-no-cleanup | Key holds `"{not json"`; call `localCache.load()` then read the key | `load` returns `null`; key still holds `"{not json"` |
| stores-019 | save-no-projection | `save({ ...snap, extra: 1 })`; read the raw key | Raw JSON contains `"extra":1`; `load()` returns the snapshot without `extra` |
| stores-020 | only-side-effect | Spy on `fetch`, `console` and every `localStorage` method; call `save(snap)` then `load()` | Only `setItem("adh-telemetry-v1", …)` and `getItem("adh-telemetry-v1")` are called |

## Edge Cases

- **Null or empty stored value**: `getItem` returns `null` (never saved) or `""` → `load` returns `null` (MUST, parse-null-empty, load-missing-key).
- **Corrupt stored value**: The key holds malformed JSON, `null`, a scalar, or an object missing `generatedAt`, `errors` or `analytics` → `load` returns `null` and leaves the value in place (MUST, load-no-cleanup).
- **Boundary: empty arrays and empty timestamp**: `{ generatedAt: "", errors: [], analytics: [] }` passes the gate and is returned as is; this is the same value `emptySnapshot()` produces (MUST, stores-011).
- **Malformed array elements**: `errors` or `analytics` contain values that are not DTOs → returned unchanged; consumers receive them as typed DTOs (MUST, parse-shallow). The stored value normally comes only from this adapter's own `save` of a typed snapshot; see Design Decisions.
- **Schema change**: A future incompatible `TelemetrySnapshot` shape that still has a string `generatedAt` and two arrays passes the gate; the versioned key name `adh-telemetry-v1` is the only migration lever (fact).
- **Storage unavailable**: `localStorage` access throws (storage blocked, sandboxed iframe) → `load` returns `null` and `save` is a no-op, both silently (MUST, load-storage-throws, save-best-effort).
- **Quota exceeded**: `setItem` throws because the serialized snapshot does not fit → the write is dropped silently; the previous stored value, if any, remains (MUST, save-best-effort).
- **Non-browser runtime**: `window` undefined during server render → `load` returns `null`, `save` is a no-op (MUST, load-no-window, save-no-window).
- **Concurrent access**: Within one page, JavaScript is single-threaded and both calls are synchronous, so no interleaving is possible. Across tabs of the same origin, the last `save` wins with no coordination and no `storage` event handling (MUST, cross-tab-last-write).
- **Offline or disconnected**: The adapter does no network I/O; offline is the case it exists for — `load` still returns the last saved snapshot (MUST, only-side-effect, durability-reload).
- **Cancellation and timeouts**: Not applicable — both operations are synchronous and bounded by one storage call; there is nothing to cancel and no timeout.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `KEY` (module constant) | `string` | `"adh-telemetry-v1"` | The single `localStorage` key; not configurable by the caller. |
| `window.localStorage` (environment) | `Storage` | Browser-provided | The only storage backend; absent in non-browser runtimes, which the adapter treats as "no cache". |
| `cache` (composition root) | `SnapshotCache` | `localCache` | Selected in `telemetry/client.ts`; replacing it swaps the adapter with no other change. |

The adapter takes no constructor parameters, environment variables or feature settings.

## Deep Linking

Not applicable: `stores/local-cache.ts` is a storage adapter with no route, URL or navigable surface.

## Localization

Not applicable: `stores/local-cache.ts` contains no user-facing strings; its only string literal is the storage key `adh-telemetry-v1`.

## Accessibility Options

Not applicable: `stores/local-cache.ts` renders nothing and has no motion, contrast or color behavior.

## Feature Flags

Not applicable: `stores/local-cache.ts` reads no flag; the adapter is selected unconditionally by `telemetry/client.ts`.

## Analytics

Not applicable: `stores/local-cache.ts` emits no events; it only stores a snapshot whose `analytics` array holds aggregate KPIs fetched elsewhere.

## Privacy

- **Data collected**: None from the user. The adapter stores the telemetry snapshot the dashboard already fetched: grouped error issues (`project`, `title`, `culprit`, `level`, counts, timestamps, `permalink`) and anonymous aggregate analytics KPIs (`metric`, `window`, `scope`, `value`).
- **Storage**: Plain-text JSON in the browser's `localStorage` for the dashboard's origin, under `adh-telemetry-v1`; not encrypted, readable by any script running on that origin.
- **Transmission**: None. The adapter never sends the snapshot anywhere.
- **Retention**: Until the next `save` overwrites it or the browser clears the origin's site data; the adapter never deletes or expires it.

## Logging

Not applicable: `stores/local-cache.ts` makes no log calls; both `catch` blocks return silently (`null` from `load`, nothing from `save`).

## Platform Notes

- **SwiftUI**: Start from `UserDefaults` (or a small file in the Caches directory written with `Data.write(to:options: .atomic)`) holding `JSONEncoder` output of a `Codable` `TelemetrySnapshot`. `@AppStorage` works for a `Data`/`String` blob. Swift has no "no window" case; drop `load-no-window`/`save-no-window`. Replace the shape gate with `try? JSONDecoder().decode(...)`, noting that `Codable` validates array elements too, which is stricter than `parse-shallow`; decode elements leniently (for example `[AnyCodable]` or a lossy wrapper) if strict parity matters. Make the adapter a `Sendable` struct or a `@MainActor` type so the synchronous contract is preserved.
- **Compose**: Start from `SharedPreferences` (synchronous `getString`/`edit().putString().apply()`) with `kotlinx.serialization` `Json { ignoreUnknownKeys = true }`, which mirrors `parse-projection`. `DataStore` is the modern choice but is asynchronous (`Flow`), which changes the port to `suspend`; keep `SharedPreferences` for a synchronous port. Wrap decode in `runCatching { … }.getOrNull()` for the null-on-anything-off gate.
- **React/Web**: The source platform. `stores/local-cache.ts` holds the adapter and the pure `parseSnapshot`; `stores/local-cache.test.ts` covers the parse with vitest; `telemetry/ports.ts` declares `SnapshotCache`; `telemetry/client.ts` wires `localCache` as `cache`; `hooks/use-telemetry.ts` reads it in an effect after mount (to keep server and first client render identical) and writes it on every new query result. The `typeof window === "undefined"` guards exist for server rendering.
- **AppKit / UIKit**: Same as SwiftUI: `UserDefaults.standard.data(forKey:)` / `set(_:forKey:)` with `JSONDecoder`/`JSONEncoder`, or `NSCache` if persistence across launches is not needed (it is here, so `UserDefaults` or a cache-directory file). Call it on the main thread to match `single-threaded`.
- **WinUI 3**: Start from `Windows.Storage.ApplicationData.Current.LocalSettings.Values["adh-telemetry-v1"]` holding a `string` of `System.Text.Json.JsonSerializer.Serialize(snapshot)`; note each `LocalSettings` value is limited to 8 KB, so a large snapshot belongs in a file in `ApplicationData.Current.LocalCacheFolder` via `FileIO.WriteTextAsync`/`ReadTextAsync` instead — which makes the API `Task`-based and changes the synchronous port to `Task<TelemetrySnapshot?> LoadAsync()` / `Task SaveAsync(...)`. For a synchronous port with an unpackaged app, use `System.IO.File.ReadAllText`/`WriteAllText` under `Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)`. Reproduce the gate with `JsonDocument.Parse` inside `try`/`catch (JsonException)`, checking `ValueKind == JsonValueKind.String` for `generatedAt` and `JsonValueKind.Array` for `errors` and `analytics`, then project into a new record (`record TelemetrySnapshot(string GeneratedAt, List<ErrorDto> Errors, List<AnalyticsMetricDto> Analytics)`). Catch `IOException`/`UnauthorizedAccessException` on write to match `save-best-effort`. There is no server-render case; drop the `window` guards. If the view model exposes the snapshot, surface it through `INotifyPropertyChanged` and an `ObservableCollection<ErrorDto>` — the adapter itself stays a plain class with no notifications, matching `only-side-effect`.

## Design Decisions

**Decision**: The read path is a shallow shape gate (`generatedAt` string, `errors` and `analytics` arrays) and does not validate array elements.
**Rationale**: The stored value is written only by this adapter's own `save` of a typed `TelemetrySnapshot`, so the gate guards against a corrupt, truncated or foreign value rather than re-validating trusted DTOs; the source comment calls it a "defensive, shape-gated parse — anything off → null". The versioned key name is the migration lever for an incompatible shape change.
**Approved**: pending

**Decision**: Both operations swallow every storage exception silently — `load` returns `null`, `save` does nothing.
**Rationale**: The cache is an optimization for instant paint and last-known view; the source comment states "best-effort — the in-memory query result is the live truth". A cache failure degrades to the no-cache path the consumer already handles (`emptySnapshot()` until the live query lands).
**Approved**: pending

**Decision**: `parseSnapshot` is split out as a pure exported function.
**Rationale**: The source comment says the split makes the parse "unit-testable without a browser; the adapter only adds the window/localStorage I/O". `local-cache.test.ts` tests only `parseSnapshot`.
**Approved**: pending

**Decision**: The port is synchronous.
**Rationale**: `localStorage` is synchronous, and the consumer reads the cache in a mount effect to paint before any network result; an async port would add a frame of empty state. Ports whose backing store is asynchronous change the signature (see Platform Notes, WinUI 3 and Compose).
**Approved**: pending

**Decision**: A stored value that fails the parse is left in place, and `save` does not project extra keys.
**Rationale**: The source has no cleanup or projection on the write path; the next successful `save` overwrites the key in full, so a stale or corrupt value costs one cold paint at most.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | performance |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |
| [secure-data-storage](agenticdevelopercookbook://compliance/privacy-and-data#secure-data-storage) | partial | privacy-and-data |

The adapter sits behind the `SnapshotCache` port and knows nothing about providers, sources or the UI, and the pure parse is separated from the storage I/O, so separation of concerns passes. `local-cache.test.ts` covers `parseSnapshot` (round trip, null/empty, malformed JSON, wrong shapes) but not `localCache.load`/`save` or the `window` and exception guards, so unit-test coverage is partial. Every storage exception is caught deliberately and documented as best-effort, but nothing records that a write was dropped, so explicit error handling is partial. Unavailable storage degrades to the no-cache path, so graceful degradation passes, and the single-slot last-known snapshot with consumer-side staleness from `generatedAt` is a coherent caching strategy. The read gate rejects corrupt top-level shapes but passes array elements unvalidated, so data integrity is partial. The snapshot (error titles, culprits, permalinks) is stored as unencrypted JSON in origin-scoped `localStorage`, which holds no credentials or user PII but is readable by any script on the origin, so secure data storage is partial.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from `stores/local-cache.ts` and its test |
