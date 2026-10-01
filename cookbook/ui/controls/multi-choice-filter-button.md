---
id: bc43002d-faf6-4ffa-bc12-95f1a07f27e8
title: Multi-Choice Filter Button
domain: agentictoolkit://cookbook/ui/controls/multi-choice-filter-button
type: ingredient
version: 1.2.0
status: review
language: en
created: 2026-09-23
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A pull-down control that filters on any combination of a short, fixed
  choice list, with a live summary title.
platforms:
- swift
- macos
tags:
- picker
- filter
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Multi-Choice Filter Button

## Overview

This is a pull-down control that filters on any combination of a short,
fixed list of choices — the source's own doc comment gives the example
"the `Good for: Coding, Writing` control above a picker's table." Choices
are identified by opaque string ids rather than a caller's own enum, so one
control serves any caller's type without this file knowing about it; the
caller maps ids back to its own type. The button's displayed title is a
running summary of the current selection ("Any" when nothing is chosen, the
chosen titles when there are one or two, a count once there are three or
more), so the state is legible without opening the menu. Because the menu
is a stock, checkable menu, it closes on every pick — per the source's own
comment, several boxes take several trips, and the alternative (items
hosting their own checkbox views to keep the menu open) trades a familiar
system control for a hand-built one.

## Behavioral Requirements

- **builds-fixed-menu-structure**: Component MUST build one menu whose
  items are, in order: an item titled `label` with no action (item 0, the
  pull-down's own displayed-title slot, per platform convention never
  itself invoked), an "Any" item that clears the selection, a separator,
  then one item per entry in `choices`, each titled with that choice's
  `title`.
- **sets-choice-tooltip**: For each choice whose `detail` is non-empty, the
  corresponding menu item MUST have its tooltip set to that `detail`.
  Component MUST NOT set a tooltip on a choice item whose `detail` is
  empty.
- **clears-selection-on-any**: Selecting the "Any" item MUST set `selection`
  to the empty set.
- **toggles-choice-on-select**: Selecting a choice's menu item MUST add that
  choice's `id` to `selection` if it is absent, or remove it if it is
  present.
- **restricts-selection-to-known-ids**: The selection-setting operation
  MUST set `selection` to the intersection of the ids it is given with the
  ids of `choices`; any id not present in `choices` MUST be discarded
  silently.
- **reflects-checkmarks**: After every call to the choice toggle action, the
  "Any" action, or the selection-setting operation, each choice's menu item
  MUST be resynchronized to checked when that item's id is a member of the
  current `selection` and unchecked otherwise — this resync MUST happen
  even when the call left `selection` unchanged in value (see
  **fires-on-change-on-actual-change** and Edge Cases).
- **label-and-any-never-checked**: Item 0 (the label item) and the "Any"
  item MUST NOT ever show a checkmark; only a per-choice item's checked
  state reflects `selection` membership. Neither item carries an id of its
  own, so the checkmark-resync operation's membership test skips both of
  them on every resync.
- **fires-on-change-on-actual-change**: `onChange` MUST be invoked with the
  new `selection` whenever `selection`'s value changes as a result of the
  choice toggle action, the "Any" action, or the selection-setting
  operation. `onChange` MUST NOT be invoked when one of those operations
  leaves `selection` equal in value to what it was before the call.
- **initializes-selection-empty**: At construction, `selection` MUST be the
  empty set, and `onChange` MUST NOT be invoked as a result of that initial
  value being set — `onChange` is nil until the caller assigns it after
  construction returns anyway. See Platform Notes
  for why the initial assignment itself triggers no side effect.
- **formats-title-none-selected**: When `selection` is empty, the button's
  displayed title MUST be `"<label>: Any"`.
- **formats-title-few-selected**: When `selection` contains exactly one or
  exactly two ids, the button's displayed title MUST be
  `"<label>: <titles>"`, where `<titles>` is the `title` of each selected
  choice, in the order those choices appear in `choices`, joined with
  `", "`.
