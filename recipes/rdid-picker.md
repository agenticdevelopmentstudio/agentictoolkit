---
id: bd0d7595-f186-4aaf-bb45-5c733cfdb03d
title: RdidPicker
domain: agentictoolkit://recipes/rdid-picker
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Modal, debounced, keyboard-driven search over the identifier registry that
  hands the caller one whole RdidOption, built on CommandPalette.
platforms:
- typescript
- web
tags:
- component
- picker
- search
- ui
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# RdidPicker

## Overview

`RdidPicker` (`@agentic-toolkit/adh-ui`) is a modal search picker for the
identifier registry: it opens a `CommandPalette` over one field, debounces
what the caller types, calls a caller-supplied `search` function, and hands
back the whole matched `RdidOption` (`rdid`, `entityType`, `entityId`) when
one is chosen. It is built directly on `CommandPalette`
(`@agenticdevelopertoolkit/ui/blocks/command-palette`) rather than beside it,
because a modal over one field with a keyboard-driven, first-result-preselected
list is already the interaction `CommandPalette` provides; `RdidPicker`
contributes only what a search-backed instance of that shape still needs: the
debounce, the abort-on-supersede, the group/label/placeholder wiring, and
resetting itself when closed. It owns no opinion about which entities are
searchable — the caller's `search` function decides that, so restricting the
picker (to one ecosystem, say) is the caller's filter, not a prop this
component interprets.

## Behavioral Requirements

- **renders-single-command-palette**: The component MUST render exactly one
  `CommandPalette`, passing it `open`, `onOpenChange`, `query`,
  `onQueryChange`, one result group, `ariaLabel`, `placeholder`, `loading`,
  `error`, and `emptyLabel`, and MUST implement no dialog, listbox, or
  keyboard handling of its own.
- **resets-on-close**: When `open` transitions to `false`, the component MUST
  clear `query` to `""`, `options` to `[]`, `error` to `null`, and `loading`
  to `false`.
- **skips-search-for-empty-query**: While `open` is `true` and the trimmed
  `query` is the empty string, the component MUST set `options` to `[]`,
  `loading` to `false`, and `error` to `null`, and MUST NOT call `search`.
- **sets-loading-before-debounce-elapses**: While `open` is `true` and the
  trimmed `query` is non-empty, the component MUST set `loading` to `true`
  immediately, before the debounce delay elapses.
- **debounces-search-call**: The component MUST wait `debounceMs`
  milliseconds (default `200`) after the last `query` change before invoking
  `search` with the trimmed value of `query`, never the raw, untrimmed
  string.
- **aborts-superseded-search**: When `open`, `query`, or `debounceMs` changes
  while a previously scheduled or in-flight `search` call has not yet
  settled, the component MUST abort that call's `AbortSignal` and MUST cancel
  its pending debounce timer.
- **ignores-aborted-search-results**: When a `search` call's promise settles
  after its `AbortSignal` has been aborted, the component MUST NOT update
  `options`, `error`, or `loading` from that settlement.
- **populates-options-on-success**: When a non-superseded `search` call
  resolves, the component MUST set `options` to the resolved array, MUST set
  `error` to `null`, and MUST set `loading` to `false`.
- **surfaces-search-rejection**: When a non-superseded `search` call rejects,
  the component MUST set `error` to the rejection's `message` when the
  rejection is an `Error`, or to the literal string `"Search failed"`
  otherwise, MUST set `options` to `[]`, and MUST set `loading` to `false`.
- **calls-latest-search-implementation**: Each debounced invocation MUST call
  the most recently supplied `search` function, even when the debounce effect
  has not re-run since `search`'s identity last changed.
- **passes-full-option-to-onPick**: Selecting a result MUST invoke `onPick`
  with that result's complete option object (`rdid`, `entityType`,
  `entityId`), not the `rdid` string alone.
- **closes-on-pick**: Selecting a result MUST close the picker. `RdidPicker`
  triggers no close of its own on selection — closing is `CommandPalette`'s
  `run()`, which calls `onOpenChange(false)` before invoking the item's
  `onSelect` (and therefore `onPick`).
- **labels-group-by-entity-type**: The single result group's label MUST read
  `<entityTypeLabel> addresses` when `entityTypeLabel` is supplied, and MUST
  read `Addresses` when it is not.
