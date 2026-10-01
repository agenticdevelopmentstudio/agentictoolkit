---
id: 3f2ae6c1-bc07-40ab-b15c-bb4b8c77986b
title: Source Filter
domain: agentictoolkit://cookbook/status/dashboard/state/source-filter
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State holding the issue-source multi-select filter, starting with every
  source selected, with a toggle that adds or removes one.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/state/env-filter
references: []
approved-by: ''
approved-date: ''
---

# Source Filter

## Overview

Source Filter is client-only state that holds which issue sources a filtered pane shows. The selectable sources are a fixed list of seven values (dns, http, glitchtip, vercel, cloudflare-pages, railway, crunchy). The selection starts with every source selected, and a toggle operation adds or removes one source. The state lives only in memory for as long as it is in use: nothing is persisted, and nothing is shared between separate uses.

It is described as the source-set toggle state shared by every filtered pane (active problems, recently resolved, activity), extracted so the three panes can't drift in how they filter. In the current source, the activity panel is the only consumer. It applies the filter only when more than one source exists and lets through rows with no platform.

Use it wherever a view needs an in-memory, per-use multi-select over the fixed issue-source list. It has no visual surface of its own.

## Behavioral Requirements

### Public operation

- **signature**: Source Filter MUST take no arguments and MUST return an object with exactly two fields: `sources` (the set of selected sources) and a toggle operation that takes one source and returns nothing.
- **source-type**: The toggle operation's parameter MUST be one of the seven fixed source values. The type signature is the caller precondition. Source Filter does no runtime membership check.
- **toggle-identity-unstable**: The toggle operation MUST be a new function value each time Source Filter is used, because the source does not give it a stable identity. A consumer that lists it in a dependency list re-runs every time.
- **sources-immutability**: Each toggle MUST produce a new set instance and MUST NOT mutate the previous one, so a consumer that compares `sources` by reference sees every change.

### Initial state

- **default-all-selected**: On the first use of each mount, `sources` MUST contain every one of the seven fixed sources, in their defined order.
- **lazy-seed**: The initial set MUST be built once per use, computed lazily rather than on every render. Later renders MUST NOT rebuild it.
- **seed-decoupled**: The seeded set MUST be a copy. Mutating it MUST NOT alter the fixed source list, and the reverse also holds.

### Toggle

- **toggle-flip**: The toggle operation MUST remove a source from the selection when it is present and add it when it is absent.
- **toggle-order**: A source added by the toggle operation MUST come after the existing members in the set's iteration order.
- **toggle-may-empty**: The toggle operation MUST allow the selection to become empty. There is no minimum of one selected source.
- **toggle-functional-update**: The toggle operation MUST derive the next selection from the latest state, so several toggles in one batch of updates compose instead of overwriting each other.
- **toggle-no-error**: The toggle operation MUST NOT throw and MUST NOT return a value. No operation in Source Filter can fail.

### Ordering, concurrency and scope

- **single-threaded**: All state updates run on a single execution thread, so toggles cannot interleave. Updates apply in the order they are issued.
- **updater-pure**: The state update MUST have no side effects. The environment MAY apply it more than once for the same input, and each application returns an equivalent set built from the same starting state.
- **per-instance-state**: Each use MUST hold its own selection. A toggle in one use MUST NOT change another concurrent use.
- **no-persistence**: The selection MUST NOT be written to or read from any storage. It resets to all-selected on every remount and every reload.
- **no-side-effects**: Source Filter MUST NOT make network requests, log, start timers, or subscribe to anything.

## Appearance

Not applicable — this is an in-memory state concept, not a visual component.

## States

Not applicable — this is an in-memory state concept, not a visual component.

## Accessibility

