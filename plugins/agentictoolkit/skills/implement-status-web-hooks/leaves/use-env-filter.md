<!-- leaf: implement-status-web-hooks/use-env-filter · source: status-web-hooks-use-env-filter.md -->

**Rules** (cite as `implement-status-web-hooks/use-env-filter#<slug>`):

- `signature` MUST
- `all-list` MUST
- `toggle-identity` MUST
- `envs-immutability` MUST
- `default-all-selected` MUST
- `deferred-hydration` MUST
- `storage-key` MUST
- `absent-value-keeps-default` MUST
- `array-hydration` MUST
- `invalid-entries-dropped` MUST
- `filtered-to-empty` MUST
- `duplicates-collapse` MUST
- `non-array-keeps-default` MUST
- `read-failure-keeps-default` MUST
- `toggle-flip` MUST
- `toggle-order` MUST
- `toggle-unvalidated` MUST
- `toggle-may-empty` MUST
- `toggle-functional-update` MUST
- `toggle-persist` MUST
- `write-failure-ignored` MUST
- `write-inside-updater` MAY
- `per-instance-state` MUST
- `no-cross-tab-sync` MUST
- `no-other-side-effects` MUST

# useEnvFilter

## Overview

`useEnvFilter` is a client-side React hook (`"use client"`) that holds which deployment environments the status dashboard's Overview shows. The selectable environments are the constant `ENVIRONMENTS` from `api/monitored-sites` (`["production", "staging", "testing"]`). The selection starts with every environment selected (no filter), is hydrated once from `localStorage` after the first render so server render and first paint match, and every toggle is written back to `localStorage` under the key `"adh-env-filter"` so the choice survives reloads. The Overview (`OverviewTab`) consumes it and treats "every environment selected" (`envs.size === all.length`) as unfiltered.

Use it wherever a view needs a persisted, per-browser multi-select over the fixed environment list. It holds no visual surface of its own.

## Behavioral Requirements

### Public operation

- **signature**: `useEnvFilter()` MUST take no arguments and MUST return an object with exactly three fields: `envs` (a `Set<string>` of selected environment names), `all` (a `readonly string[]` of every environment), and `toggle` (a function `(env: string) => void`).
- **all-list**: The `all` field MUST be the `ENVIRONMENTS` constant, in its declared order `production`, `staging`, `testing`, and MUST be the same array reference on every render.
- **toggle-identity**: The `toggle` function MUST keep the same identity across renders of one hook instance (it is memoised with an empty dependency list), so consumers MAY list it in dependency arrays without causing re-runs.
- **envs-immutability**: Each state change MUST produce a new `Set` instance; the previous `Set` MUST NOT be mutated, so consumers comparing `envs` by reference observe every change.

### Initial state and hydration

- **default-all-selected**: On the first render the hook MUST return `envs` containing every entry of `ENVIRONMENTS`, regardless of what storage holds.
- **deferred-hydration**: The hook MUST read storage only after the first render, exactly once per mount (an effect with an empty dependency list), so a server render and the client's first paint both show the default.
- **storage-key**: The hook MUST read and write the `localStorage` key `"adh-env-filter"`.
- **absent-value-keeps-default**: When the stored value is missing (`getItem` returns `null`) or is the empty string, hydration MUST leave `envs` at the default.
- **array-hydration**: When the stored value parses as a JSON array, hydration MUST replace `envs` with a `Set` of the array's elements that are strings and members of `ENVIRONMENTS`, in the array's order.
- **invalid-entries-dropped**: Hydration MUST silently drop array elements that are not strings or not members of `ENVIRONMENTS`.
- **filtered-to-empty**: When filtering leaves no valid elements (including a stored empty array `[]`), hydration MUST set `envs` to an empty `Set` (nothing selected), not fall back to the default.
- **duplicates-collapse**: Duplicate names in the stored array MUST collapse to one member, because the result is a `Set`.
- **non-array-keeps-default**: When the stored value parses as valid JSON that is not an array (an object, number, string, boolean or `null`), hydration MUST leave `envs` at the default.
- **read-failure-keeps-default**: When `localStorage` access throws or the stored value is not valid JSON, hydration MUST catch the exception, leave `envs` at the default, and MUST NOT propagate the error or log it.

### Toggle

