---
id: dcfe8ed6-2129-44ea-a084-eb30b640c0e3
title: Environment Filter
domain: agentictoolkit://cookbook/status/dashboard/state/env-filter
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State holding the Overview's selected-environments filter, defaulting
  to all and persisted to per-browser storage.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/state/activity-ttl
references: []
approved-by: ''
approved-date: ''
---

# Environment Filter

## Overview

Environment Filter is client-side state that holds which deployment environments the status dashboard's Overview shows. The selectable environments are the constant `ENVIRONMENTS` (`["production", "staging", "testing"]`). The selection starts with every environment selected (no filter), is hydrated once from persistent per-browser storage after the initial state settles so the pre-hydration render and first paint match, and every toggle is written back to storage under the key `"adh-env-filter"` so the choice survives reloads. The Overview treats "every environment selected" (`envs.size === all.length`) as unfiltered.

Use it wherever a view needs a persisted, per-browser multi-select over the fixed environment list. It holds no visual surface of its own.

## Behavioral Requirements

### Public operation

- **signature**: Environment Filter MUST take no arguments and MUST return an object with exactly three fields: `envs` (a set of selected environment names), `all` (an ordered list of every environment), and `toggle` (a function taking one environment name and returning nothing).
- **all-list**: The `all` field MUST be the `ENVIRONMENTS` constant, in its declared order `production`, `staging`, `testing`, and MUST be the same list instance on every read.
- **toggle-identity**: The `toggle` function MUST keep the same identity across the life of one instance, so consumers MAY depend on that stability without causing needless re-runs.
- **envs-immutability**: Each state change MUST produce a new set instance; the previous set MUST NOT be mutated, so consumers comparing `envs` by reference observe every change.

### Initial state and hydration

- **default-all-selected**: Before hydration, Environment Filter MUST return `envs` containing every entry of `ENVIRONMENTS`, regardless of what storage holds.
- **deferred-hydration**: Environment Filter MUST read storage only after the initial state is established, exactly once per instance, so a pre-hydration render and the first paint both show the default.
- **storage-key**: Environment Filter MUST read and write the storage key `"adh-env-filter"`.
- **absent-value-keeps-default**: When the stored value is missing (a read that returns nothing) or is the empty string, hydration MUST leave `envs` at the default.
- **array-hydration**: When the stored value parses as a JSON array, hydration MUST replace `envs` with a set of the array's elements that are strings and members of `ENVIRONMENTS`, in the array's order.
- **invalid-entries-dropped**: Hydration MUST silently drop array elements that are not strings or not members of `ENVIRONMENTS`.
- **filtered-to-empty**: When filtering leaves no valid elements (including a stored empty array `[]`), hydration MUST set `envs` to an empty set (nothing selected), not fall back to the default.
- **duplicates-collapse**: Duplicate names in the stored array MUST collapse to one member, because the result is a set.
- **non-array-keeps-default**: When the stored value parses as valid JSON that is not an array (an object, number, string, boolean or null), hydration MUST leave `envs` at the default.
- **read-failure-keeps-default**: When the storage read throws or the stored value is not valid JSON, hydration MUST catch the exception, leave `envs` at the default, and MUST NOT propagate the error or log it.

### Toggle

- **toggle-flip**: `toggle(env)` MUST remove `env` from the selection when it is present and add it when it is absent.
- **toggle-order**: A name added by `toggle` MUST be appended after the existing members in the set's iteration order.
- **toggle-unvalidated**: `toggle` MUST NOT validate `env` against `ENVIRONMENTS`; an unknown name is added to the in-memory set and persisted like any other. Only hydration filters to `ENVIRONMENTS`, so an unknown name is dropped on the next hydration. Callers pass names taken from `all`, which is the precondition the Overview meets.
- **toggle-may-empty**: `toggle` MUST allow the selection to become empty; there is no minimum of one selected environment.
- **toggle-functional-update**: `toggle` MUST derive the next selection from the latest state, so several toggles made together compose rather than overwrite each other.
- **toggle-persist**: After computing the next selection, `toggle` MUST write it to `"adh-env-filter"` as a JSON array of the set's members in iteration order (for example `["production","testing"]`).
- **write-failure-ignored**: When the storage write throws (storage unavailable, quota exceeded), `toggle` MUST catch the exception, MUST still apply the new in-memory selection, and MUST NOT propagate or log the error.

