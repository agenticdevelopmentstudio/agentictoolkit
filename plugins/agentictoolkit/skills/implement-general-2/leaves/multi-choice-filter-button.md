<!-- leaf: implement-general-2/multi-choice-filter-button · source: multi-choice-filter-button.md -->

**Rules** (cite as `implement-general-2/multi-choice-filter-button#<slug>`):

- `builds-fixed-menu-structure` MUST
- `sets-choice-tooltip` MUST
- `clears-selection-on-any` MUST
- `toggles-choice-on-select` MUST
- `restricts-selection-to-known-ids` MUST
- `reflects-checkmarks` MUST
- `label-and-any-never-checked` MUST
- `fires-on-change-on-actual-change` MUST
- `initializes-selection-empty` MUST
- `formats-title-none-selected` MUST
- `formats-title-few-selected` MUST
- `formats-title-many-selected` MUST
- `refreshes-title-synchronously` MUST
- `resizes-for-longer-titles` MUST
- `exposes-readonly-selection` MUST
- `themes-text-appearance` MUST
- `rejects-coder-initialization` MUST
- `confines-to-main-actor` MUST
- `disables-autoresizing-mask-translation` MUST
- `font` MAY — SemanticPalette.font(.body) resolves the active theme's .body TextRole, whose system default …

# MultiChoiceFilterButton

## Overview

`MultiChoiceFilterButton`
(`packages/apple/AgenticToolkit/macOS/UI/Controls/MultiChoiceFilterButton.swift`)
is a macOS `NSPopUpButton` subclass, configured as a pull-down, that filters
on any combination of a short, fixed list of choices — the source's own doc
comment gives the example "the `Good for: Coding, Writing` control above a
picker's table." Choices are identified by opaque string ids rather than a
caller's own enum, so one control serves any caller's type without this file
knowing about it; the caller maps ids back to its own type. The button's
displayed title is a running summary of the current selection ("Any" when
nothing is chosen, the chosen titles when there are one or two, a count once
there are three or more), so the state is legible without opening the menu.
Because the menu is a stock, checkable `NSMenu`, it closes on every pick —
per the source's own comment, several boxes take several trips, and the
alternative (items hosting their own checkbox views to keep the menu open)
trades a familiar system control for a hand-built one.

## Behavioral Requirements

- **builds-fixed-menu-structure**: Component MUST build one `NSMenu` whose
  items are, in order: an item titled `label` with no action (item 0, the
  pull-down's own displayed-title slot, per AppKit convention never itself
  invoked), an "Any" item that clears the selection, a separator, then one
  item per entry in `choices`, each titled with that choice's `title`.
- **sets-choice-tooltip**: For each choice whose `detail` is non-empty, the
  corresponding menu item MUST have its `toolTip` set to that `detail`.
  Component MUST NOT set a `toolTip` on a choice item whose `detail` is
  empty.
- **clears-selection-on-any**: Selecting the "Any" item MUST set `selection`
  to the empty set.
- **toggles-choice-on-select**: Selecting a choice's menu item MUST add that
  choice's `id` to `selection` if it is absent, or remove it if it is
  present.
- **restricts-selection-to-known-ids**: `setSelection(_:)` MUST set
  `selection` to the intersection of the ids it is given with the ids of
  `choices`; any id not present in `choices` MUST be discarded silently.
- **reflects-checkmarks**: After every call to the choice toggle action, the
  "Any" action, or `setSelection(_:)`, each choice's menu item `state` MUST
  be resynchronized to `.on` when that item's id is a member of the current
  `selection` and `.off` otherwise — this resync MUST happen even when the
  call left `selection` unchanged in value (see **fires-on-change-on-actual-change** and Edge Cases).
- **label-and-any-never-checked**: Item 0 (the label item) and the "Any"
  item MUST NOT ever show a checkmark `state`; only a per-choice item's
  `state` reflects `selection` membership. Neither item carries a
  `representedObject` id, so `syncStates()`'s membership test skips both of
  them on every resync.
- **fires-on-change-on-actual-change**: `onChange` MUST be invoked with the
  new `selection` whenever `selection`'s value changes as a result of the
  choice toggle action, the "Any" action, or `setSelection(_:)`. `onChange`
  MUST NOT be invoked when one of those operations leaves `selection` equal
  in value to what it was before the call.
- **initializes-selection-empty**: At construction, `selection` MUST be the
  empty set, and `onChange` MUST NOT be invoked as a result of that initial
  value being set — the initializer never assigns `selection` itself, so its
  declared default bypasses `didSet`, and `onChange` is nil until the caller
  assigns it after construction returns anyway.
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
  or `setSelection(_:)`) returns — never a stale title left over until some
  later, unrelated redraw. See the AppKit / UIKit Platform Note for the
  specific API call this requires.
- **resizes-for-longer-titles**: After every title change, the button's
  measured (intrinsic) size MUST already reflect the new title's length, so
  a longer summary is never laid out — and truncated — inside a width
  computed for the previous, shorter title. See the AppKit / UIKit Platform
  Note for the specific API call this requires.
- **exposes-readonly-selection**: `selection` MUST be readable from outside
  the type and MUST NOT be settable from outside the type except through
  `setSelection(_:)`.