- **formats-title-many-selected**: When `selection` contains three or more
  ids, the button's displayed title MUST be `"<label>: <n> selected"`, where
  `<n>` is `selection.count`.
- **refreshes-title-synchronously**: On every `selection` change, the
  button's on-screen displayed title MUST match the newly computed summary
  before the triggering call (the choice toggle action, the "Any" action,
  or the selection-setting operation) returns — never a stale title left
  over until some later, unrelated redraw. See Platform Notes for the specific API call this requires.
- **resizes-for-longer-titles**: After every title change, the button's
  measured natural size MUST already reflect the new title's length, so a
  longer summary is never laid out — and truncated — inside a width
  computed for the previous, shorter title. See Platform Notes for the specific API call this requires.
- **exposes-readonly-selection**: `selection` MUST be readable from outside
  the type and MUST NOT be settable from outside the type except through
  the selection-setting operation.
- **themes-text-appearance**: The component MUST set its foreground tint
  color to the active theme's `SemanticPalette.primaryTextColor` and its
  font to the active theme's `SemanticPalette.font(.body)`, applying both
  immediately at initialization and reapplying both every time the active
  theme changes.
- **rejects-coder-initialization**: See Platform Notes.
- **confines-to-main-actor**: See Platform Notes.
- **disables-autoresizing-mask-translation**: See Platform Notes.

## Appearance

- **Corner radius**: Not applicable — the component draws nothing of its
  own and sets no layer or corner-radius property; its corner rounding, if
  any, is the platform's native pull-down bezel.
- **Padding**: Not applicable — no content-inset or padding value is set in
  source; the button's internal padding is the platform's native control
  metrics.
- **Font**: `SemanticPalette.font(.body)` resolves the active theme's
  `.body` role, whose default style is a 13pt, regular-weight, proportional
  system font, scaled by the theme's `sizeScale` and by the reader's live
  text-size setting; an active theme MAY override `.body` with its own
  family/size/weight. Applied at initialization and reapplied on every
  theme change, via an observer that falls back to the Solarized Dark
  theme when no active theme manager exists (e.g. previews or tests run
  without an app host).
- **Background**: Not applicable — the foreground tint color is the only
  color this file sets; the button's fill is the platform's native control
  bezel.
