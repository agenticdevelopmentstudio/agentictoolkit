<!-- leaf: implement-general-2/rdid-picker · source: rdid-picker.md -->

**Rules** (cite as `implement-general-2/rdid-picker#<slug>`):

- `renders-single-command-palette` MUST
- `resets-on-close` MUST
- `skips-search-for-empty-query` MUST
- `sets-loading-before-debounce-elapses` MUST
- `debounces-search-call` MUST
- `aborts-superseded-search` MUST
- `ignores-aborted-search-results` MUST
- `populates-options-on-success` MUST
- `surfaces-search-rejection` MUST
- `calls-latest-search-implementation` MUST
- `passes-full-option-to-onpick` MUST — Selecting a result MUST invoke onPick with that result's complete option object (rdid, entityType, entityId), not the …
- `closes-on-pick` MUST
- `labels-group-by-entity-type` MUST
- `derives-default-placeholder` MUST
- `derives-empty-label-from-query` MUST
- `defaults-title-and-aria-label` MUST
- `renders-each-result-by-rdid-with-badge` MUST

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

