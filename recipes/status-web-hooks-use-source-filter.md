---
id: 3f2ae6c1-bc07-40ab-b15c-bb4b8c77986b
title: useSourceFilter
domain: agentictoolkit://recipes/status-web-hooks-use-source-filter
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook holding the issue-source multi-select filter, starting with every
  source selected, with a toggle that adds or removes one.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-env-filter
references: []
approved-by: ''
approved-date: ''
---

# useSourceFilter

## Overview

`useSourceFilter` is a client-side React hook (`"use client"`) in the status dashboard that holds which issue sources a filtered pane shows. The selectable sources are the constant `ISSUE_SOURCES` from `lib/issue-sources` (`["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]`), typed as the union `IssueSource`. The selection starts with every source selected, and `toggleSource` adds or removes one source. The state lives only in React component memory: nothing is persisted, and nothing is shared between hook instances.

Its doc comment describes it as "the source-set toggle state shared by every filtered pane (active problems, recently resolved, activity)", extracted "so the three panes can't drift in how they filter." In the current source, `ActivityPanel` is the only consumer. It applies the filter only when more than one source exists (`allSources.length > 1`) and lets through rows with no `platform`.

Use it wherever a view needs an in-memory, per-mount multi-select over the fixed issue-source list. It has no visual surface of its own.

## Behavioral Requirements

### Public operation

- **signature**: `useSourceFilter()` MUST take no arguments and MUST return an object with exactly two fields: `sources` (a `Set<IssueSource>` of the selected sources) and `toggleSource` (a function `(s: IssueSource) => void`).
- **source-type**: The `toggleSource` parameter MUST be typed `IssueSource`, the closed union `"dns" | "http" | "glitchtip" | "vercel" | "cloudflare-pages" | "railway" | "crunchy"`. The type signature is the caller precondition. The hook does no runtime membership check.
- **toggle-identity-unstable**: `toggleSource` MUST be a new function on every render, because the source does not memoise it. A consumer that lists it in a dependency array re-runs on every render.
- **sources-immutability**: Each toggle MUST produce a new `Set` instance and MUST NOT mutate the previous one, so a consumer that compares `sources` by reference sees every change.

### Initial state

- **default-all-selected**: On the first render of each mount, `sources` MUST contain every member of `ISSUE_SOURCES` (7 members), in `ISSUE_SOURCES` order.
- **lazy-seed**: The initial `Set` MUST be built once per mount through a lazy state initializer. Later renders MUST NOT rebuild it.
- **seed-decoupled**: The seeded `Set` MUST be a copy. Mutating it MUST NOT alter the `ISSUE_SOURCES` array, and the reverse also holds.

### Toggle

- **toggle-flip**: `toggleSource(s)` MUST remove `s` from the selection when it is present and add it when it is absent.
- **toggle-order**: A source added by `toggleSource` MUST come after the existing members in the `Set`'s iteration order.
- **toggle-may-empty**: `toggleSource` MUST allow the selection to become empty. There is no minimum of one selected source.
- **toggle-functional-update**: `toggleSource` MUST derive the next selection from the latest state (a functional state update), so several toggles in one event batch compose instead of overwriting each other.
- **toggle-no-error**: `toggleSource` MUST NOT throw and MUST NOT return a value. No operation in the hook can fail.

### Ordering, concurrency and scope

- **single-threaded**: All state updates run on the browser's main JavaScript thread, so toggles cannot interleave. React applies queued updaters in call order.
- **updater-pure**: The state updater MUST have no side effects. React MAY call it twice in development Strict Mode, and each call returns an equivalent `Set` built from the same `prev`.
- **per-instance-state**: Each hook instance MUST hold its own selection. A toggle in one instance MUST NOT change another mounted instance.
- **no-persistence**: The selection MUST NOT be written to or read from any storage (`localStorage`, URL, cookies, server). It resets to all-selected on every remount and every page reload.
- **no-side-effects**: The hook MUST NOT make network requests, log, start timers, or subscribe to anything.

## Appearance

Not applicable — this is an in-memory React state hook, not a visual component.

## States

Not applicable — this is an in-memory React state hook, not a visual component.

## Accessibility