- **Foreground/Text**: The foreground tint color is set to
  `SemanticPalette.primaryTextColor`, which resolves the theme's
  `primaryText` role (an explicit override if the active theme declares
  one, else a value derived from the theme's palette). Reapplied live on
  every theme change via the same observer.
- **Border**: Not applicable — no border is drawn or configured in source;
  the button keeps the platform's native control border.
- **Shadow**: Not applicable — no shadow is drawn or configured in source.
- **Min/Max size**: Not applicable — no explicit width/height constraint is
  set in source; the button's size is the platform's native measured size
  for this control, recomputed on every title change (see
  **resizes-for-longer-titles**).

## States

| State | Appearance change |
|-------|------------------|
| Default | Title reads `"<label>: Any"`; no choice menu item is checked. |
| Choice selected | The corresponding menu item is checked (system checkmark glyph); the title updates per **formats-title-few-selected** / **formats-title-many-selected**. |
| Choice deselected / "Any" chosen | The corresponding menu item is unchecked; once no items remain checked, the title reverts to `"<label>: Any"`. |
| Pressed | Not styled by source: opening the pull-down and highlighting a hovered/pressed menu item is the platform's own native rendering for this control and its menu, not custom to this file. |
| Disabled | Not implemented in source; no enabled/disabled property is ever read or set on the component in its own source. A caller may set the inherited enabled property directly, at which point the platform's native disabled dimming applies. |
| Focused | Not styled by source; any focus ring shown when the button is tabbed to is the platform's own native focus-ring appearance for this control. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized in source — no explicit accessibility role
  assignment appears anywhere in this component's own source; the control
  inherits the platform's native pull-down accessibility role, and each
  entry inherits the platform's native checkable-menu-item semantics from
  its checked state.
- **Label requirements**: Not set via an explicit accessible-label
  override; a screen reader's accessible name comes from the platform's
  native title-based naming, and by construction (see
  **formats-title-none-selected** through **formats-title-many-selected**)
  that title always states both `label`, the axis being filtered, and the
  current selection state, so the accessible name is never a bare,
  contextless string.
- **Announce state changes (e.g., loading, disabled)**: Not customized in
  source — the title-refresh and checkmark-resync operations rely entirely
  on the platform's own native accessibility change notifications for this
  control and its menu items; this file posts no announcement of its own.
- **Minimum tap target**: Not applicable — this is a pointer/
  trackpad-driven control with no touch input path in source; a 44×44pt
  minimum is touch guidance that does not apply. Source sets no explicit
  control-size override, so it keeps the platform's regular system control
  metrics.
- **contrast**: NEEDS REVIEW: Not implemented in source. The foreground
  tint color (`primaryTextColor`) and the button's bezel are both resolved
  from the active theme at runtime, and this component's own source
  performs no contrast check against that background; resolving it
  requires auditing each shipped theme's foreground-vs-bezel contrast
  against a chosen accessibility bar (e.g., WCAG 2.1 AA's 4.5:1 for
  body-sized text), a call for the design/accessibility owner of the theme
  catalog, not this file.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| multi-choice-filter-button-001 | builds-fixed-menu-structure | Construct with `label: "Good for"`, `choices: [a, b]` | Menu has exactly 4 items in order: `label` (no action), "Any", a separator, then items titled `a.title` and `b.title` |
| multi-choice-filter-button-002 | sets-choice-tooltip | Choice `a` has `detail: "Runs code"`; choice `b` has `detail: ""` | `a`'s menu item has tooltip "Runs code"; `b`'s menu item has no tooltip set |
| multi-choice-filter-button-003 | clears-selection-on-any | `selection == ["a"]`; invoke the "Any" item's action | `selection == []` |
| multi-choice-filter-button-004 | toggles-choice-on-select | `selection == []`; invoke choice `a`'s item action | `selection == ["a"]` |
| multi-choice-filter-button-005 | toggles-choice-on-select | `selection == ["a"]`; invoke choice `a`'s item action again | `selection == []` |
| multi-choice-filter-button-006 | restricts-selection-to-known-ids | `choices` ids are `["a","b"]`; call the selection-setting operation with `["a","z"]` | `selection == ["a"]`; `"z"` is discarded |
| multi-choice-filter-button-007 | reflects-checkmarks | `selection == []`; invoke choice `a`'s item action | `a`'s menu item is checked; every other choice item is unchecked |
| multi-choice-filter-button-008 | reflects-checkmarks | `selection == ["a"]`; manually set `a`'s menu item to unchecked (simulating drift), then call the selection-setting operation with `["a"]` (no-op value) | `a`'s menu item is resynchronized back to checked by the call |
| multi-choice-filter-button-009 | fires-on-change-on-actual-change | `onChange` recorder attached; `selection == []`; invoke choice `a`'s item action | `onChange` is invoked exactly once with `["a"]` |
| multi-choice-filter-button-010 | fires-on-change-on-actual-change | `onChange` recorder attached; `selection == []`; invoke the "Any" item's action | `onChange` is not invoked |
| multi-choice-filter-button-011 | formats-title-none-selected | `label: "Good for"`, `selection == []` | Button title == `"Good for: Any"` |
| multi-choice-filter-button-012 | formats-title-few-selected | `label: "Good for"`, `choices` titled `["Coding","Writing"]`, both selected | Button title == `"Good for: Coding, Writing"` |
| multi-choice-filter-button-013 | formats-title-many-selected | `label: "Good for"`, 4 of the choices selected | Button title == `"Good for: 4 selected"` |
| multi-choice-filter-button-014 | refreshes-title-synchronously | Invoke choice `a`'s item action | The button's displayed title already matches `"<label>: a.title"` immediately after the call returns, with no further user action needed to refresh it |
| multi-choice-filter-button-015 | resizes-for-longer-titles | Selection goes from 0 choices ("Any") to 2 choices with long titles | The button's measured width after the change is wide enough to display the new title without truncation, and is greater than it was before the change |
| multi-choice-filter-button-016 | exposes-readonly-selection | From outside the type, attempt to assign to `selection` directly | Rejected — `selection` has no externally accessible setter; only the selection-setting operation may change it (enforced at compile time where the language supports it; see Platform Notes) |
| multi-choice-filter-button-017 | themes-text-appearance | Construct the button, then post a theme-change notification with a new theme | The foreground tint color and font update to the new theme's corresponding values without re-constructing the button |
| multi-choice-filter-button-021 | label-and-any-never-checked | Construct with `choices: [a, b]`; invoke choice `a`'s item action | Item 0 and the "Any" item remain unchecked; only `a`'s item is checked |
| multi-choice-filter-button-022 | initializes-selection-empty | Construct the button; check `selection` immediately, before any interaction | `selection == []` |

`rejects-coder-initialization`, `confines-to-main-actor`, and
`disables-autoresizing-mask-translation` have no test vectors: see Platform Notes for each.

## Edge Cases

- Null/empty input: `label` (a string) and `choices` (a list of `Choice`)
  are required, non-optional constructor parameters; neither can be
  omitted or left absent. The component therefore provides, and needs, no
  nil-handling path.
- Empty `choices` array: menu construction still produces item 0, "Any",
  and the separator, but no choice items follow. `selection` can never
  become non-empty (there is nothing to toggle), so the title is
  permanently `"<label>: Any"`. The component does not crash or
  special-case this; it falls straight out of the existing
  menu-building and title-formatting logic.
- Duplicate ids within `choices`: the source enforces no uniqueness on
  `Choice.id`. If two entries share an id, both of their menu items match
  the same membership test in the checkmark-resync operation and are
  therefore always kept in the same checked state as each other, while
  `selection` (a set of strings) holds that id only once regardless of how
  many menu entries reference it. This is the source's actual, as-written
  behavior — a duplicate id is not rejected or deduplicated by this
  component itself (see Design Decisions). Callers MUST supply unique ids
  across `choices`; behavior is undefined if two choices share an id.
- Boundary values: the selection-count boundaries are 0, 1–2, and 3+,
  exactly the three branches in **formats-title-none-selected**,
  **formats-title-few-selected**, and **formats-title-many-selected**. MUST:
  the transition from 2 selected ("`a`, `b`") to 3 selected ("3 selected")
  happens at exactly `selection.count == 3`, with no intermediate form.
- Concurrent access: Not applicable — the component is confined to a
  single thread of execution for its entire lifetime, so all construction,
  menu-item actions, and the selection-setting operation are serialized to
  that thread. See Platform Notes for how that
  confinement is enforced.
- Error states: Not applicable — every operation in this file (menu
  building, toggling, title formatting, theming) is synchronous; no
  error-throwing or failure-producing call appears anywhere in source.
- Offline/disconnected: Not applicable — the component performs no
  networking; it only manages an in-process menu and selection set.
- Selecting "Any" while `selection` is already empty: assigning the empty
  set to `selection` when it is already empty leaves it unchanged in
  value, so neither the title-refresh operation nor `onChange` runs. MUST:
  the checkmark-resync operation still runs immediately after, so every
  choice item's checkmark is still resynchronized on this call even though
  nothing visibly changes (see **reflects-checkmarks**).
- The selection-setting operation called with a set that, after discarding
  unknown ids, equals the current `selection`'s value: the same no-op
  suppression applies to the title-refresh operation and `onChange`, but
  the selection-setting operation still runs the checkmark-resync
  operation unconditionally on every call, so checkmarks are still
  resynchronized. MUST: callers relying on `onChange` to detect a call to
  the selection-setting operation MUST NOT assume it fires when the
  resulting set is unchanged.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `label` | String | — (required) | Names the filtered axis (e.g. `"Good for"`); prefixes every title-summary state and is item 0's own (unselectable) menu title. |
| `choices` | List of Choice | — (required) | The fixed, ordered list of selectable entries; also fixes the order `formats-title-few-selected` joins titles in. |
| `onChange` | Callback | none | Assigned by the caller after construction; invoked with the new `selection` on every actual change (see **fires-on-change-on-actual-change**). |
| `Choice.id` | String | — (required) | Opaque identifier the caller maps back to its own type; membership in `selection` is keyed by this value. |
| `Choice.title` | String | — (required) | The menu item's display title and the text used in the few-selected title summary. |
| `Choice.detail` | String | `""` | Tooltip text for choices whose meaning a title alone can't carry; empty means no tooltip is set (see **sets-choice-tooltip**). |

## Deep Linking

Not applicable: this component is an in-place filter control, not a
navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in its own source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Any" | Menu item title and title-summary text shown when `selection` is empty; hardcoded in the menu-building and title-refresh operations, not routed through any localization mechanism. |
| n/a (literal) | "{n} selected" | Title-summary text shown when three or more choices are selected; same caveat as above. |

Not applicable beyond the table above: `label` and each `Choice.title`/
`Choice.detail` are caller-supplied strings, not literals owned by this
file, so there is nothing else here for the component itself to localize.

`"Any"` and `"{n} selected"` are English literals assigned directly, with
no localization key, and the count string has no plural variant.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this component's own source contains no animation or transition call of any kind; every title and checkmark update is an instantaneous property assignment. |
| Increase Contrast | Not applicable: the file sets no custom color beyond the foreground tint color, sourced from the active theme's `primaryText` role; the pull-down's bezel/border chrome is the platform's native rendering, which follows the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Supported: selection state is communicated through the built-in checkmark glyph on each menu item, not through a color-only signal introduced by this component, so no separate path is needed. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component's own source; the control always builds its full menu
once constructed.

## Analytics

Not applicable: this component's own source contains no analytics or
telemetry call.

## Privacy

- **Data collected**: None beyond what the caller already supplies —
  `label`, `choices` (ids/titles/details), and the resulting `selection`
  are reported only to the caller's own `onChange` closure, in-process.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store; if a caller wants to remember a filter across
  launches, that persistence and its restoration via the selection-setting
  operation are the caller's responsibility, not this file's.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The instance retains only `label`, `choices`, its own
  `selection`, `onChange`, and its own theme-change observer, for its own
  lifetime; it persists nothing beyond that.

## Logging

Not applicable: this component's own source contains no logging call.

## Platform Notes

- **SwiftUI**: Build a `Menu` whose label is the computed summary string
  (mirroring the title-refresh operation's three branches), containing a
  `Button` ("Any") that clears the selection, a `Divider`, then a `Toggle`
  per choice bound to that choice's membership in the selection set — on
  macOS, a `Toggle` inside a `Menu` renders as a checkable menu item, the
  SwiftUI analog of a checked menu item. Gate the write with an equality
  check before invoking the caller's change handler, mirroring
  fires-on-change-on-actual-change.
- **Compose**: Use a `Box` with a `TextButton`/`OutlinedButton` showing the
  summary text, opening a `DropdownMenu` of `DropdownMenuItem`s, each with a
  leading `Checkbox` (or check icon) reflecting membership, plus a
  leading "Any" item that clears the set. Note a translation difference:
  Compose's `DropdownMenuItem.onClick` conventionally dismisses the menu
  (`expanded = false`) unless the call site explicitly keeps it open, so
  matching the source's "menu closes on every pick" behavior is the
  default, but a Compose implementation that wants to let one visit toggle
  several boxes would have to deliberately diverge from this recipe.
- **React/Web**: A `<button>` with `aria-haspopup="menu"` and
  `aria-expanded`, showing the summary text, disclosing a `role="menu"`
  container of `role="menuitemcheckbox"` entries with `aria-checked`
  reflecting membership, plus a `role="menuitem"` "Any" entry that clears
  every `aria-checked`. Note a translation difference: the ARIA Authoring
  Practices convention for `menuitemcheckbox` keeps the menu open across
  multiple picks, unlike the source's per-pick close, so matching the
  source exactly means closing the menu explicitly after each selection.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/UI/Controls/MultiChoiceFilterButton.swift`.
  A macOS-only (`import AppKit`) `NSPopUpButton` subclass, `@MainActor`,
  configured `pullsDown: true`. `confines-to-main-actor` is enforced by
  the class being declared `@MainActor`, so construction or mutation from
  off the main actor fails to compile — a static, compile-time check
  rather than a vector observed by running the program.
  `rejects-coder-initialization` is implemented as a fatal error on
  `init?(coder:)`, since this component provides no Interface
  Builder/`NSCoding` support: attempting `MultiChoiceFilterButton(coder:
  someCoder)` traps with a fatal error and no instance is returned.
  `disables-autoresizing-mask-translation` sets
  `translatesAutoresizingMaskIntoConstraints = false` at initialization so
  the button is positioned by Auto Layout rather than by an autoresizing
  mask — pure layout plumbing with no independently observable behavior of
  its own. It builds a checkable `NSMenu` by hand (label item, "Any",
  separator, one item per choice with `representedObject` holding the
  choice's id — neither the label item nor "Any" carries one, which is why
  the checkmark-resync operation skips both), toggles membership in a
  `Set<String>` from each item's target-action, and repaints its title and
  theme colors through `refreshTitle()`/`applyTheme(_:)`. `refreshTitle()`
  satisfies **refreshes-title-synchronously** by calling
  `synchronizeTitleAndSelectedItem()` immediately after recomputing item
  0's title (a pull-down otherwise keeps the stale title until its menu is
  next reset), and satisfies **resizes-for-longer-titles** by calling
  `invalidateIntrinsicContentSize()` right after that, so the new width is
  measured immediately instead of truncating inside the previous width.
  `initializes-selection-empty` holds because the initializer never
  assigns `selection` itself, so its declared default bypasses the
  property's `didSet` observer (the same observer that drives
  `refreshTitle()`/`onChange` on every later change). The foreground tint
  color is `contentTintColor`; the font path is
  `ThemeTypography.defaultStyle` scaled by `readerScale`, applied and
  reapplied via `ThemePaletteObserver` (falling back to the Solarized Dark
  theme when no `ThemeManager` exists). Checked/unchecked state is
  `NSMenuItem.state = .on`/`.off`. No `controlSize` is set on the button.
  There is no UIKit code path in source — `NSPopUpButton`/`NSMenu` have no
  direct UIKit counterpart; a UIKit/iOS port would replace this with a
  `UIButton` whose `menu` is a checkable `UIMenu` (`UIAction`s with
  `.state = .on`/`.off`; leave `UIMenu.Options` without `.displayInline`, so
  the whole list of checkable actions stays visible instead of collapsing
  into a submenu), setting `showsMenuAsPrimaryAction = true`.
- **WinUI 3**: Build a `DropDownButton` whose `Flyout` is a `MenuFlyout`
  containing one `ToggleMenuFlyoutItem` per choice — `ToggleMenuFlyoutItem.
  IsChecked` is the WinUI analog of `NSMenuItem.state`, and, like a
  checkable `NSMenu`, a `MenuFlyout` closes after an item is invoked by
  default, matching the source's per-pick close. Add a plain
  `MenuFlyoutItem` titled "Any" above a `MenuFlyoutSeparator` that clears
  every `ToggleMenuFlyoutItem.IsChecked`. Recompute the `DropDownButton`'s
  `Content` from a summary string mirroring the title-refresh operation's
  three branches on every selection change — from each
  `ToggleMenuFlyoutItem.Click` handler, the "Any" item's click handler, and
  any programmatic selection-setting entry point alike — since WinUI has
  no built-in pull-down title binding the way `NSPopUpButton` redraws item
  0's title. Set `AutomationProperties.Name` on the `DropDownButton` to the
  current summary text as well, so Narrator's accessible name stays in
  sync the way `NSPopUpButton`'s native title-based name does
  automatically.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/Controls/MultiChoiceFilterButton.swift` |

## Design Decisions

**Decision**: Close the menu on every pick rather than give menu items their
own checkbox views to keep the menu open across multiple picks.
**Rationale**: Per the source's own comment, this is "the stock behaviour of
a checkable menu, and the alternative — items hosting their own checkbox
views to keep the menu open — trades a familiar control for a hand-built
one." (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Identify choices by opaque string ids rather than a caller's
own enum.
**Rationale**: Per the source's own comment, this lets "one control serve any
caller's enum without this file knowing about it; callers map ids back to
their own type." (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Show the full selected list at one or two choices and switch to
a bare count at three or more.
**Rationale**: Per the source's own comment, "the summary title says what is
on without opening it, and 'Any' clears the whole set in one click" — the
count branch exists because, past two items, the full list stops fitting
in a glance. (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Call `invalidateIntrinsicContentSize()` after every title
refresh.
**Rationale**: Per the source's own comment, "the title just changed length,
and the button's intrinsic width is measured from it — without this, a
longer summary lays out inside the old width and gets truncated ('Good
for: Cod…')." (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Leave the checkmark-resync operation unconditional on every
toggle/"Any"/selection-setting-operation call, while gating the
title-refresh operation and `onChange` behind `selection`'s `didSet`
equality check.
**Rationale**: This is the source's as-written, verified behavior: the
checkmark-resync operation is called directly from each method's body
regardless of whether the assignment above it actually changed
`selection`, while the title/`onChange` side effects live in `didSet` and
are naturally suppressed on a no-op assignment. Documented and required
here (see **reflects-checkmarks**) rather than smoothed into "both paths
react identically to a no-op." (Applies to the AppKit implementation.)
**Approved**: pending

**Decision**: Do not deduplicate or reject `Choice` entries that share an
`id`.
**Rationale**: `selection` is a set of strings, and the checkmark-resync
operation matches menu items by their id, so two choices with the same id
are always kept in the same checked state as each other even though they
are visually distinct menu entries. The source enforces no uniqueness
constraint on `Choice.id`; keeping ids unique is a contract on the caller,
stated in Edge Cases. (Applies to the AppKit implementation.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

Native-controls-preference and platform-design-language pass because the
component is a stock pull-down/menu control with no custom drawing.
Keyboard-navigable passes on the platform's inherited keyboard support for
this control (Space/Return opens the menu; arrow keys and type-to-select
navigate it), unmodified by this component. Screen-reader-support passes
because the accessible name is the same title-based string always shown on
screen, and that string always states both the filtered axis and the
current selection (see **Label requirements** under Accessibility).
Contrast-ratio is `partial` because the resolved theme colors are never
checked for contrast in source (see the open question on **contrast**).
String-externalization is failed because the "Any" and "{n} selected"
strings are hardcoded English literals with no localization key (see
Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformatted frontmatter dates and Design Decisions to the template's bold three-line form; fixed the split `fires-on-change-on-actual-change` citation; downgraded descriptive Edge Cases MUSTs to prose while adding an explicit caller contract for unique `Choice.id`s; restated `refreshes-title-synchronously` and `resizes-for-longer-titles` as observable outcomes and moved their AppKit method calls into the Platform Note; added `label-and-any-never-checked` and `initializes-selection-empty` requirements with test vectors; reworded the `syncStates()` asymmetry Design Decision to align with `reflects-checkmarks` instead of contradicting it; fixed test vectors 008 (unfalsifiable no-op), 014 and 015 (spy-only assertions); cleaned up the garbled UIKit note and the incomplete WinUI 3 note; changed the Compliance table's `needs-review` status to `partial` and its categories to title case, remapped `meaningful-labels` into `screen-reader-support` and dropped the uncataloged `differentiate-without-color` and `main-actor-confined` checks, and updated the surrounding prose to match |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/controls/. |
