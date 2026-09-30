<!-- leaf: implement-status-web/stores · source: status-web-stores.md -->

**Rules** (cite as `implement-status-web/stores#<slug>`):

- `snapshot-shape` MUST
- `storage-key` MUST
- `single-slot` MUST
- `port-conformance` MUST
- `synchronous-api` MUST
- `parse-null-empty` MUST
- `parse-malformed-json` MUST
- `parse-json-null` MUST
- `parse-generated-at-gate` MUST
- `parse-errors-gate` MUST
- `parse-analytics-gate` MUST
- `parse-projection` MUST
- `parse-shallow` MUST
- `parse-pure` MUST
- `load-no-window` MUST
- `load-reads-key` MUST
- `load-missing-key` MUST
- `load-storage-throws` MUST
- `load-no-cleanup` MUST
- `save-no-window` MUST
- `save-format` MUST
- `save-overwrites` MUST
- `save-no-projection` MUST
- `save-best-effort` MUST
- `save-no-validation` MUST
- `durability-reload` MUST
- `durability-loss-harmless` MUST
- `no-expiry` MUST
- `single-threaded` MUST
- `cross-tab-last-write` MUST
- `only-side-effect` MUST

# Status Web Stores

## Overview

The client-side store of the status dashboard's telemetry subsystem. It is the `localStorage` adapter of the `SnapshotCache` port (`telemetry/ports.ts`): it keeps the latest `TelemetrySnapshot` so the production-visibility band "paints instantly on reload and shows a last-known view while the source is briefly unreachable" (source comment in `stores/local-cache.ts`).

The module exports two things:

- `parseSnapshot(raw: string | null): TelemetrySnapshot | null` — a pure, browser-free parse that turns a stored string back into a snapshot, or `null` when anything about it is off.
- `localCache: SnapshotCache` — an object with `load()` and `save(snapshot)` that adds only the `window.localStorage` I/O around `parseSnapshot` and `JSON.stringify`.

The composition root `telemetry/client.ts` wires it as `export const cache: SnapshotCache = localCache;`, and the `useTelemetry` hook calls `cache.load()` once after mount and `cache.save(query.data)` whenever fresh data arrives (see Status Web Hooks Use Telemetry). Swapping the adapter is a one-line change at that root; nothing above the port moves.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `KEY` (module constant) | `string` | `"adh-telemetry-v1"` | The single `localStorage` key; not configurable by the caller. |
| `window.localStorage` (environment) | `Storage` | Browser-provided | The only storage backend; absent in non-browser runtimes, which the adapter treats as "no cache". |
| `cache` (composition root) | `SnapshotCache` | `localCache` | Selected in `telemetry/client.ts`; replacing it swaps the adapter with no other change. |

The adapter takes no constructor parameters, environment variables or feature settings.

## Privacy

- **Data collected**: None from the user. The adapter stores the telemetry snapshot the dashboard already fetched: grouped error issues (`project`, `title`, `culprit`, `level`, counts, timestamps, `permalink`) and anonymous aggregate analytics KPIs (`metric`, `window`, `scope`, `value`).
- **Storage**: Plain-text JSON in the browser's `localStorage` for the dashboard's origin, under `adh-telemetry-v1`; not encrypted, readable by any script running on that origin.
- **Transmission**: None. The adapter never sends the snapshot anywhere.
- **Retention**: Until the next `save` overwrites it or the browser clears the origin's site data; the adapter never deletes or expires it.

## Platform Notes

- **SwiftUI**: Start from `UserDefaults` (or a small file in the Caches directory written with `Data.write(to:options: .atomic)`) holding `JSONEncoder` output of a `Codable` `TelemetrySnapshot`. `@AppStorage` works for a `Data`/`String` blob. Swift has no "no window" case; drop `load-no-window`/`save-no-window`. Replace the shape gate with `try? JSONDecoder().decode(...)`, noting that `Codable` validates array elements too, which is stricter than `parse-shallow`; decode elements leniently (for example `[AnyCodable]` or a lossy wrapper) if strict parity matters. Make the adapter a `Sendable` struct or a `@MainActor` type so the synchronous contract is preserved.
- **Compose**: Start from `SharedPreferences` (synchronous `getString`/`edit().putString().apply()`) with `kotlinx.serialization` `Json { ignoreUnknownKeys = true }`, which mirrors `parse-projection`. `DataStore` is the modern choice but is asynchronous (`Flow`), which changes the port to `suspend`; keep `SharedPreferences` for a synchronous port. Wrap decode in `runCatching { … }.getOrNull()` for the null-on-anything-off gate.
- **React/Web**: The source platform. `stores/local-cache.ts` holds the adapter and the pure `parseSnapshot`; `stores/local-cache.test.ts` covers the parse with vitest; `telemetry/ports.ts` declares `SnapshotCache`; `telemetry/client.ts` wires `localCache` as `cache`; `hooks/use-telemetry.ts` reads it in an effect after mount (to keep server and first client render identical) and writes it on every new query result. The `typeof window === "undefined"` guards exist for server rendering.
- **AppKit / UIKit**: Same as SwiftUI: `UserDefaults.standard.data(forKey:)` / `set(_:forKey:)` with `JSONDecoder`/`JSONEncoder`, or `NSCache` if persistence across launches is not needed (it is here, so `UserDefaults` or a cache-directory file). Call it on the main thread to match `single-threaded`.
- **WinUI 3**: Start from `Windows.Storage.ApplicationData.Current.LocalSettings.Values["adh-telemetry-v1"]` holding a `string` of `System.Text.Json.JsonSerializer.Serialize(snapshot)`; note each `LocalSettings` value is limited to 8 KB, so a large snapshot belongs in a file in `ApplicationData.Current.LocalCacheFolder` via `FileIO.WriteTextAsync`/`ReadTextAsync` instead — which makes the API `Task`-based and changes the synchronous port to `Task<TelemetrySnapshot?> LoadAsync()` / `Task SaveAsync(...)`. For a synchronous port with an unpackaged app, use `System.IO.File.ReadAllText`/`WriteAllText` under `Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)`. Reproduce the gate with `JsonDocument.Parse` inside `try`/`catch (JsonException)`, checking `ValueKind == JsonValueKind.String` for `generatedAt` and `JsonValueKind.Array` for `errors` and `analytics`, then project into a new record (`record TelemetrySnapshot(string GeneratedAt, List<ErrorDto> Errors, List<AnalyticsMetricDto> Analytics)`). Catch `IOException`/`UnauthorizedAccessException` on write to match `save-best-effort`. There is no server-render case; drop the `window` guards. If the view model exposes the snapshot, surface it through `INotifyPropertyChanged` and an `ObservableCollection<ErrorDto>` — the adapter itself stays a plain class with no notifications, matching `only-side-effect`.