- **themes-text-appearance**: The component MUST set its `contentTintColor`
  to the active theme's `SemanticPalette.primaryTextColor` and its `font` to
  the active theme's `SemanticPalette.font(.body)`, applying both
  immediately at initialization and reapplying both every time the active
  theme changes.
- **rejects-coder-initialization**: `init?(coder:)` MUST NOT produce a
  usable instance; invoking it MUST trigger a fatal error.
- **confines-to-main-actor**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **disables-autoresizing-mask-translation**: The component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` at initialization, so
  it is positioned by Auto Layout rather than by an autoresizing mask.

## Appearance

- **Corner radius**: Not applicable — the component draws nothing of its
  own and sets no layer or corner-radius property; its corner rounding, if
  any, is `NSPopUpButton`'s native system pull-down bezel.
- **Padding**: Not applicable — no content-inset or padding value is set in
  source; the button's internal padding is `NSPopUpButton`'s native bezel
  metrics.
- **Font**: `SemanticPalette.font(.body)` resolves the active theme's
  `.body` `TextRole`, whose system default (`ThemeTypography.defaultStyle`)
  is a 13pt, regular-weight, proportional system font, scaled by the
  theme's `sizeScale` and by the reader's live "Text Size" control
  (`readerScale`); an active theme MAY override `.body` with its own family/
  size/weight. Applied at initialization and reapplied on every theme
  change via `ThemePaletteObserver` (which falls back to the Solarized Dark
  theme when no `ThemeManager` exists, e.g. previews or tests run without
  an app host).
- **Background**: Not applicable — `contentTintColor` is the only color
  this file sets; the button's fill is `NSPopUpButton`'s native system
  bezel.
- **Foreground/Text**: `contentTintColor` is set to
  `SemanticPalette.primaryTextColor`, which resolves the theme's
  `.primaryText` `ThemeRole` (an explicit override if the active theme
  declares one, else a value derived from the theme's palette). Reapplied
  live on every theme change via the same `ThemePaletteObserver`.
- **Border**: Not applicable — no border is drawn or configured in source;
  the button keeps `NSPopUpButton`'s native bezel border.
- **Shadow**: Not applicable — no shadow is drawn or configured in source.
- **Min/Max size**: Not applicable — no explicit width/height constraint is
  set in source; the button's size is its `NSPopUpButton` intrinsic content
  size, recomputed on every title change via
  `invalidateIntrinsicContentSize()` (see
  **resizes-for-longer-titles**).

## Accessibility

- **Role/trait**: Not customized in source — no `setAccessibilityRole` or
  similar call appears anywhere in `MultiChoiceFilterButton.swift`; the
  control inherits `NSPopUpButton`'s native pull-down accessibility role,
  and each entry inherits `NSMenuItem`'s native checkable-menu-item
  semantics from its `state`.
- **Label requirements**: Not set via an explicit `accessibilityLabel`/
  `accessibilityTitle` override; VoiceOver's accessible name comes from
  `NSPopUpButton`'s native title-based naming, and by construction (see
  **formats-title-none-selected** through **formats-title-many-selected**)
  that title always states both `label`, the axis being filtered, and the
  current selection state, so the accessible name is never a bare, contextless
  string.
- **Announce state changes (e.g., loading, disabled)**: Not customized in
  source — the title mutation in `refreshTitle()` and each item's `state`
  change in `syncStates()` are AppKit's own native `NSPopUpButton`/
  `NSMenuItem` accessibility change notifications; this file posts no
  announcement of its own.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSControl` with no touch input path in source; the
  44×44pt minimum is iOS/touch guidance. Source sets no `controlSize` on
  the button, so it keeps `NSPopUpButton`'s regular system control metrics.
- **contrast**: NEEDS REVIEW: Not implemented in source. Text color (`contentTintColor` = `primaryTextColor`) and the button's bezel are both resolved from the active `ColorTheme` at runtime, and `MultiChoiceFilterButton.swift` performs no contrast check against that background; resolving it requires auditing each shipped `ColorTheme`'s `.primaryText`-vs-bezel contrast against a chosen accessibility bar (e.g., WCAG 2.1 AA's 4.5:1 for body-sized text), a call for the design/accessibility owner of the theme catalog, not this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `label` | `String` | — (required) | Names the filtered axis (e.g. `"Good for"`); prefixes every title-summary state and is item 0's own (unselectable) menu title. |
| `choices` | `[Choice]` | — (required) | The fixed, ordered list of selectable entries; also fixes the order `formats-title-few-selected` joins titles in. |
| `onChange` | `((Set<String>) -> Void)?` | `nil` | Assigned by the caller after construction; invoked with the new `selection` on every actual change (see **fires-on-change-on-actual-change**). |
| `Choice.id` | `String` | — (required) | Opaque identifier the caller maps back to its own type; membership in `selection` is keyed by this value. |
| `Choice.title` | `String` | — (required) | The menu item's display title and the text used in the few-selected title summary. |
| `Choice.detail` | `String` | `""` | Tooltip text for choices whose meaning a title alone can't carry; empty means no tooltip is set (see **sets-choice-tooltip**). |

