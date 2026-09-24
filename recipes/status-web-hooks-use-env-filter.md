---
id: dcfe8ed6-2129-44ea-a084-eb30b640c0e3
title: useEnvFilter
domain: agentictoolkit://recipes/status-web-hooks-use-env-filter
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook holding the Overview's selected-environments filter, defaulting
  to all and persisted to localStorage.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-activity-ttl
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a React state hook backed by localStorage, not a visual component.

## States

Not applicable — this is a React state hook backed by localStorage, not a visual component.

## Accessibility

Not applicable — this is a React state hook backed by localStorage, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input / Precondition | Action | Expected |
|----|-------------|----------------------|--------|----------|
| env-filter-001 | signature, default-all-selected, all-list | Empty storage | Render the hook; read the first render's result | `envs` equals `{production, staging, testing}`; `all` is `["production","staging","testing"]`; `toggle` is a function |
| env-filter-002 | deferred-hydration, array-hydration, storage-key | `"adh-env-filter"` = `["production"]` | Render; capture first render; flush effects | First render `envs` = all three; after effects `envs` = `{production}` |
| env-filter-003 | absent-value-keeps-default | `"adh-env-filter"` = `""` (empty string) | Render; flush effects | `envs` stays all three; `JSON.parse` is not reached |
| env-filter-004 | invalid-entries-dropped, duplicates-collapse | `"adh-env-filter"` = `["staging", 7, "prod", "staging", null]` | Render; flush effects | `envs` = `{staging}` (size 1) |
| env-filter-005 | filtered-to-empty | `"adh-env-filter"` = `[]` | Render; flush effects | `envs` is an empty `Set` |
| env-filter-006 | filtered-to-empty | `"adh-env-filter"` = `["qa","dev"]` | Render; flush effects | `envs` is an empty `Set` (not the default) |
| env-filter-007 | non-array-keeps-default | `"adh-env-filter"` = `{"production":true}` | Render; flush effects | `envs` stays all three |
| env-filter-008 | read-failure-keeps-default | `"adh-env-filter"` = `{not json` | Render; flush effects | No exception escapes; `envs` stays all three |
| env-filter-009 | read-failure-keeps-default | `localStorage.getItem` throws `SecurityError` | Render; flush effects | No exception escapes; `envs` stays all three |
| env-filter-010 | toggle-flip, toggle-persist, envs-immutability | Default state (all three) | Call `toggle("staging")` | `envs` = `{production, testing}` and is a different `Set` instance; storage holds `["production","testing"]` |
| env-filter-011 | toggle-flip, toggle-order, toggle-persist | State after env-filter-010 | Call `toggle("staging")` | `envs` = `{production, testing, staging}`; storage holds `["production","testing","staging"]` |
| env-filter-012 | toggle-may-empty | `envs` = `{production}` | Call `toggle("production")` | `envs` is empty; storage holds `[]` |
| env-filter-013 | toggle-functional-update | Default state | Call `toggle("production")` and `toggle("testing")` in one batch | `envs` = `{staging}`; storage holds `["staging"]` |
| env-filter-014 | write-failure-ignored | `localStorage.setItem` throws `QuotaExceededError` | Call `toggle("testing")` | No exception escapes; `envs` = `{production, staging}` |
| env-filter-015 | toggle-unvalidated | Default state | Call `toggle("qa")`; then remount and flush effects | Before remount `envs` has 4 members including `qa`, storage holds `["production","staging","testing","qa"]`; after remount `envs` = all three |
| env-filter-016 | toggle-identity, all-list | Any state | Call `toggle` to force a re-render; compare the returned `toggle` and `all` with the previous render's | Both are reference-equal to the previous values |
| env-filter-017 | storage-key | Storage holds `"adh-env-filter"` = `["production"]` | Run `purgeRetiredStorage()` (from `lib/retired-storage`) | The key survives unchanged; this is asserted in `retired-storage.test.ts` ("leaves keys the app still uses alone") |

## Edge Cases