Not applicable — this is an in-memory React state hook, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input / Precondition | Action | Expected |
|----|-------------|----------------------|--------|----------|
| source-filter-001 | signature, default-all-selected | Fresh mount | Render the hook and read the first result | `sources` equals `{dns, http, glitchtip, vercel, cloudflare-pages, railway, crunchy}` (size 7), iterating in that order. `toggleSource` is a function. |
| source-filter-002 | default-all-selected | Fresh mount | Check `sources.has("cloudflare-pages")` | `true`. This matches `row-model.test.ts`, which asserts "useSourceFilter's default seed selects every ISSUE_SOURCES member" via `new Set(ISSUE_SOURCES).has(...)`. |
| source-filter-003 | toggle-flip, sources-immutability | Default state | Call `toggleSource("http")` | `sources` has 6 members and no `http`. It is a different `Set` instance from before. |
| source-filter-004 | toggle-flip, toggle-order | State after source-filter-003 | Call `toggleSource("http")` | `sources` has 7 members and iterates `dns, glitchtip, vercel, cloudflare-pages, railway, crunchy, http`. |
| source-filter-005 | toggle-may-empty | Default state | Call `toggleSource` once for each of the 7 sources | `sources` is an empty `Set` (size 0). No error is thrown. |
| source-filter-006 | toggle-functional-update | Default state | Call `toggleSource("dns")` and `toggleSource("railway")` in one batched event handler | `sources` has 5 members, neither `dns` nor `railway`. |
| source-filter-007 | toggle-functional-update | Default state | Call `toggleSource("vercel")` twice in one batch | `sources` is back to all 7 members (the two toggles cancel). |
| source-filter-008 | seed-decoupled, lazy-seed | Default state | Call `toggleSource("dns")`, then read `ISSUE_SOURCES` | `ISSUE_SOURCES` still has 7 entries and includes `"dns"`. |
| source-filter-009 | per-instance-state | Two components mounted, each calling the hook | Call `toggleSource("glitchtip")` in the first | The first instance has 6 members. The second still has 7. |
| source-filter-010 | no-persistence | Instance toggled to `{dns}` only | Unmount and remount the component | `sources` is all 7 members again. Web Storage is never touched. |
| source-filter-011 | toggle-identity-unstable | Any state | Force a re-render and compare the returned `toggleSource` with the previous render's | Not reference-equal. `sources` IS reference-equal when no toggle occurred. |

## Edge Cases

- **Empty selection**: toggling off every source MUST give an empty `Set`. For `ActivityPanel`, this hides every row that has a known `platform` whenever more than one source exists. Rows whose `platform` is null or missing still show, because the consumer lets them through.
- **Unknown source string**: the `IssueSource` parameter type rules this out at compile time. A value forced in with a cast MUST be added to or removed from the in-memory `Set` like any other value, because the hook does no runtime check. `sources.size` can then exceed 7.
- **Source added to `ISSUE_SOURCES` later**: new mounts MUST include it in the default. An instance that is already mounted does not pick it up until it remounts.
- **Rapid repeated toggles**: each call MUST flip membership once, based on the latest queued state (source-filter-007).
- **Strict Mode double-invoked updater**: the result MUST be the same as a single call, because the updater is pure.
- **Reload or remount**: the selection MUST reset to all-selected. The source persists nothing (see Design Decisions).
- **Server render**: the hook MUST render the default all-selected `Set` on the server. It touches no browser-only API.
- **Null or empty input, timeouts, cancellation, network loss, storage errors**: not applicable. The hook takes no arguments, and its only operation is a synchronous in-memory set update with no I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ISSUE_SOURCES` (from `lib/issue-sources`) | `IssueSource[]` | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]` | The default selection and its initial iteration order. Its comment says it mirrors the server's `src/monitor/issue-sources.ts`. |
| `IssueSource` (from `lib/issue-sources`) | string-literal union | same 7 values | The compile-time domain of `toggleSource`'s argument. |

The hook takes no parameters and reads no environment variables, settings keys or storage.

## Deep Linking

Not applicable: the hook never reads or writes the URL, so the selection cannot be reached by a link.

## Localization

Not applicable: the hook has no user-facing strings. Display labels live in `SOURCE_LABEL`, which the consumer renders.

## Accessibility Options

Not applicable: the hook renders nothing and reads no display preference.

## Feature Flags

Not applicable: no flag gates the hook. It always returns a selection seeded from `ISSUE_SOURCES`.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook holds only a set of source identifiers in component memory. It stores nothing and transmits nothing.