### Ordering, concurrency and scope

- **single-threaded**: All reads, writes and state updates run on a single execution thread; hydration and toggles cannot interleave, and hydration completes before a later user event is handled.
- **write-inside-updater**: The storage write happens inside the state-update step itself. That step MAY run more than once for the same logical update; a repeat write stores the same value, so the effect is idempotent.
- **per-instance-state**: Each instance MUST hold its own selection; a toggle in one instance MUST NOT update another active instance until that instance is recreated and re-hydrates.
- **no-cross-tab-sync**: Environment Filter MUST NOT listen for cross-tab storage-change notifications; a change made in another tab is not reflected until this instance is recreated.
- **no-other-side-effects**: Environment Filter MUST NOT perform network requests, logging, timers or any storage access other than one read per instance and one write per toggle.

## Appearance

Not applicable — this is state backed by persistent storage, not a visual component.

## States

Not applicable — this is state backed by persistent storage, not a visual component.

## Accessibility

Not applicable — this is state backed by persistent storage, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input / Precondition | Action | Expected |
|----|-------------|----------------------|--------|----------|
| env-filter-001 | signature, default-all-selected, all-list | Empty storage | Create the state; read the initial result | `envs` equals `{production, staging, testing}`; `all` is `["production","staging","testing"]`; `toggle` is a function |
| env-filter-002 | deferred-hydration, array-hydration, storage-key | `"adh-env-filter"` = `["production"]` | Create the state; capture the initial result; let hydration run | Initial `envs` = all three; after hydration `envs` = `{production}` |
| env-filter-003 | absent-value-keeps-default | `"adh-env-filter"` = `""` (empty string) | Create the state; let hydration run | `envs` stays all three; the value is never parsed |
| env-filter-004 | invalid-entries-dropped, duplicates-collapse | `"adh-env-filter"` = `["staging", 7, "prod", "staging", null]` | Create the state; let hydration run | `envs` = `{staging}` (size 1) |
| env-filter-005 | filtered-to-empty | `"adh-env-filter"` = `[]` | Create the state; let hydration run | `envs` is an empty set |
| env-filter-006 | filtered-to-empty | `"adh-env-filter"` = `["qa","dev"]` | Create the state; let hydration run | `envs` is an empty set (not the default) |
| env-filter-007 | non-array-keeps-default | `"adh-env-filter"` = `{"production":true}` | Create the state; let hydration run | `envs` stays all three |
| env-filter-008 | read-failure-keeps-default | `"adh-env-filter"` = `{not json` | Create the state; let hydration run | No exception escapes; `envs` stays all three |
| env-filter-009 | read-failure-keeps-default | The storage read throws a security error | Create the state; let hydration run | No exception escapes; `envs` stays all three |
| env-filter-010 | toggle-flip, toggle-persist, envs-immutability | Default state (all three) | Call `toggle("staging")` | `envs` = `{production, testing}` and is a different set instance; storage holds `["production","testing"]` |
| env-filter-011 | toggle-flip, toggle-order, toggle-persist | State after env-filter-010 | Call `toggle("staging")` | `envs` = `{production, testing, staging}`; storage holds `["production","testing","staging"]` |
| env-filter-012 | toggle-may-empty | `envs` = `{production}` | Call `toggle("production")` | `envs` is empty; storage holds `[]` |
| env-filter-013 | toggle-functional-update | Default state | Call `toggle("production")` and `toggle("testing")` together | `envs` = `{staging}`; storage holds `["staging"]` |
| env-filter-014 | write-failure-ignored | The storage write throws a quota-exceeded error | Call `toggle("testing")` | No exception escapes; `envs` = `{production, staging}` |
| env-filter-015 | toggle-unvalidated | Default state | Call `toggle("qa")`; then recreate the state and let hydration run | Before recreation `envs` has 4 members including `qa`, storage holds `["production","staging","testing","qa"]`; after recreation `envs` = all three |
| env-filter-016 | toggle-identity, all-list | Any state | Call `toggle` to force a state update; compare the returned `toggle` and `all` with the previous result's | Both are reference-equal to the previous values |
| env-filter-017 | storage-key | Storage holds `"adh-env-filter"` = `["production"]` | Run a routine that purges retired storage keys | The key survives unchanged; a companion test asserts this ("leaves keys the app still uses alone") |