- **Missing key**: `getItem` returns `null`; the hook MUST keep the default (all selected).
- **Empty string stored**: `""` is falsy; the hook MUST keep the default without parsing.
- **Empty array stored**: `[]` is a valid array; the hook MUST hydrate to an empty selection. A consumer that treats "none selected" as "show nothing" shows nothing after reload.
- **Only unknown names stored** (for example after an environment is removed from `ENVIRONMENTS`): the hook MUST hydrate to an empty selection, not the default.
- **Non-array JSON** (`null`, a number, an object, a quoted string): the hook MUST keep the default.
- **Malformed JSON**: the parse exception MUST be caught and the default kept.
- **Storage unavailable** (disabled cookies/site data, sandboxed frame, private mode that throws): both the read and every write MUST be caught; the hook MUST keep working in memory only, and the choice is lost on reload.
- **Quota exceeded on write**: the in-memory toggle MUST still apply; the stored value stays at its previous content.
- **Unknown environment passed to `toggle`**: the name MUST be accepted in memory and persisted, then dropped by the next hydration. While it is present, `envs.size` can equal `all.length` without every environment being selected, which misleads a consumer's "unfiltered" check such as `OverviewTab`'s.
- **Toggle before hydration**: cannot occur in practice; React flushes the mount effect before handling a later user event, and all code is single-threaded.
- **Several instances mounted**: each MUST keep its own selection; the last writer's value is what the next mount hydrates from.
- **Another tab changes the value**: the hook SHOULD NOT reflect it until remount, because it registers no `storage` listener (rationale in Design Decisions).
- **Server render**: storage is never touched during render, so the hook MUST render the default on the server without referencing `localStorage`.
- **Timeouts, cancellation, network loss**: not applicable; the hook performs only synchronous `localStorage` calls and no network I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ENVIRONMENTS` (from `api/monitored-sites`) | `readonly ["production", "staging", "testing"]` | `["production", "staging", "testing"]` | The complete selectable set, the default selection, and the allow-list hydration filters against. Changing it changes all three. |
| Storage key `KEY` | `string` (module constant) | `"adh-env-filter"` | The `localStorage` key read on mount and written on toggle. Not configurable by callers. |
| `localStorage` | Web Storage (ambient global) | Browser-provided | Injected implicitly through the global; tests install their own implementation. |

The hook takes no parameters and reads no environment variables or settings keys.

## Deep Linking

Not applicable: the hook reads and writes only `localStorage` and never reads or writes the URL, so the filter is not addressable by link.

## Localization

Not applicable: the hook contains no user-facing strings; the environment names are data identifiers whose display is the consumer's concern.

## Accessibility Options

Not applicable: the hook renders nothing and does not read any display preference.

## Feature Flags

Not applicable: the hook is not gated by any flag; it always returns a selection.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook stores only a list of environment names (a UI preference) in the browser's own `localStorage`; it collects no personal data and transmits nothing.

## Logging

Not applicable: the hook makes no log calls; both caught exceptions are discarded without logging.

## Platform Notes

- **React/Web** (source): `packages/web/packages/status-web/src/hooks/use-env-filter.ts`. `useState` with a lazy initializer seeds the default `Set`; a mount-only `useEffect` hydrates from `localStorage` (with an eslint suppression for `react-hooks/set-state-in-effect`, justified inline as one-shot external-store sync); `useCallback` with an empty dependency list keeps `toggle` stable. The `"use client"` directive marks it as a Next.js client module. The storage write sits inside the `setEnvs` updater, which is the one React-specific quirk to drop in a port.
- **SwiftUI**: Start from an `@Observable` model (or `@AppStorage` with a `String` holding the JSON array) exposing `envs: Set<String>` and `toggle(_:)`, persisting to `UserDefaults`. There is no server render, so hydration can happen in the initializer; keep the same allow-list filter and "empty array hydrates to empty set" behavior. Mark the model `@MainActor` to match the single-threaded source.
- **Compose**: Start from a `ViewModel` holding `MutableStateFlow<Set<String>>`, persisted with Jetpack DataStore (`stringSetPreferencesKey`) or `SharedPreferences.getStringSet`. DataStore is asynchronous, so the default-then-hydrate sequence mirrors the source naturally; a `Set` there has no guaranteed order, which differs from the source's insertion-ordered JSON array.
- **AppKit / UIKit**: A plain `@MainActor` model class backed by `UserDefaults.standard` (`array(forKey:)` then filter to `[String]` members of the environment list), posting a change notification or using Combine `@Published` so the view controller updates.
- **WinUI 3**: Start from a view-model class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`) exposing a `HashSet<string>` (or `ObservableCollection<string>` for direct binding to `ToggleButton`/`CheckBox` items via `IsChecked`), a `static readonly string[] All`, and a `Toggle(string env)` method or `RelayCommand<string>`. Persist to `Windows.Storage.ApplicationData.Current.LocalSettings.Values["adh-env-filter"]` as a string produced by `System.Text.Json.JsonSerializer.Serialize(set)` and read with `JsonSerializer.Deserialize<JsonElement>`, checking `ValueKind == JsonValueKind.Array` and keeping only `String` elements contained in `All`, so non-array JSON keeps the default. Wrap both calls in `try`/`catch` (`JsonException`, `COMException`) to match the source's swallow-and-keep-default behavior. There is no SSR, so load in the constructor or `OnNavigatedTo`, but keep the default when nothing valid is stored. `HashSet<string>` does not preserve insertion order; use a `List<string>` with membership checks if the persisted order matters. All access runs on the UI thread (`DispatcherQueue`), matching the single-threaded source; no `Task`/`async` is needed because `LocalSettings` is synchronous.