## Logging

Not applicable: the hook makes no log calls and has no failure path to log.

## Platform Notes

- **React/Web** (source): `packages/web/packages/status-web/src/hooks/use-source-filter.ts`. It uses `useState` with a lazy initializer (`() => new Set(ISSUE_SOURCES)`) and a plain arrow function for `toggleSource`, with no `useCallback`. The updater copies `prev` into a new `Set` before flipping membership, so React sees a new reference. The `"use client"` directive marks it as a Next.js client module. Its sibling `useEnvFilter` adds `localStorage` persistence and a memoised toggle. This hook has neither.
- **SwiftUI**: Start from a `@MainActor @Observable` model with `var sources: Set<IssueSource>` seeded from `IssueSource.allCases` (make `IssueSource` a `String`-backed `CaseIterable` enum) and a `toggle(_:)` method. Use `@State` for per-view ownership so each view gets its own instance. Swift `Set` is unordered, so keep an ordered array, or sort by `allCases` index, if iteration order matters.
- **Compose**: Start from `remember { mutableStateOf(IssueSource.entries.toSet()) }`, or a `ViewModel` holding `MutableStateFlow<Set<IssueSource>>`. Update with `update { if (s in it) it - s else it + s }` so each change produces a new immutable set. Kotlin's `setOf`/`toSet` keep insertion order (`LinkedHashSet`), which matches the source.
- **AppKit / UIKit**: A `@MainActor` model class with `@Published var sources: Set<IssueSource>` (Combine) or a delegate callback, seeded from `IssueSource.allCases`. It has no persistence, matching the source.
- **WinUI 3**: Start from a view-model class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject` with `[ObservableProperty]`). Expose an `IssueSource` enum, an `IReadOnlySet<IssueSource> Sources` property seeded from `Enum.GetValues<IssueSource>()`, and a `ToggleSource(IssueSource s)` method or `RelayCommand<IssueSource>`. Replace the whole set on each toggle (`var next = new HashSet<IssueSource>(Sources); if (!next.Remove(s)) next.Add(s); Sources = next;`) so `PropertyChanged` fires and bindings that compare by reference update, matching the source's copy-on-write. Bind each source's `ToggleButton` or `CheckBox` `IsChecked` through a converter or a per-item wrapper, or use an `ObservableCollection` of item view-models each with a bool `IsSelected`. `HashSet<T>` does not guarantee order, so use a `List<IssueSource>` with membership checks if order matters. Everything runs on the UI thread (`DispatcherQueue`), so no `Task`/`async`, `System.Text.Json` or `Windows.Storage` is needed. The source persists nothing, so a port MUST NOT add `ApplicationData.LocalSettings` persistence if it is to behave identically.

## Design Decisions

**Decision**: Start with every source selected, and allow the selection to become empty.

**Rationale**: The doc comment states it "starts with all sources selected; toggling one adds/removes it." No minimum is enforced. `ActivityPanel` keeps the result usable by bypassing the filter when only one source exists, and by letting through rows that have no platform.

**Approved**: pending

**Decision**: The selection is in-memory only and per instance, with no persistence.

**Rationale**: The source uses bare `useState` with no storage calls, so the choice resets on reload. This differs from the sibling `useEnvFilter`, which persists to `localStorage`. A port that adds persistence changes observable behavior.

**Approved**: pending

**Decision**: Extract the toggle into a shared hook even though only one pane uses it today.

**Rationale**: The doc comment says the extraction exists "so the three panes can't drift in how they filter" and names active problems, recently resolved and activity. In the given source only `ActivityPanel` imports it, so the comment describes the intended set of consumers, not the current one. The hook's own contract is unaffected.

**Approved**: pending

**Decision**: `toggleSource` is not memoised.

**Rationale**: The source defines it as a plain arrow function on each render. Its one consumer passes it only to click handlers, never to a dependency array, so the changing identity has no observable effect there.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | privacy-and-data |

The hook holds only selection state. Row filtering and label rendering live in `ActivityPanel`, so state and presentation are kept apart. No test renders `useSourceFilter` directly. The only related assertion is in `row-model.test.ts`, which checks the default seed through `new Set(ISSUE_SOURCES)` rather than through the hook, so toggle behavior is untested. The hook has no failure path, so there is no error to swallow. It keeps only source identifiers in memory and sends nothing anywhere.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
