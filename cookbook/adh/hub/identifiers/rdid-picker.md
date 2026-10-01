---
id: bd0d7595-f186-4aaf-bb45-5c733cfdb03d
title: RDID Picker
domain: agentictoolkit://cookbook/adh/hub/identifiers/rdid-picker
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Modal, debounced, keyboard-driven search over the identifier registry that
  hands the caller one whole matched option, built on a shared modal command-search
  interaction.
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

# RDID Picker

## Overview

The Rdid Picker is a modal search picker for the identifier registry: it
opens a single-field, keyboard-driven search interaction, debounces what
the caller types, calls a caller-supplied search function, and hands back
the whole matched option (`rdid`, `entityType`, `entityId`) when one is
chosen. It is built directly on a shared modal command-search interaction
rather than beside it, because a modal over one field with a
keyboard-driven, first-result-preselected list is already the interaction
that shared component provides; the picker contributes only what a
search-backed instance of that shape still needs: the debounce, the
abort-on-supersede, the group/label/placeholder wiring, and resetting
itself when closed. It owns no opinion about which entities are
searchable — the caller's search function decides that, so restricting
the picker (to one ecosystem, say) is the caller's filter, not a prop
this component interprets.

## Behavioral Requirements

- **renders-single-command-palette**: The component MUST render exactly
  one command-palette instance, passing it the open state, an open-state
  change callback, the query text, a query-change callback, one result
  group, an accessible label, a placeholder, a loading flag, an error
  message, and an empty-results label, and MUST implement no dialog,
  listbox, or keyboard handling of its own.
- **resets-on-close**: When the open state transitions to closed, the
  component MUST clear the query text to empty, the result list to
  empty, the error message to none, and the loading flag to false.
- **skips-search-for-empty-query**: While open and the trimmed query text
  is empty, the component MUST set the result list to empty, the loading
  flag to false, and the error message to none, and MUST NOT call the
  search function.
- **sets-loading-before-debounce-elapses**: While open and the trimmed
  query text is non-empty, the component MUST set the loading flag to
  true immediately, before the debounce delay elapses.
- **debounces-search-call**: The component MUST wait a configurable
  delay (default 200 milliseconds) after the last query change before
  invoking the search function with the trimmed query text, never the
  raw, untrimmed string.
- **aborts-superseded-search**: When the open state, the query text, or
  the debounce delay changes while a previously scheduled or in-flight
  search call has not yet settled, the component MUST cancel that call
  and MUST cancel its pending debounce timer.
- **ignores-aborted-search-results**: When a search call settles after it
  has been canceled, the component MUST NOT update the result list, the
  error message, or the loading flag from that settlement.
- **populates-options-on-success**: When a non-superseded search call
  resolves, the component MUST set the result list to the resolved
  array, MUST set the error message to none, and MUST set the loading
  flag to false.
- **surfaces-search-rejection**: When a non-superseded search call
  rejects, the component MUST set the error message to the rejection's
  message when the rejection is an error object, or to the literal
  string `"Search failed"` otherwise, MUST set the result list to empty,
  and MUST set the loading flag to false.
- **calls-latest-search-implementation**: Each debounced invocation MUST
  call the most recently supplied search function, even when the
  debounce mechanism has not been reset since the search function last
  changed identity.
- **passes-full-option-to-onPick**: Selecting a result MUST invoke the
  pick callback with that result's complete option (`rdid`,
  `entityType`, `entityId`), not the `rdid` string alone.
- **closes-on-pick**: Selecting a result MUST close the picker. The
  picker triggers no close of its own on selection — closing happens
  inside the composed command palette's own commit action, which fires
  the open-state change callback (closing the picker) before invoking
  the item's selection handler (and therefore the pick callback).
- **labels-group-by-entity-type**: The single result group's label MUST
  read `<entityTypeLabel> addresses` when an entity type label is
  supplied, and MUST read `Addresses` when it is not.