Not applicable — this is an in-memory state concept, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input / Precondition | Action | Expected |
|----|-------------|----------------------|--------|----------|
| source-filter-001 | signature, default-all-selected | Fresh mount | Use Source Filter and read the first result | `sources` equals `{dns, http, glitchtip, vercel, cloudflare-pages, railway, crunchy}` (size 7), iterating in that order. The toggle operation is a function. |
| source-filter-002 | default-all-selected | Fresh mount | Check whether `sources` contains `"cloudflare-pages"` | `true` |
| source-filter-003 | toggle-flip, sources-immutability | Default state | Call the toggle operation with `"http"` | `sources` has 6 members and no `http`. It is a different set instance from before. |
| source-filter-004 | toggle-flip, toggle-order | State after source-filter-003 | Call the toggle operation with `"http"` | `sources` has 7 members and iterates `dns, glitchtip, vercel, cloudflare-pages, railway, crunchy, http`. |
| source-filter-005 | toggle-may-empty | Default state | Call the toggle operation once for each of the 7 sources | `sources` is an empty set (size 0). No error is thrown. |
| source-filter-006 | toggle-functional-update | Default state | Call the toggle operation with `"dns"` and with `"railway"` in one batch of updates | `sources` has 5 members, neither `dns` nor `railway`. |
| source-filter-007 | toggle-functional-update | Default state | Call the toggle operation with `"vercel"` twice in one batch | `sources` is back to all 7 members (the two toggles cancel). |
| source-filter-008 | seed-decoupled, lazy-seed | Default state | Call the toggle operation with `"dns"`, then read the fixed source list | The fixed source list still has 7 entries and includes `"dns"`. |
| source-filter-009 | per-instance-state | Two separate uses | Call the toggle operation with `"glitchtip"` in the first | The first use has 6 members. The second still has 7. |
| source-filter-010 | no-persistence | One use toggled to `{dns}` only | Stop using it and start again | `sources` is all 7 members again. No storage is ever touched. |
| source-filter-011 | toggle-identity-unstable | Any state | Force a re-render and compare the returned toggle operation with the previous one | Not reference-equal. `sources` IS reference-equal when no toggle occurred. |

## Edge Cases