- **derives-default-placeholder**: When no `placeholder` prop is given, the
  search field's placeholder MUST read `Search <entityTypeLabel> addresses…`
  when `entityTypeLabel` is supplied, and `Search addresses…` when it is not.
- **derives-empty-label-from-query**: The empty-results label passed to
  `CommandPalette` MUST read `Start typing an address` while the trimmed
  `query` is empty, and MUST read `No matching address` once the trimmed
  `query` is non-empty.
- **defaults-title-and-aria-label**: The component MUST default `title` to
  `Choose an address` and MUST pass `title` through as `CommandPalette`'s
  `ariaLabel`.
- **renders-each-result-by-rdid-with-badge**: Each item in the rendered group
  MUST use the option's `rdid` as both its item id and its label, and MUST
  show the option's `entityType` as the item's badge.

## Appearance

Not applicable: `rdid-picker.tsx` renders no markup of its own — its return
statement is a single `<CommandPalette>` element. Corner radius, padding,
font, background, foreground, border, shadow, and min/max size are all owned
by the composed `CommandPalette` (and the `Dialog` it renders into), not by
this component.

## States

| State | Appearance change |
|-------|------------------|
| Closed (`open=false`) | `CommandPalette` not shown; internal `query`/`options`/`error`/`loading` are reset |
| Open, query empty | `emptyLabel` reads "Start typing an address"; `loading=false`, `error=null`, `options=[]` |
| Open, query non-empty, debounce/search pending | `loading=true` passed to `CommandPalette` (shown beside any still-displayed prior `options`, per `CommandPalette`'s own loading treatment) |
| Open, search resolved with results | `options` populated; each renders as a group item keyed by `rdid` |
| Open, search resolved with zero results | `options=[]`; `emptyLabel` reads "No matching address" |
| Open, search rejected | `error` set to the rejection message (or "Search failed"); `options=[]`; `loading=false` |

## Accessibility

- `RdidPicker` contributes one accessible name: `title` (default "Choose an
  address") is passed straight through as `CommandPalette`'s `ariaLabel`,
  which names both the dialog's visually-hidden `DialogTitle` and the search
  field/listbox for assistive tech (per `command-palette.tsx`).
- All other accessibility mechanics are inherited by composition, not
  implemented in `rdid-picker.tsx`: the search field is a `role="combobox"`
  input with `aria-controls`, `aria-expanded`, `aria-autocomplete="list"`, and
  `aria-activedescendant` tracking the highlighted row; results sit in a
  `role="listbox"` with `role="group"`/`role="option"` rows and
  `aria-selected`; arrow keys, Home/End, and Enter move and commit the
  highlight; Escape closes via the underlying `Dialog`'s own handling. These
  are `CommandPalette`'s contract, not `RdidPicker`'s own code, and
  `CommandPalette` has no ingredient of its own yet in this cookbook — this
  section describes what `RdidPicker` actually gets by composing it, traced
  to `command-palette.tsx`.
- Each result's `entityType` badge is rendered as visible text (not a
  color-only cue), so entity type reads without color.
- Touch/click target sizing for the search field, result rows, and dialog
  chrome is `CommandPalette`'s rendering, not a value `rdid-picker.tsx`
  chooses; `RdidPicker` supplies no sizing of its own to evaluate here.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| T1 | renders-single-command-palette | mount with `open=true` | Exactly one `CommandPalette` rendered, receiving `open`, `onOpenChange`, `query`, `onQueryChange`, one group, `ariaLabel`, `placeholder`, `loading`, `error`, `emptyLabel` |
| T2 | resets-on-close | type "abc", let it resolve, then set `open=false` | `CommandPalette` receives `query===""`, `groups[0].items` equals `[]`, `error===null`, `loading===false` |
| T3 | skips-search-for-empty-query | `open=true`, `query=""` (also: `query="   "`) | `search` not called; `CommandPalette` receives `groups[0].items` equal to `[]`, `loading===false`, `error===null` |
| T4 | sets-loading-before-debounce-elapses | type "a"; inspect the props passed to `CommandPalette` before `debounceMs` elapses | `CommandPalette` receives `loading===true` |
| T5 | debounces-search-call | type "a", "ab", "abc" within `debounceMs`, then wait past it | `search` called exactly once, with `"abc"` |
| T6 | debounces-search-call | type `"  abc "` (leading and trailing whitespace) as the final value within `debounceMs`, then wait past it | `search` called exactly once, with `"abc"` (trimmed), never `"  abc "` |
| T7 | aborts-superseded-search | type "ab"; before `debounceMs` elapses, type "abc" | the "ab" debounce timer is cleared and never invokes `search`; `search` is ultimately invoked once, for "abc" |
| T8 | aborts-superseded-search | type "ab"; wait until its debounced call invokes `search` but before it settles; then type "abc" | the "ab" call's `AbortSignal.aborted===true` |
| T9 | ignores-aborted-search-results | resolve the aborted "ab" call's promise from T8 after "abc" is in flight | the `loading`/`error`/`groups[0].items` props passed to `CommandPalette` are unaffected by the "ab" settlement |
| T10 | populates-options-on-success | `search` resolves with `[{rdid:"r1",entityType:"ecosystem",entityId:"e1"}]` | `CommandPalette` receives `groups[0].items` containing one item with id `"r1"`, label `"r1"`, badge `"ecosystem"`; `error===null`; `loading===false` |
| T11 | surfaces-search-rejection | `search` rejects with `new Error("boom")` | `CommandPalette` receives `error==="boom"`; `groups[0].items` equal to `[]`; `loading===false` |
| T12 | surfaces-search-rejection | `search` rejects with a non-`Error` value | `CommandPalette` receives `error==="Search failed"` |
| T13 | calls-latest-search-implementation | re-render with a new `search` function identity, `query` unchanged, then let the pending call fire | the most recently supplied `search` function is the one invoked |
| T14 | passes-full-option-to-onPick | select the result `{rdid:"r1",entityType:"ecosystem",entityId:"e1"}` | `onPick` called with that whole object |
| T15 | closes-on-pick | select any result | `onOpenChange(false)` is called (by `CommandPalette`'s `run()`) before/independent of `onPick` handling; the picker closes |
| T16 | labels-group-by-entity-type | `entityTypeLabel="ecosystem"` | group label reads "ecosystem addresses" |
| T17 | labels-group-by-entity-type | no `entityTypeLabel` | group label reads "Addresses" |
| T18 | derives-default-placeholder | `entityTypeLabel="ecosystem"`, no `placeholder` | placeholder reads "Search ecosystem addresses…" |
| T19 | derives-default-placeholder | no `entityTypeLabel`, no `placeholder` | placeholder reads "Search addresses…" |
| T20 | derives-empty-label-from-query | `query=""` | `emptyLabel` reads "Start typing an address" |
| T21 | derives-empty-label-from-query | non-empty `query`, zero results | `emptyLabel` reads "No matching address" |
| T22 | defaults-title-and-aria-label | no `title` prop | `CommandPalette` receives `ariaLabel==="Choose an address"` |
| T23 | renders-each-result-by-rdid-with-badge | option `{rdid:"r1",entityType:"ecosystem",entityId:"e1"}` | rendered item id is "r1", label is "r1", badge is "ecosystem" |
| T24 | aborts-superseded-search, resets-on-close | open, type "ab", close before `debounceMs` elapses, then reopen before `debounceMs` (measured from the "ab" keystroke) elapses | `search` is never called with "ab"; no stale call from the first session reaches `search` in the reopened session |

## Edge Cases

- **Null/empty input**: an empty or whitespace-only `query` is treated
  identically — trimmed to `""` and no `search` call is made (see
  skips-search-for-empty-query, T3). A non-empty query with surrounding
  whitespace is trimmed before it reaches `search`, never passed raw (see
  debounces-search-call, T6). `entityTypeLabel` and `placeholder` are
  optional props; their absence falls through to the derived defaults rather
  than any null-handling logic.
- **Boundary values**: `debounceMs=0` still schedules via `setTimeout(fn, 0)`
  — the call is deferred to the next macrotask, never synchronous. Source
  performs no clamping or validation on `debounceMs`; a very large value
  simply delays longer. A `search` resolving with `[]` is a normal success
  (renders the "No matching address" empty label), not an error.
- **Concurrent access**: rapid retyping produces overlapping `search` calls;
  each query change aborts whatever call was still pending and starts a new
  debounce (aborts-superseded-search, T7/T8). The component's state is local
  `React.useState` owned by one mounted instance, so there is no shared
  mutable state across instances to race on. Closing and reopening before an
  earlier debounce timer elapses does not let that stale timer reach
  `search` in the new session (T24).
- **Error states**: a `search` rejection — whether an `Error` or any other
  rejected value — surfaces as `error` and clears `options`
  (surfaces-search-rejection, T11/T12). Source contains no retry or backoff
  loop of its own: a failed search is not retried automatically; the user
  retrigger is another keystroke, which starts a fresh debounced call.
- **Offline / disconnected**: the component makes no network call directly —
  `search` is a caller-supplied function, and its transport, timeout, and
  retry behavior are the caller's responsibility, not `rdid-picker.tsx`'s.
  Whatever that function's promise rejects with (network failure, timeout, or
  otherwise) is handled identically and generically as any other rejection;
  the source has no online/offline detection of its own.
- A rejection that settles after the picker has since closed (and possibly
  reopened) is already aborted by the close-triggered effect cleanup, so it
  is ignored rather than corrupting the fresh session's state (see
  resets-on-close and ignores-aborted-search-results, and T24 for the
  reopen-before-elapsed case directly).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `open` | `boolean` | — | Controls the `CommandPalette`/`Dialog`. |