- **derives-default-placeholder**: When no placeholder is given, the
  search field's placeholder MUST read `Search <entityTypeLabel>
  addresses…` when an entity type label is supplied, and `Search
  addresses…` when it is not.
- **derives-empty-label-from-query**: The empty-results label MUST read
  `Start typing an address` while the trimmed query text is empty, and
  MUST read `No matching address` once the trimmed query text is
  non-empty.
- **defaults-title-and-aria-label**: The component MUST default its
  title to `Choose an address` and MUST pass that title through as the
  composed command palette's accessible label.
- **renders-each-result-by-rdid-with-badge**: Each item in the rendered
  group MUST use the option's `rdid` as both its item identifier and its
  label, and MUST show the option's `entityType` as the item's badge.

## Appearance

Not applicable: the component renders no markup of its own — it delegates
its entire visual output to one composed command-palette instance. Corner
radius, padding, font, background, foreground, border, shadow, and
min/max size are all owned by that composed interaction (and the modal
dialog it renders into), not by this component.

## States

| State | Appearance change |
|-------|------------------|
| Closed | The command palette is not shown; internal query text, result list, error message, and loading flag are reset |
| Open, query empty | Empty-results label reads "Start typing an address"; loading is false, error message is none, result list is empty |
| Open, query non-empty, debounce/search pending | A loading flag is passed to the command palette (shown beside any still-displayed prior results, per the command palette's own loading treatment) |
| Open, search resolved with results | The result list is populated; each renders as a group item keyed by `rdid` |
| Open, search resolved with zero results | The result list is empty; empty-results label reads "No matching address" |
| Open, search rejected | The error message is set to the rejection message (or "Search failed"); the result list is empty; loading is false |

## Accessibility

- The picker contributes one accessible name: the title (default
  "Choose an address") is passed straight through as the composed
  command palette's accessible label, which names both the modal's
  hidden heading and the search field/listbox for assistive technology.
- All other accessibility mechanics are inherited by composition, not
  implemented by the picker itself: the search field behaves as a
  combo-box-style input associated with the results list, and tracks
  which row is highlighted; results sit in a listbox-like structure with
  grouped, selectable rows; arrow keys, Home/End, and Enter move and
  commit the highlight; Escape closes via the underlying modal's own
  handling. These are the composed command-search interaction's
  contract, not the picker's own logic, and that composed interaction
  has no ingredient of its own yet in this cookbook — this section
  describes what the picker actually gets by composing it.
- Each result's entity-type badge is rendered as visible text (not a
  color-only cue), so entity type reads without color.
- Touch/click target sizing for the search field, result rows, and
  dialog chrome is the composed interaction's rendering, not a value the
  picker chooses; the picker supplies no sizing of its own to evaluate
  here.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| T1 | renders-single-command-palette | mount with the picker open | Exactly one command-palette instance renders, receiving the open state, an open-state change callback, the query text, a query-change callback, one result group, an accessible label, a placeholder, a loading flag, an error message, and an empty-results label |
| T2 | resets-on-close | type "abc", let it resolve, then close the picker | The command palette receives an empty query text, an empty result group, no error message, and loading false |
| T3 | skips-search-for-empty-query | open with an empty query (also: a whitespace-only query) | search not called; the command palette receives an empty result group, loading false, no error message |
| T4 | sets-loading-before-debounce-elapses | type "a"; inspect the state passed to the command palette before the debounce delay elapses | The command palette receives loading true |
| T5 | debounces-search-call | type "a", "ab", "abc" within the debounce delay, then wait past it | search called exactly once, with "abc" |
| T6 | debounces-search-call | type "  abc " (leading and trailing whitespace) as the final value within the debounce delay, then wait past it | search called exactly once, with "abc" (trimmed), never "  abc " |
| T7 | aborts-superseded-search | type "ab"; before the debounce delay elapses, type "abc" | the "ab" debounce timer is cleared and never invokes search; search is ultimately invoked once, for "abc" |
| T8 | aborts-superseded-search | type "ab"; wait until its debounced call invokes search but before it settles; then type "abc" | the "ab" call is canceled |
| T9 | ignores-aborted-search-results | resolve the canceled "ab" call's result after "abc" is in flight | the loading flag, error message, and result group passed to the command palette are unaffected by the "ab" settlement |
| T10 | populates-options-on-success | search resolves with one option `{rdid:"r1",entityType:"ecosystem",entityId:"e1"}` | The command palette receives a result group containing one item with identifier "r1", label "r1", badge "ecosystem"; no error message; loading false |
| T11 | surfaces-search-rejection | search rejects with an error object carrying the message "boom" | The command palette receives error message "boom"; the result group is empty; loading false |
| T12 | surfaces-search-rejection | search rejects with a non-error-object value | The command palette receives error message "Search failed" |
| T13 | calls-latest-search-implementation | re-render with a new search function, query text unchanged, then let the pending call fire | the most recently supplied search function is the one invoked |
| T14 | passes-full-option-to-onPick | select the result `{rdid:"r1",entityType:"ecosystem",entityId:"e1"}` | the pick callback is called with that whole option |
| T15 | closes-on-pick | select any result | the open-state change callback is called to close the picker (fired by the composed command palette's own commit action) before/independent of the pick callback handling |
| T16 | labels-group-by-entity-type | entity type label "ecosystem" | group label reads "ecosystem addresses" |
| T17 | labels-group-by-entity-type | no entity type label | group label reads "Addresses" |
| T18 | derives-default-placeholder | entity type label "ecosystem", no placeholder | placeholder reads "Search ecosystem addresses…" |
| T19 | derives-default-placeholder | no entity type label, no placeholder | placeholder reads "Search addresses…" |
| T20 | derives-empty-label-from-query | empty query | empty-results label reads "Start typing an address" |
| T21 | derives-empty-label-from-query | non-empty query, zero results | empty-results label reads "No matching address" |
| T22 | defaults-title-and-aria-label | no title given | the command palette receives accessible label "Choose an address" |
| T23 | renders-each-result-by-rdid-with-badge | option `{rdid:"r1",entityType:"ecosystem",entityId:"e1"}` | rendered item identifier is "r1", label is "r1", badge is "ecosystem" |
| T24 | aborts-superseded-search, resets-on-close | open, type "ab", close before the debounce delay elapses, then reopen before the debounce delay (measured from the "ab" keystroke) elapses | search is never called with "ab"; no stale call from the first session reaches search in the reopened session |

## Edge Cases

- **Null/empty input**: an empty or whitespace-only query is treated
  identically — trimmed to empty and no search call is made (see
  skips-search-for-empty-query, T3). A non-empty query with surrounding
  whitespace is trimmed before it reaches search, never passed raw (see
  debounces-search-call, T6). The entity type label and placeholder are
  optional; their absence falls through to the derived defaults rather
  than any null-handling logic.
- **Boundary values**: a debounce delay of 0 still schedules via a
  deferred timer — the call is deferred to the next tick, never
  synchronous. Source performs no clamping or validation on the
  debounce delay; a very large value simply delays longer. A search
  resolving with an empty list is a normal success (renders the "No
  matching address" empty label), not an error.
- **Concurrent access**: rapid retyping produces overlapping search
  calls; each query change aborts whatever call was still pending and
  starts a new debounce (aborts-superseded-search, T7/T8). The
  component's state is local to one mounted instance, so there is no
  shared mutable state across instances to race on. Closing and
  reopening before an earlier debounce timer elapses does not let that
  stale timer reach search in the new session (T24).
- **Error states**: a search rejection — whether an error object or any
  other rejected value — surfaces as the error message and clears the
  result list (surfaces-search-rejection, T11/T12). Source contains no
  retry or backoff loop of its own: a failed search is not retried
  automatically; the user retrigger is another keystroke, which starts a
  fresh debounced call.
- **Offline / disconnected**: the component makes no network call
  directly — search is a caller-supplied function, and its transport,
  timeout, and retry behavior are the caller's responsibility, not this
  component's. Whatever that function's promise rejects with (network
  failure, timeout, or otherwise) is handled identically and generically
  as any other rejection; the source has no online/offline detection of
  its own.
- A rejection that settles after the picker has since closed (and
  possibly reopened) is already canceled by the close-triggered cleanup,
  so it is ignored rather than corrupting the fresh session's state (see
  resets-on-close and ignores-aborted-search-results, and T24 for the
  reopen-before-elapsed case directly).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `open` | boolean | — | Controls the modal search interaction. |
| `onOpenChange` | callback taking the new open state | — | Fired when the dialog wants to open or close (e.g. Escape, backdrop). |
| `onPick` | callback taking the selected option | — | Fired with the whole selected option when a result is chosen. |
| `search` | callback taking the query text and a cancellation signal, returning a promise of an array of options | — | Caller-supplied lookup; scoping (e.g. to one entity type) is the caller's, via closure. |
| `entityTypeLabel` | string | none | Named in the group label and default placeholder, e.g. `"ecosystem"` → "Search ecosystem addresses…". |
| `title` | string | `"Choose an address"` | Dialog title; passed through as the composed interaction's accessible label. |
| `placeholder` | string | derived from `entityTypeLabel` | Search field placeholder; overrides the derived default when set. |
| `debounceMs` | number | `200` | Milliseconds of no query change before search is invoked. |

## Deep Linking

Not applicable: the component has no route or URL of its own. Visibility
is controlled entirely by the caller through the open/close callbacks;
the component reads no URL state and performs no routing of its own.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Choose an address" | Default title / dialog accessible label |
| n/a (literal) | "Search addresses…" | Default placeholder, no entity type label |
| n/a (literal) | "Search <entityTypeLabel> addresses…" | Default placeholder, with entity type label |
| n/a (literal) | "Addresses" | Default group label, no entity type label |
| n/a (literal) | "<entityTypeLabel> addresses" | Group label, with entity type label |
| n/a (literal) | "Start typing an address" | Empty label, empty query |
| n/a (literal) | "No matching address" | Empty label, query with zero results |
| n/a (literal) | "Search failed" | Fallback error message for a non-error-object rejection |

Not applicable beyond the table above: these are hardcoded as inline
English string literals with no localization key extraction or i18n
mechanism in the component.

## Accessibility Options

- **Reduce Motion**: Not applicable — the component defines no animation
  or transition of its own; any open/close motion belongs to the
  composed command palette.
- **Increase Contrast**: Not applicable — the component defines no color
  values of its own; all colors are owned by the composed command
  palette.
- **Differentiate Without Color**: Satisfied by composition — each
  result's entity type is rendered as the item's badge text (see
  renders-each-result-by-rdid-with-badge), not encoded by color alone.

## Feature Flags

Not applicable: the component contains no feature-flag or config-gating
logic; it renders whenever open is true.

## Analytics

Not applicable: the component contains no analytics or telemetry calls.
A caller may instrument the pick/open-state callbacks itself, but the
component emits no events of its own.

## Privacy

- **Data collected**: None by the component itself. It holds the query
  text, result list, loading flag, and error message in transient local
  state.
- **Storage**: In-memory only, for the lifetime of the mounted component;
  cleared back to initial values whenever it closes (resets-on-close).
  No persistent storage is used.
- **Transmission**: The component makes no network call itself; any
  transmission happens inside the caller-supplied search function, which
  is outside this component's own logic.
- **Retention**: None — state does not survive a close, and nothing is
  written to durable storage.

## Logging

Not applicable: the component contains no logging calls. A failed search
is surfaced only through the error message consumed by the composed
command palette.

## Platform Notes

- **React/Web (source)**: `packages/web/packages/adh-ui/src/blocks/rdid-picker.tsx`
  (`@agentic-toolkit/adh-ui`, `"use client"`). Composes `CommandPalette`
  and `CommandGroup` from
  `@agenticdevelopertoolkit/ui/blocks/command-palette`; `RdidPicker`
  itself owns only the debounce/abort/reset state machine (held in
  `React.useState`) and the group/label/placeholder derivation — no
  dialog, listbox, or keyboard logic of its own. `CommandPalette`
  supplies the accessible name (a visually-hidden `DialogTitle` bound to
  `ariaLabel`), a `role="combobox"` search input with
  `aria-controls`/`aria-expanded`/`aria-autocomplete="list"`/`aria-activedescendant`,
  and a `role="listbox"` of `role="group"`/`role="option"` rows with
  `aria-selected`, arrow/Home/End/Enter handling, and Escape-to-close via
  the underlying `Dialog` — traced to `command-palette.tsx`, which has
  no ingredient of its own yet in this cookbook. Debounce/abort is
  hand-rolled: a `setTimeout` reschedule per keystroke (clearing the
  prior with `clearTimeout`) and an `AbortController` created per search
  call, aborted on supersede; the current `search` function is read
  through a ref (`searchRef`) rather than listed as an effect
  dependency, so retyping doesn't restart the debounce on every parent
  re-render (see Design Decisions).
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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-ui/src/blocks/rdid-picker.tsx` |

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
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/identifiers/. |