## Design Decisions

**Decision**: Start at the default (all selected) and hydrate from storage in a mount effect rather than reading storage in the state initializer.

**Rationale**: The source comment states it keeps "SSR/first-paint match": a server render has no `localStorage`, so reading it during render would make the client's first render differ from the server's HTML. `useActivityTtl` and `useBuildProgress` cite this hook as the pattern they mirror.

**Approved**: pending

**Decision**: Hydration filters stored names against `ENVIRONMENTS` but `toggle` does not validate its argument.

**Rationale**: Stored data is untrusted (older builds, hand edits, a removed environment), so it is filtered on read. `toggle` is only called with names from `all` by its one consumer, so the source leaves the check out; the filter on the next hydration repairs any stray name.

**Approved**: pending

**Decision**: A stored array whose entries are all invalid, or an empty array, hydrates to an empty selection rather than the default.

**Rationale**: The source applies the filter result directly whenever the parsed value is an array; only a missing, non-array or unparseable value falls back to the default. A port MUST keep this distinction to behave identically after reload.

**Approved**: pending

**Decision**: `localStorage` read and write failures are caught and discarded without logging.

**Rationale**: The source comments say "localStorage unavailable / bad JSON — keep the default" and "ignore persistence failure". The filter is a convenience preference; the in-memory selection keeps the page fully usable, and losing it on reload is the accepted cost.

**Approved**: pending

**Decision**: No `storage` event listener and no shared store across instances.

**Rationale**: The source registers none; the Overview mounts one instance, so per-instance state is sufficient. Cross-tab or cross-instance sync would be a new feature, not part of this contract.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | privacy-and-data |

The hook holds only selection state and persistence; the filtering of rows by environment lives in `OverviewTab`, so logic and presentation are separated. No test exercises `useEnvFilter` directly; the only coverage is `retired-storage.test.ts`, which asserts the `"adh-env-filter"` key survives the retired-storage purge, so hydration filtering and toggle persistence are untested. Both storage failures are caught and discarded without a log or signal. That is deliberate and commented in the source, but it falls short of the "MUST NOT be silently swallowed" bar, hence partial. When storage is unavailable the hook degrades to an in-memory filter that still works. Only environment names are stored, and nothing leaves the device.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