- **toggle-flip**: `toggle(env)` MUST remove `env` from the selection when it is present and add it when it is absent.
- **toggle-order**: A name added by `toggle` MUST be appended after the existing members in the `Set`'s iteration order.
- **toggle-unvalidated**: `toggle` MUST NOT validate `env` against `ENVIRONMENTS`; an unknown name is added to the in-memory `Set` and persisted like any other. Only hydration filters to `ENVIRONMENTS`, so an unknown name is dropped on the next mount. Callers pass names taken from `all`, which is the precondition `OverviewTab` meets.
- **toggle-may-empty**: `toggle` MUST allow the selection to become empty; there is no minimum of one selected environment.
- **toggle-functional-update**: `toggle` MUST derive the next selection from the latest state (a functional state update), so several toggles in one event batch compose rather than overwrite each other.
- **toggle-persist**: After computing the next selection, `toggle` MUST write it to `"adh-env-filter"` as a JSON array of the `Set`'s members in iteration order (for example `["production","testing"]`).
- **write-failure-ignored**: When the `localStorage` write throws (storage unavailable, quota exceeded), `toggle` MUST catch the exception, MUST still apply the new in-memory selection, and MUST NOT propagate or log the error.

### Ordering, concurrency and scope

- **single-threaded**: All reads, writes and state updates run on the browser's main JavaScript thread; hydration and toggles cannot interleave, and React flushes the mount effect before it processes a later user event.
- **write-inside-updater**: The storage write happens inside the state-updater function. React MAY invoke that updater twice in development Strict Mode; the second write stores the same value, so the effect is idempotent.
- **per-instance-state**: Each hook instance MUST hold its own selection; a toggle in one instance MUST NOT update another mounted instance until that instance remounts and re-hydrates.
- **no-cross-tab-sync**: The hook MUST NOT listen for `storage` events; a change made in another tab is not reflected until this tab remounts the hook.
- **no-other-side-effects**: The hook MUST NOT perform network requests, logging, timers or any storage access other than one `getItem` per mount and one `setItem` per toggle.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ENVIRONMENTS` (from `api/monitored-sites`) | `readonly ["production", "staging", "testing"]` | `["production", "staging", "testing"]` | The complete selectable set, the default selection, and the allow-list hydration filters against. Changing it changes all three. |
| Storage key `KEY` | `string` (module constant) | `"adh-env-filter"` | The `localStorage` key read on mount and written on toggle. Not configurable by callers. |
| `localStorage` | Web Storage (ambient global) | Browser-provided | Injected implicitly through the global; tests install their own implementation. |

The hook takes no parameters and reads no environment variables or settings keys.

## Platform Notes

- **React/Web** (source): `packages/web/packages/status-web/src/hooks/use-env-filter.ts`. `useState` with a lazy initializer seeds the default `Set`; a mount-only `useEffect` hydrates from `localStorage` (with an eslint suppression for `react-hooks/set-state-in-effect`, justified inline as one-shot external-store sync); `useCallback` with an empty dependency list keeps `toggle` stable. The `"use client"` directive marks it as a Next.js client module. The storage write sits inside the `setEnvs` updater, which is the one React-specific quirk to drop in a port.
- **SwiftUI**: Start from an `@Observable` model (or `@AppStorage` with a `String` holding the JSON array) exposing `envs: Set<String>` and `toggle(_:)`, persisting to `UserDefaults`. There is no server render, so hydration can happen in the initializer; keep the same allow-list filter and "empty array hydrates to empty set" behavior. Mark the model `@MainActor` to match the single-threaded source.
- **Compose**: Start from a `ViewModel` holding `MutableStateFlow<Set<String>>`, persisted with Jetpack DataStore (`stringSetPreferencesKey`) or `SharedPreferences.getStringSet`. DataStore is asynchronous, so the default-then-hydrate sequence mirrors the source naturally; a `Set` there has no guaranteed order, which differs from the source's insertion-ordered JSON array.
- **AppKit / UIKit**: A plain `@MainActor` model class backed by `UserDefaults.standard` (`array(forKey:)` then filter to `[String]` members of the environment list), posting a change notification or using Combine `@Published` so the view controller updates.
- **WinUI 3**: Start from a view-model class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`) exposing a `HashSet<string>` (or `ObservableCollection<string>` for direct binding to `ToggleButton`/`CheckBox` items via `IsChecked`), a `static readonly string[] All`, and a `Toggle(string env)` method or `RelayCommand<string>`. Persist to `Windows.Storage.ApplicationData.Current.LocalSettings.Values["adh-env-filter"]` as a string produced by `System.Text.Json.JsonSerializer.Serialize(set)` and read with `JsonSerializer.Deserialize<JsonElement>`, checking `ValueKind == JsonValueKind.Array` and keeping only `String` elements contained in `All`, so non-array JSON keeps the default. Wrap both calls in `try`/`catch` (`JsonException`, `COMException`) to match the source's swallow-and-keep-default behavior. There is no SSR, so load in the constructor or `OnNavigatedTo`, but keep the default when nothing valid is stored. `HashSet<string>` does not preserve insertion order; use a `List<string>` with membership checks if the persisted order matters. All access runs on the UI thread (`DispatcherQueue`), matching the single-threaded source; no `Task`/`async` is needed because `LocalSettings` is synchronous.