- **Empty selection**: toggling off every source MUST give an empty set. For the activity panel, this hides every row that has a known `platform` whenever more than one source exists. Rows whose `platform` is null or missing still show, because the consumer lets them through.
- **Unknown source value**: the source type rules this out at compile time. A value forced in some other way MUST be added to or removed from the in-memory set like any other value, because Source Filter does no runtime check. The set's size can then exceed 7.
- **Source added to the fixed list later**: new mounts MUST include it in the default. A use that is already mounted does not pick it up until it starts again.
- **Rapid repeated toggles**: each call MUST flip membership once, based on the latest queued state (source-filter-007).
- **Update applied more than once for the same input**: the result MUST be the same as a single application, because the update has no side effects.
- **Reload or remount**: the selection MUST reset to all-selected. Source Filter persists nothing (see Design Decisions).
- **Server render**: Source Filter MUST render the default all-selected set on a server-rendering pass. It touches no client-only API.
- **Null or empty input, timeouts, cancellation, network loss, storage errors**: not applicable. Source Filter takes no arguments, and its only operation is a synchronous in-memory set update with no I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Fixed source list | list of source values | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]` | The default selection and its initial iteration order. Mirrors the server's own issue-source list. |
| Source type | closed enumeration | same 7 values | The type-checked domain of the toggle operation's argument. |

Source Filter takes no parameters and reads no environment variables, settings keys or storage.

## Deep Linking

Not applicable: Source Filter never reads or writes the URL, so the selection cannot be reached by a link.

## Localization

Not applicable: Source Filter has no user-facing strings. Display labels live with the consumer that renders them.

## Accessibility Options

Not applicable: Source Filter renders nothing and reads no display preference.

## Feature Flags

Not applicable: no flag gates Source Filter. It always returns a selection seeded from the fixed source list.

## Analytics

Not applicable: Source Filter emits no analytics events.

## Privacy

Not applicable: Source Filter holds only a set of source identifiers in memory. It stores nothing and transmits nothing.

## Logging

Not applicable: Source Filter makes no log calls and has no failure path to log.

## Platform Notes

- **React/Web** (source): `packages/web/packages/status-web/src/hooks/use-source-filter.ts`. It uses `useState` with a lazy initializer (`() => new Set(ISSUE_SOURCES)`) and a plain arrow function for `toggleSource`, with no `useCallback`. The updater copies `prev` into a new `Set` before flipping membership, so React sees a new reference; React MAY call that updater twice in development Strict Mode, which is why the update itself must stay pure. The `"use client"` directive marks it as a Next.js client module. Its sibling `useEnvFilter` adds `localStorage` persistence and a memoised toggle; this hook has neither. `row-model.test.ts` asserts the default seed ("useSourceFilter's default seed selects every ISSUE_SOURCES member") via `new Set(ISSUE_SOURCES).has(...)`, independent of the hook itself.
- **SwiftUI**: Start from a `@MainActor @Observable` model with `var sources: Set<IssueSource>` seeded from `IssueSource.allCases` (make `IssueSource` a `String`-backed `CaseIterable` enum) and a `toggle(_:)` method. Use `@State` for per-view ownership so each view gets its own instance. Swift `Set` is unordered, so keep an ordered array, or sort by `allCases` index, if iteration order matters.
- **Compose**: Start from `remember { mutableStateOf(IssueSource.entries.toSet()) }`, or a `ViewModel` holding `MutableStateFlow<Set<IssueSource>>`. Update with `update { if (s in it) it - s else it + s }` so each change produces a new immutable set. Kotlin's `setOf`/`toSet` keep insertion order (`LinkedHashSet`), which matches the source.
- **AppKit / UIKit**: A `@MainActor` model class with `@Published var sources: Set<IssueSource>` (Combine) or a delegate callback, seeded from `IssueSource.allCases`. It has no persistence, matching the source.
- **WinUI 3**: Start from a view-model class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject` with `[ObservableProperty]`). Expose an `IssueSource` enum, an `IReadOnlySet<IssueSource> Sources` property seeded from `Enum.GetValues<IssueSource>()`, and a `ToggleSource(IssueSource s)` method or `RelayCommand<IssueSource>`. Replace the whole set on each toggle (`var next = new HashSet<IssueSource>(Sources); if (!next.Remove(s)) next.Add(s); Sources = next;`) so `PropertyChanged` fires and bindings that compare by reference update, matching the source's copy-on-write. Bind each source's `ToggleButton` or `CheckBox` `IsChecked` through a converter or a per-item wrapper, or use an `ObservableCollection` of item view-models each with a bool `IsSelected`. `HashSet<T>` does not guarantee order, so use a `List<IssueSource>` with membership checks if order matters. Everything runs on the UI thread (`DispatcherQueue`), so no `Task`/`async`, `System.Text.Json` or `Windows.Storage` is needed. The source persists nothing, so a port MUST NOT add `ApplicationData.LocalSettings` persistence if it is to behave identically.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-source-filter.ts` |

## Design Decisions

**Decision**: Start with every source selected, and allow the selection to become empty.

**Rationale**: The source is documented as starting with all sources selected, toggling one adds or removes it. No minimum is enforced. The activity panel keeps the result usable by bypassing the filter when only one source exists, and by letting through rows that have no platform.

**Approved**: pending

**Decision**: The selection is in-memory only and per use, with no persistence.

**Rationale**: The source uses bare in-memory state with no storage calls, so the choice resets on reload. This differs from the sibling Environment Filter, which persists its selection to storage (on the web platform, `localStorage`). A port that adds persistence changes observable behavior.

**Approved**: pending

**Decision**: Extract the toggle into a shared concept even though only one pane uses it today.

**Rationale**: The source is documented as existing so the three panes can't drift in how they filter, naming active problems, recently resolved and activity. In the given source only the activity panel imports it, so the documentation describes the intended set of consumers, not the current one. Source Filter's own contract is unaffected.

**Approved**: pending

**Decision**: The toggle operation is not memoised.

**Rationale**: The source defines it as a plain function created on each render. Its one consumer passes it only to interaction handlers, never to a dependency list, so the changing identity has no observable effect there.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