## Edge Cases

- **Missing key**: The read returns nothing; Environment Filter MUST keep the default (all selected).
- **Empty string stored**: An empty string is treated as absent; Environment Filter MUST keep the default without parsing.
- **Empty array stored**: `[]` is a valid array; Environment Filter MUST hydrate to an empty selection. A consumer that treats "none selected" as "show nothing" shows nothing after reload.
- **Only unknown names stored** (for example after an environment is removed from `ENVIRONMENTS`): Environment Filter MUST hydrate to an empty selection, not the default.
- **Non-array JSON** (`null`, a number, an object, a quoted string): Environment Filter MUST keep the default.
- **Malformed JSON**: the parse exception MUST be caught and the default kept.
- **Storage unavailable** (disabled cookies/site data, sandboxed frame, private mode that throws): both the read and every write MUST be caught; Environment Filter MUST keep working in memory only, and the choice is lost on reload.
- **Quota exceeded on write**: the in-memory toggle MUST still apply; the stored value stays at its previous content.
- **Unknown environment passed to `toggle`**: the name MUST be accepted in memory and persisted, then dropped by the next hydration. While it is present, `envs.size` can equal `all.length` without every environment being selected, which misleads a consumer's "unfiltered" check such as the Overview's.
- **Toggle before hydration**: cannot occur in practice; hydration completes before a later user event is handled, and all code is single-threaded.
- **Several instances active**: each MUST keep its own selection; the last writer's value is what the next instance hydrates from.
- **Another tab changes the value**: Environment Filter SHOULD NOT reflect it until recreated, because it registers no cross-tab change listener (rationale in Design Decisions).
- **Pre-hydration render**: storage is never touched before hydration, so Environment Filter MUST report the default without referencing storage.
- **Timeouts, cancellation, network loss**: not applicable; Environment Filter performs only synchronous storage calls and no network I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ENVIRONMENTS` | ordered list of 3 strings | `["production", "staging", "testing"]` | The complete selectable set, the default selection, and the allow-list hydration filters against. Changing it changes all three. |
| Storage key | string constant | `"adh-env-filter"` | The storage key read on creation and written on toggle. Not configurable by callers. |
| Persistent per-browser storage | ambient facility | platform-provided | Injected implicitly through the runtime; tests install their own implementation. |

Environment Filter takes no parameters and reads no environment variables or settings keys.

## Deep Linking

Not applicable: Environment Filter reads and writes only persistent per-browser storage and never reads or writes the URL, so the filter is not addressable by link.

## Localization

Not applicable: Environment Filter contains no user-facing strings; the environment names are data identifiers whose display is the consumer's concern.

## Accessibility Options

Not applicable: Environment Filter renders nothing and does not read any display preference.

## Feature Flags

Not applicable: Environment Filter is not gated by any flag; it always returns a selection.

## Analytics

Not applicable: Environment Filter emits no analytics events.

## Privacy

Not applicable: Environment Filter stores only a list of environment names (a UI preference) in the browser's own persistent storage; it collects no personal data and transmits nothing.

## Logging

Not applicable: Environment Filter makes no log calls; both caught exceptions are discarded without logging.

## Platform Notes

- **React/Web** (source): `packages/web/packages/status-web/src/hooks/use-env-filter.ts`. `useState` with a lazy initializer seeds the default `Set`; a mount-only `useEffect` hydrates from `localStorage` (with an eslint suppression for `react-hooks/set-state-in-effect`, justified inline as one-shot external-store sync); `useCallback` with an empty dependency list keeps `toggle` stable. The `"use client"` directive marks it as a Next.js client module. The storage write sits inside the `setEnvs` updater, and React MAY invoke that updater twice in development Strict Mode — the one React-specific quirk to drop in a port. `envs` is typed `Set<string>`, `all` is `readonly string[]`, and `toggle` is `(env: string) => void`.
- **SwiftUI**: Start from an `@Observable` model (or `@AppStorage` with a `String` holding the JSON array) exposing `envs: Set<String>` and `toggle(_:)`, persisting to `UserDefaults`. There is no pre-hydration render, so hydration can happen in the initializer; keep the same allow-list filter and "empty array hydrates to empty set" behavior. Mark the model `@MainActor` to match the single-threaded source.
- **Compose**: Start from a `ViewModel` holding `MutableStateFlow<Set<String>>`, persisted with Jetpack DataStore (`stringSetPreferencesKey`) or `SharedPreferences.getStringSet`. DataStore is asynchronous, so the default-then-hydrate sequence mirrors the source naturally; a `Set` there has no guaranteed order, which differs from the source's insertion-ordered JSON array.
- **AppKit / UIKit**: A plain `@MainActor` model class backed by `UserDefaults.standard` (`array(forKey:)` then filter to `[String]` members of the environment list), posting a change notification or using Combine `@Published` so the view controller updates.
- **WinUI 3**: Start from a view-model class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`) exposing a `HashSet<string>` (or `ObservableCollection<string>` for direct binding to `ToggleButton`/`CheckBox` items via `IsChecked`), a `static readonly string[] All`, and a `Toggle(string env)` method or `RelayCommand<string>`. Persist to `Windows.Storage.ApplicationData.Current.LocalSettings.Values["adh-env-filter"]` as a string produced by `System.Text.Json.JsonSerializer.Serialize(set)` and read with `JsonSerializer.Deserialize<JsonElement>`, checking `ValueKind == JsonValueKind.Array` and keeping only `String` elements contained in `All`, so non-array JSON keeps the default. Wrap both calls in `try`/`catch` (`JsonException`, `COMException`) to match the source's swallow-and-keep-default behavior. There is no SSR, so load in the constructor or `OnNavigatedTo`, but keep the default when nothing valid is stored. `HashSet<string>` does not preserve insertion order; use a `List<string>` with membership checks if the persisted order matters. All access runs on the UI thread (`DispatcherQueue`), matching the single-threaded source; no `Task`/`async` is needed because `LocalSettings` is synchronous.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-env-filter.ts` |