| `onOpenChange` | `(open: boolean) => void` | — | Fired when the dialog wants to open or close (e.g. Escape, backdrop). |
| `onPick` | `(option: RdidOption) => void` | — | Fired with the whole selected option when a result is chosen. |
| `search` | `(query: string, signal: AbortSignal) => Promise<RdidOption[]>` | — | Caller-supplied lookup; scoping (e.g. to one entity type) is the caller's, via closure. |
| `entityTypeLabel` | `string` | `undefined` | Named in the group label and default placeholder, e.g. `"ecosystem"` → "Search ecosystem addresses…". |
| `title` | `string` | `"Choose an address"` | Dialog title; passed through as `CommandPalette`'s `ariaLabel`. |
| `placeholder` | `string` | derived from `entityTypeLabel` | Search field placeholder; overrides the derived default when set. |
| `debounceMs` | `number` | `200` | Milliseconds of no `query` change before `search` is invoked. |

## Deep Linking

Not applicable: the component has no route or URL of its own. Visibility is
controlled entirely by the caller through the `open`/`onOpenChange` props;
`rdid-picker.tsx` imports no router and reads no URL state.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Choose an address" | Default `title` / dialog `ariaLabel` |
| n/a (literal) | "Search addresses…" | Default placeholder, no `entityTypeLabel` |
| n/a (literal) | "Search <entityTypeLabel> addresses…" | Default placeholder, with `entityTypeLabel` |
| n/a (literal) | "Addresses" | Default group label, no `entityTypeLabel` |
| n/a (literal) | "<entityTypeLabel> addresses" | Group label, with `entityTypeLabel` |
| n/a (literal) | "Start typing an address" | Empty label, empty query |
| n/a (literal) | "No matching address" | Empty label, query with zero results |
| n/a (literal) | "Search failed" | Fallback error message for a non-`Error` rejection |

