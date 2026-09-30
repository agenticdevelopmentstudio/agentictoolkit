<!-- leaf: implement-general-2/multi-choice-filter-button--part-2 · source: multi-choice-filter-button.md -->

# MultiChoiceFilterButton — continued (part 2)

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Any" | Menu item title and title-summary text shown when `selection` is empty; hardcoded in `buildMenu()`/`refreshTitle()`, not routed through any localization mechanism (no `NSLocalizedString` call in source). |
| n/a (literal) | "{n} selected" | Title-summary text shown when three or more choices are selected (`"\(chosen.count) selected"`); same caveat as above. |

Not applicable beyond the table above: `label` and each `Choice.title`/
`Choice.detail` are caller-supplied strings, not literals owned by this
file, so there is nothing else here for the component itself to localize.

`"Any"` and `"{n} selected"` are English literals assigned to AppKit titles
with no localization key, and the count string has no plural variant.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `MultiChoiceFilterButton.swift` contains no animation, transition, or `NSAnimationContext` call; every title and checkmark update is an instantaneous property assignment. |
| Increase Contrast | Not applicable: the file sets no custom `NSColor` beyond `contentTintColor`, sourced from the active theme's `.primaryText` role; the pull-down's bezel/border chrome is `NSPopUpButton`'s native rendering, which follows the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Supported: selection state is communicated through `NSMenuItem`'s built-in checkmark glyph (`item.state = .on`/`.off`), not through a color-only signal introduced by this component, so no separate path is needed. |

## Privacy

- **Data collected**: None beyond what the caller already supplies —
  `label`, `choices` (ids/titles/details), and the resulting `selection`
  are reported only to the caller's own `onChange` closure, in-process.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; if a caller wants to remember a
  filter across launches, that persistence and its restoration via
  `setSelection(_:)` are the caller's responsibility, not this file's.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The instance retains only `label`, `choices`, its own
  `selection`, `onChange`, and its `ThemePaletteObserver`, for its own
  lifetime; it persists nothing beyond that.

## Platform Notes

- **SwiftUI**: Build a `Menu` whose label is the computed summary string
  (mirroring `refreshTitle()`'s three branches), containing a `Button`
  ("Any") that clears the selection, a `Divider`, then a `Toggle` per
  choice bound to that choice's membership in the selection set — on
  macOS, a `Toggle` inside a `Menu` renders as a checkable menu item, the
  SwiftUI analog of `NSMenuItem.state`. Gate the write with an equality
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
  configured `pullsDown: true`. It builds a checkable `NSMenu` by hand
  (label item, "Any", separator, one item per choice with
  `representedObject` holding the choice's id), toggles membership in a
  `Set<String>` from each item's target-action, and repaints its title and
  theme colors through `refreshTitle()`/`applyTheme(_:)`. `refreshTitle()`
  satisfies **refreshes-title-synchronously** by calling
  `synchronizeTitleAndSelectedItem()` immediately after recomputing item
  0's title (a pull-down otherwise keeps the stale title until its menu is
  next reset), and satisfies **resizes-for-longer-titles** by calling
  `invalidateIntrinsicContentSize()` right after that, so the new width is
  measured immediately instead of truncating inside the previous width.
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
  `Content` from a summary string mirroring `refreshTitle()`'s three
  branches on every selection change — from each `ToggleMenuFlyoutItem.
  Click` handler, the "Any" item's click handler, and any programmatic
  selection-setting entry point (the WinUI analog of `setSelection(_:)`)
  alike — since WinUI has no built-in pull-down title binding the way
  `NSPopUpButton` redraws item 0's title. Set `AutomationProperties.Name` on
  the `DropDownButton` to the current summary text as well, so Narrator's
  accessible name stays in sync the way `NSPopUpButton`'s native
  title-based name does automatically.

## Design Decisions

**Decision**: Close the menu on every pick rather than give menu items their
own checkbox views to keep the menu open across multiple picks.
**Rationale**: Per the source's own comment, this is "the stock behaviour of
a checkable menu, and the alternative — items hosting their own checkbox
views to keep the menu open — trades a familiar control for a hand-built
one."
**Approved**: pending

**Decision**: Identify choices by opaque string ids rather than a caller's
own enum.
**Rationale**: Per the source's own comment, this lets "one control serve any
caller's enum without this file knowing about it; callers map ids back to
their own type."
**Approved**: pending

**Decision**: Show the full selected list at one or two choices and switch to
a bare count at three or more.
**Rationale**: Per the source's own comment, "the summary title says what is
on without opening it, and 'Any' clears the whole set in one click" — the
count branch exists because, past two items, the full list stops fitting
in a glance.
**Approved**: pending

**Decision**: Call `invalidateIntrinsicContentSize()` after every title
refresh.
**Rationale**: Per the source's own comment, "the title just changed length,
and the button's intrinsic width is measured from it — without this, a
longer summary lays out inside the old width and gets truncated ('Good
for: Cod…')."
**Approved**: pending

**Decision**: Leave `syncStates()` (checkmark resync) unconditional on every
toggle/"Any"/`setSelection(_:)` call, while gating `refreshTitle()` and
`onChange` behind `selection`'s `didSet` equality check.
**Rationale**: This is the source's as-written, verified behavior:
`syncStates()` is called directly from each method's body regardless of
whether the assignment above it actually changed `selection`, while the
title/`onChange` side effects live in `didSet` and are naturally suppressed
on a no-op assignment. Documented and required here (see
**reflects-checkmarks**) rather than smoothed into "both paths react
identically to a no-op."
**Approved**: pending

**Decision**: Do not deduplicate or reject `Choice` entries that share an
`id`.
**Rationale**: `selection` is a `Set<String>`, and `syncStates()` matches
menu items by their `representedObject` id, so two choices with the same
id are always kept in the same checked state as each other even though
they are visually distinct menu entries. The source enforces no
uniqueness constraint on `Choice.id`; keeping ids unique is a contract on
the caller, stated in Edge Cases.
**Approved**: pending