## Design Decisions

**Decision**: Start at the default (all selected) and hydrate from storage after the initial state settles, rather than reading storage while establishing that initial state.

**Rationale**: The source comment states it keeps "SSR/first-paint match": a server render has no `localStorage`, so reading it during that render would make the client's first render differ from the server's HTML. The Activity TTL and Build Progress concepts cite this concept as the pattern they mirror.

**Approved**: pending

**Decision**: Hydration filters stored names against `ENVIRONMENTS` but `toggle` does not validate its argument.

**Rationale**: Stored data is untrusted (older builds, hand edits, a removed environment), so it is filtered on read. `toggle` is only called with names from `all` by its one consumer, so the source leaves the check out; the filter on the next hydration repairs any stray name.

**Approved**: pending

**Decision**: A stored array whose entries are all invalid, or an empty array, hydrates to an empty selection rather than the default.

**Rationale**: The source applies the filter result directly whenever the parsed value is an array; only a missing, non-array or unparseable value falls back to the default. A port MUST keep this distinction to behave identically after reload.

**Approved**: pending

**Decision**: Storage read and write failures are caught and discarded without logging.

**Rationale**: The source comments say "localStorage unavailable / bad JSON — keep the default" and "ignore persistence failure". The filter is a convenience preference; the in-memory selection keeps the page fully usable, and losing it on reload is the accepted cost.

**Approved**: pending

**Decision**: No cross-tab change listener and no shared store across instances.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