Not applicable beyond the table above: `rdid-picker.tsx` hardcodes these as
inline English string literals with no localization key extraction or i18n
mechanism in source.

## Accessibility Options

- **Reduce Motion**: Not applicable — `rdid-picker.tsx` defines no animation
  or transition of its own; any open/close motion belongs to the composed
  `Dialog`/`CommandPalette`.
- **Increase Contrast**: Not applicable — `rdid-picker.tsx` defines no color
  values of its own; all colors are owned by the composed `CommandPalette`.
- **Differentiate Without Color**: Satisfied by composition — each result's
  `entityType` is rendered as the item's `badge` text (see
  renders-each-result-by-rdid-with-badge), not encoded by color alone.

## Feature Flags

Not applicable: `rdid-picker.tsx` contains no feature-flag or config-gating
logic; it renders whenever `open` is `true`.

## Analytics

Not applicable: `rdid-picker.tsx` contains no analytics or telemetry calls.
A caller may instrument `onPick`/`onOpenChange` itself, but the component
emits no events of its own.

## Privacy

- **Data collected**: None by the component itself. It holds `query`,
  `options`, `loading`, and `error` in transient `React.useState`.
- **Storage**: In-memory only, for the lifetime of the mounted component;
  cleared back to initial values whenever `open` becomes `false`
  (resets-on-close). No `localStorage`, cookie, or other persistence is used.
- **Transmission**: The component makes no network call itself; any
  transmission happens inside the caller-supplied `search` function, which is
  outside this component's source.
- **Retention**: None — state does not survive a close, and nothing is
  written to durable storage.

## Logging

Not applicable: `rdid-picker.tsx` contains no logging calls. A failed search
is surfaced only through the `error` state consumed by `CommandPalette`.

## Platform Notes

- **React/Web (source)**: `packages/web/packages/adh-ui/src/blocks/rdid-picker.tsx`
  (`@agentic-toolkit/adh-ui`, `"use client"`). Composes `CommandPalette` and
  `CommandGroup` from `@agenticdevelopertoolkit/ui/blocks/command-palette`;
  `RdidPicker` itself owns only the debounce/abort/reset state machine and
  the group/label/placeholder derivation — no dialog, listbox, or keyboard
  logic of its own.
- **SwiftUI**: Present as a `.sheet`/`.popover` hosting a `List` with a
  `.searchable(text:)`-bound query; drive the debounced fetch from a
  `.task(id: query)` after a `Task.sleep(for:)` of `debounceMs` — a new
  `id` automatically cancels the prior `Task`, giving abort-on-supersede for
  free without a manual `AbortController` analogue. Surface `loading`/`error`
  as an overlay (`ProgressView`, `ContentUnavailableView`) over the `List`.
- **Compose**: Host in a `ModalBottomSheet` or `AlertDialog` with a
  `LazyColumn`; bind the search `TextField` through a `Flow` using
  `.debounce(debounceMs)` and `.collectLatest { }`, which mirrors the
  trailing-delay-plus-cancel-on-supersede this ingredient implements by hand with
  `setTimeout`/`AbortController`. Hoist `loading`/`error`/`options` as Compose
  state the same way `query`/`options` are hoisted here.
- **AppKit/UIKit**: Present modally (`NSPanel` or a `UIViewController`) over
  an `NSSearchField`/`UISearchController` and a table view. Debounce by
  rescheduling a single `DispatchWorkItem`/`Timer` on every keystroke (cancel
  and replace, matching the `clearTimeout`+new `setTimeout` here), and cancel
  the in-flight `URLSessionTask` the way `AbortController.abort()` is called
  here before starting the next one.
- **WinUI 3**: Use an `AutoSuggestBox` inside a `ContentDialog` (or a
  `Popup`) as the direct analogue of `CommandPalette`'s combobox input +
  listbox pairing — `AutoSuggestBox` already binds a text box to a
  keyboard-navigable suggestion list with Enter-to-commit, matching the
  type/arrow/Enter contract this ingredient requires. Bind `ItemsSource` to a
  small view-model list exposing `Rdid`/`EntityType` for the item template's
  primary text and badge (mirroring `renders-each-result-by-rdid-with-badge`).
  Debounce in the `TextChanged` handler with a `DispatcherTimer` that is
  stopped and restarted on every keystroke (the `setTimeout` reset here), and
  cancel the previous lookup via a stored `CancellationTokenSource.Cancel()`
  before creating a new one and awaiting `SearchAsync(query, token)` — the
  direct analogue of `AbortController`. Bind `IsLoading` to show a
  `ProgressRing` (or the `AutoSuggestBox`'s built-in loading indicator) and
  bind an `ErrorMessage` string to a status `TextBlock`, toggled exactly as
  `loading`/`error` gate `CommandPalette`'s render here. Clear
  `AutoSuggestBox.Text` and the bound `ItemsSource` in the dialog's `Closing`
  handler, mirroring the `open`-keyed reset effect in source.

## Design Decisions

- **Decision**: Build on `CommandPalette` rather than a bespoke search
  dialog.
  **Rationale**: Per source comment in `rdid-picker.tsx`'s top-of-file JSDoc,
  "the palette already IS this interaction — a modal over one field,
  keyboard-driven, first result preselected, Enter runs it and closes." A
  second dialog with its own search box and result list would duplicate that
  shape under a different name.
  **Approved**: pending
- **Decision**: No `scope` prop; a caller restricts results by closing over
  its own filter inside `search`.
  **Rationale**: Per source comment in `rdid-picker.tsx`'s top-of-file JSDoc
  ("SCOPING IS THE CALLER'S" paragraph), a `scope` prop would mean this
  component owns the list of scopes, requiring every new entity type to come
  back and edit it; closing over the filter keeps `RdidPicker` ignorant of
  what an "ecosystem" (or any other entity type) is.
  **Approved**: pending
- **Decision**: Debouncing and abort-on-supersede live in `RdidPicker`, not
  in `CommandPalette`.
  **Rationale**: Per source comment in `rdid-picker.tsx`'s top-of-file JSDoc
  ("DEBOUNCING LIVES HERE" paragraph), `CommandPalette` is a controlled input
  with no opinion on when the host fetches; but this picker's list IS the
  fetch, so the trailing delay and the abort of a superseded request belong
  to it.
  **Approved**: pending
- **Decision**: `onPick` receives the whole `RdidOption`, not just the
  `rdid` string.
  **Rationale**: Per source comment on the `onPick` prop in
  `rdid-picker.tsx`, a caller that needs the entity id must not have to
  re-resolve the address it just picked — a second lookup that can disagree
  with the first.
  **Approved**: pending
- **Decision**: `search` is read through a ref (`searchRef`) inside the
  debounce effect instead of listing `search` itself as a dependency.
  **Rationale**: Per source comment above the `searchRef` effect in
  `rdid-picker.tsx`, `search` is usually an inline arrow function with a new
  identity on every render; keying the effect on it would restart the
  debounce on every parent re-render, and a steadily typing user would never
  reach the trailing edge.
  **Approved**: pending
- **Decision**: Closing the picker clears `query`, `options`, `error`, and
  `loading`.
  **Rationale**: Per source comment above the close-triggered reset effect in
  `rdid-picker.tsx`, reopening onto a stale query and a stale list would
  offer a result for a search the user has already moved on from.
  **Approved**: pending
- **Decision**: A failed search clears `options` rather than leaving stale
  results in place.
  **Rationale**: Per source comment in the rejection handler in
  `rdid-picker.tsx`, an empty list after a failed request reads as "no such
  address," the one wrong conclusion available; clearing `options` and
  setting `error` avoids that misreading.
  **Approved**: pending
- **Decision**: Only `title`, `placeholder`, and `entityTypeLabel` are
  caller-overridable strings; the group label's "addresses" suffix, both
  empty-state labels, and the non-`Error` rejection fallback ("Search
  failed") are fixed English literals with no localization mechanism.
  **Rationale**: `rdid-picker.tsx` exposes no other string-customization
  prop and contains no localization key extraction or i18n call; this is the
  component's current, deliberate string surface rather than an oversight,
  and any broader localization would need to be added as new props.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | partial | Accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | Accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | passed | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | failed | Internationalization |
| [text-expansion-tolerance](agenticdevelopercookbook://compliance/internationalization#text-expansion-tolerance) | failed | Internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy & Data |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

Statuses rest on `rdid-picker.tsx`'s composition of `CommandPalette`/`Dialog`
(confirmed ARIA roles — `combobox`, `listbox`, `group`, `option` —, arrow/Home/End/Enter
handling, and a base-ui `Dialog` that traps focus and auto-focuses the input,
grounding the Accessibility passes, while the underlying color tokens and
rendered pixel dimensions aren't determinable from source, grounding the
`partial`s); its hardcoded English literals plus physical `left-`/`pl-`/`pr-`
Tailwind positioning and `truncate`-based labels (grounding the
Internationalization failures); its transient, in-memory-only, close-cleared
state (grounding `data-minimization`); and its keystroke-only retry with no
automatic recovery loop, versus its non-crashing handling of malformed
rejections and whitespace input (grounding `error-recovery` failing while
`graceful-degradation` and `fault-tolerance` pass).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe extracted from `rdid-picker.tsx`. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: use "ingredient" consistently instead of "recipe"; rebuild the Compliance table from real catalog checks; add closes-on-pick and trimmed-query-to-search requirements with test vectors; split the superseded-search test vector into pending-timer and in-flight-abort cases and add a reopen-before-elapsed test vector; restate internal-state test vectors as `CommandPalette` props; cite the `rdid-picker.tsx` location for every Design Decision rationale; bold `**Approved**`; record the fixed-string localization surface as a Design Decision. |
