---
id: bfc2dcde-d905-4923-bff2-577c85f17d5f
title: ComposableTabsArrangeOverlayView
domain: agentictoolkit://recipes/composable-tabs-arrange-overlay-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Toolbar overlay that dims a composable-tabs pane and offers Add, Remove,
  Move, and Done controls while the window is in arrange mode.
platforms:
- swift
- macos
tags:
- composable-tabs
- arrange-mode
- overlay
- toolbar
- appkit
depends-on: []
related:
- agentictoolkit://recipes/composable-tabs-pane-view-controller
references: []
approved-by: ''
approved-date: ''
---

# ComposableTabsArrangeOverlayView

## Overview

`ComposableTabsArrangeOverlayView` is a macOS `NSView` that a composable-tabs
pane shows in place of its normal content while the enclosing window is in
arrange mode. It dims the pane's content behind a scrim and centers one small
toolbar over it — Add, Remove, a Move pull-down, and Done — plus the pane's
name, so the user always knows which pane they are about to rearrange even
though its content is unreadable underneath. The scrim is a real subview with
a translucent background rather than an alpha applied to the content, so it
can also swallow pointer clicks meant for that content, while still letting an
unhandled click travel up the responder chain to the pane's background view so
clicking a dimmed pane still selects it. `ComposableTabsPaneViewController`
installs and removes an instance of this view as arrange mode toggles for the
window, and re-reads `canAdd`/`canRemove`/`availableDirections` through
`refreshAvailability()` whenever the tab layout changes.

## Behavioral Requirements

- **dims-content-with-scrim**: Component MUST paint its own layer's
  background as `SemanticPalette.nsColor(.windowBackground)` at 72% opacity
  (`withAlphaComponent(0.72)`).
- **paints-toolbar-surface**: The toolbar container MUST render with an 8pt
  corner radius, a 1pt border, a background color of
  `SemanticPalette.nsColor(.elevatedSurface)`, and a border color of
  `SemanticPalette.nsColor(.border)`.
- **applies-theme-immediately-and-on-change**: Component MUST apply the
  active palette's colors to itself and the toolbar immediately when
  constructed, and MUST reapply them every time the active theme changes
  thereafter, via `observeTheme(_:)`.
- **centers-toolbar-column**: Component MUST center a column holding the
  pane-name label above the toolbar, with 10pt spacing between them,
  horizontally and vertically within its own bounds.
- **caps-name-label-width**: The pane-name label's width MUST be constrained
  to at most the overlay's own width minus 16pt.
- **truncates-name-label-tail**: The pane-name label MUST truncate
  overflowing text at the tail and MUST be center-aligned.
- **toolbar-can-overhang-narrow-pane**: Component MUST NOT constrain the
  centered column's leading, trailing, top, or bottom edges to its own
  bounds, so a toolbar wider than a narrow pane is allowed to overhang the
  pane's edges rather than forcing the pane wider.
- **updates-pane-name-on-assignment**: Assigning a new value to `paneName`
  MUST update the pane-name label's displayed text synchronously.
- **exposes-add-button-as-anchor-view**: `addButtonView` MUST return the
  exact `NSView` instance of the Add button.
- **invokes-add-callback-on-tap**: Clicking or activating the Add button MUST
  invoke the `onAdd` closure when one is set, and MUST have no observable
  effect when `onAdd` is `nil`.
- **invokes-remove-callback-on-tap**: Clicking or activating the Remove
  button MUST invoke the `onRemove` closure when one is set, and MUST have no
  observable effect when `onRemove` is `nil`.
- **invokes-done-callback-on-tap**: Clicking or activating the Done button
  MUST invoke the `onDone` closure when one is set, and MUST have no
  observable effect when `onDone` is `nil`.
- **invokes-move-callback-on-selection**: Choosing a direction from the Move
  pull-down MUST invoke the `onMove` closure, when set, with that direction,
  and MUST have no observable effect when `onMove` is `nil`.
- **add-button-enablement-tracks-can-add**: `refreshAvailability()` MUST set
  the Add button's enabled state to the current result of the `canAdd`
  closure.
- **remove-button-enablement-tracks-can-remove**: `refreshAvailability()`
  MUST set the Remove button's enabled state to the current result of the
  `canRemove` closure.
- **move-menu-rebuilt-on-refresh**: `refreshAvailability()` MUST discard and
  rebuild the Move pull-down's menu items on every call: it MUST keep the
  pull-down's own non-selectable title item first, then append exactly one
  item per `Direction` (a typealias for `ComposableTabsViewController.Direction`,
  whose four cases — `left`, `right`, `above`, `below` — display respectively
  as Left, Right, Up, Down), in `Direction.allCases` order (Left, Right, Up,
  Down).
- **move-item-enablement-tracks-available-directions**: Each rebuilt Move
  menu item's enabled state MUST equal whether `availableDirections()`
  contains that item's direction at the time of the rebuild.
- **move-button-enablement-tracks-items**: Component MUST enable the Move
  button if and only if at least one of its four rebuilt items is enabled.
- **move-items-icons-match-direction**: Each Move menu item MUST display a
  system symbol image matching its direction (`arrow.left`, `arrow.right`,
  `arrow.up`, `arrow.down` for Left, Right, Up, Down respectively), with an
  accessibility description equal to its title.
- **toolbar-buttons-show-icon-and-label**: The Add, Remove, and Done buttons
  MUST each display a leading system symbol icon (`plus`, `minus`,
  `checkmark`, respectively) alongside their text title, with an
  accessibility description equal to that title.
- **refresh-is-caller-driven**: Component MUST NOT observe or poll `canAdd`,
  `canRemove`, or `availableDirections` on its own; the Add, Remove, and Move
  controls MUST remain at whatever enabled state was last computed until
  `refreshAvailability()` is called again.
- **computes-initial-availability-at-construction**: Component MUST call
  `refreshAvailability()` once during initialization.
- **root-and-controls-carry-accessibility-identifiers**: The root view and
  the Add, Remove, Move, and Done controls, and the pane-name label, each
  MUST carry a fixed accessibility identifier (`composable-tabs.arrange.scrim`,
  `.add`, `.remove`, `.move`, `.done`, and `.pane-name`, respectively).
- **move-items-carry-prefixed-identifiers**: Each Move menu item's
  accessibility identifier MUST be the fixed prefix
  `composable-tabs.arrange.move` followed by a period and that item's
  lowercased movement name (e.g. `composable-tabs.arrange.move.left`).
- **coder-initialization-unsupported**: Component MUST NOT support
  initialization via `init(coder:)` and MUST fail fast (fatal error) if it is
  invoked.
- **done-button-has-no-key-equivalent**: The Done button MUST NOT be
  assigned a key equivalent.
- **scrim-blocks-clicks-to-content**: Component MUST cover the pane's content
  so pointer clicks aimed at that content do not reach it while the overlay
  is present.
- **scrim-click-still-reaches-pane-selection**: An unhandled click on the
  scrim's own bounds (outside its buttons) MUST still be able to reach the
  pane's background view above it in the responder chain, so clicking a
  dimmed pane still selects it.

## Appearance

- **Corner radius**: 8pt, on the toolbar container only; the scrim itself
  (`self`) has no corner radius.
- **Padding**: Toolbar: 8pt on all four sides between the button row and the
  toolbar's edges. Column: 10pt vertical spacing between the pane-name label
  and the toolbar. Button row: 8pt horizontal spacing between Add, Remove,
  Move, and Done.
- **Font**: The pane-name label's font is resolved via
  `SemanticPalette.font(.heading)` — the active theme's typography for the
  `.heading` text role — not a fixed literal size or weight in this file.
- **Background**: Scrim: `SemanticPalette.nsColor(.windowBackground)` at 72%
  opacity. Toolbar: `SemanticPalette.nsColor(.elevatedSurface)`, fully
  opaque.
- **Foreground/Text**: Pane-name label: `SemanticPalette.nsColor(.primaryText)`
  (the `role` the label is constructed with).
- **Border**: Toolbar: 1pt, `SemanticPalette.nsColor(.border)`. The scrim
  itself has no border.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: Not set within this file beyond the pane-name label's
  width cap (at most the overlay's own width minus 16pt); the overlay's own
  frame is sized entirely by the caller's Auto Layout constraints against the
  pane view (`ComposableTabsPaneViewController.installArrangeOverlay()`),
  which is outside this file.

## States

| State | Appearance change |
|-------|------------------|
| Default | Scrim dims the content; toolbar and pane name are centered, with each control's enabled state reflecting the last `refreshAvailability()` call. |
| Add disabled (`canAdd()` is `false`) | The Add button is rendered in AppKit's standard disabled (dimmed) style and does not send its action. |
| Remove disabled (`canRemove()` is `false`) | The Remove button is rendered disabled the same way. |
| Move disabled (no directions in `availableDirections()`) | All four Move menu items are disabled and the Move button itself is disabled. |
| Pressed | Not applicable: no custom pressed-state styling exists in source; AppKit's default `.rounded` bezel press highlight applies unmodified to every button. |
| Focused | Not applicable: no custom focus-ring styling exists in source; AppKit's default keyboard-focus ring applies unmodified. |
| Loading | Not applicable: no asynchronous operation or loading indicator exists anywhere in this file. |

## Accessibility

- **Role/trait**: Not explicitly set via `setAccessibilityRole` anywhere in
  source; the Add/Remove/Done buttons, the Move pull-down, and the pane-name
  label all use AppKit's default roles for `NSButton`, `NSPopUpButton`, and
  `NSTextField` respectively.
- **Label requirements**: The root view and every control carry an explicit
  accessibility identifier for automation (`composable-tabs.arrange.scrim`,
  `.add`, `.remove`, `.move`, `.done`, `.pane-name`, and one
  `.move.<direction>` per Move item). Each button's `NSImage` is given an
  `accessibilityDescription` equal to its title (`Add`, `Remove`, `Done`, and
  each Move item's movement name), and each control's own visible title text
  is otherwise the label AppKit exposes to VoiceOver by default; source sets
  no separate `accessibilityLabel` override beyond that.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. `refreshAvailability()` changes the enabled state of
  the Add, Remove, and Move controls (e.g. disabling Remove because the
  pane is now the last one, or disabling a Move direction because the pane
  reached the top of the window) with no
  `NSAccessibility.post(element:notification:)` call anywhere in this file.
  What is missing: whether a VoiceOver user is told an arrange control just
  became unavailable, or hears nothing until they navigate back onto that
  control. What would settle it: a VoiceOver pass over an active arrange
  session while removing panes down to one, or an explicit decision to post
  an accessibility notification from `refreshAvailability()`.
- **Minimum tap target**: Each button uses AppKit's `.rounded` bezel style
  with no explicit frame set in source, so its height comes from AppKit's
  default intrinsic content size rather than a literal point value in this
  file; that default is well under the 44×44pt (iOS) / 48×48dp (Android)
  touch minimum, which is expected for a pointer/keyboard-driven macOS
  toolbar rather than a touch surface. That minimum applies to the
  touch-platform translations described in Platform Notes, not to this
  AppKit view.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-arrange-overlay-001 | dims-content-with-scrim | Inspect `layer?.backgroundColor` immediately after construction | Equals `SemanticPalette.nsColor(.windowBackground).withAlphaComponent(0.72).cgColor` for the active palette |
| composable-tabs-arrange-overlay-002 | paints-toolbar-surface | Inspect the toolbar's layer after construction | `cornerRadius == 8`, `borderWidth == 1`, `backgroundColor == elevatedSurface.cgColor`, `borderColor == border.cgColor` |
| composable-tabs-arrange-overlay-003 | applies-theme-immediately-and-on-change | Construct the view under theme A, then switch the active theme to B | Colors match theme A's palette immediately after construction, and update to match theme B's palette after the switch, with no further action taken |
| composable-tabs-arrange-overlay-004 | centers-toolbar-column | Inspect the column's constraints after construction | `centerXAnchor`/`centerYAnchor` are each constrained equal to the view's own center; the label-to-toolbar spacing in the column is 10pt |
| composable-tabs-arrange-overlay-005 | caps-name-label-width | Inspect `nameLabel`'s width constraint after construction | A `lessThanOrEqualTo` constraint against the view's `widthAnchor` with constant `-16` exists |
| composable-tabs-arrange-overlay-006 | truncates-name-label-tail | Set `paneName` to a string wider than the label's constrained width | `nameLabel.lineBreakMode == .byTruncatingTail` and `nameLabel.alignment == .center` |
| composable-tabs-arrange-overlay-007 | toolbar-can-overhang-narrow-pane | Inspect the column's constraints against the view for leading/trailing/top/bottom pins | No such constraint exists; only centerX/centerY constraints tie the column to the view |
| composable-tabs-arrange-overlay-008 | updates-pane-name-on-assignment | Set `paneName = "Editor"` | `nameLabel.stringValue == "Editor"` immediately after the assignment returns |
| composable-tabs-arrange-overlay-009 | exposes-add-button-as-anchor-view | Read `addButtonView` | Returns the same `NSView` instance used as the Add button |
| composable-tabs-arrange-overlay-010 | invokes-add-callback-on-tap | Set `onAdd` to a closure that increments a counter, then click the Add button | Counter increments by exactly 1 |
| composable-tabs-arrange-overlay-011 | invokes-add-callback-on-tap | Leave `onAdd` as `nil`, then click the (enabled) Add button | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-012 | invokes-remove-callback-on-tap | Set `onRemove` to a closure that increments a counter, then click the Remove button | Counter increments by exactly 1 |
| composable-tabs-arrange-overlay-013 | invokes-remove-callback-on-tap | Leave `onRemove` as `nil`, then click the (enabled) Remove button | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-014 | invokes-done-callback-on-tap | Set `onDone` to a closure that increments a counter, then click the Done button | Counter increments by exactly 1 |
| composable-tabs-arrange-overlay-015 | invokes-done-callback-on-tap | Leave `onDone` as `nil`, then click the Done button | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-016 | invokes-move-callback-on-selection | Set `onMove` to a closure capturing its argument; `availableDirections` returns `{.left}`; choose the "Left" Move item | Closure is invoked exactly once with `.left` |
| composable-tabs-arrange-overlay-017 | invokes-move-callback-on-selection | Leave `onMove` as `nil`; choose an enabled Move item | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-018 | add-button-enablement-tracks-can-add | Set `canAdd = { false }`, then call `refreshAvailability()` | `addButton.isEnabled == false` |
| composable-tabs-arrange-overlay-019 | remove-button-enablement-tracks-can-remove | Set `canRemove = { false }`, then call `refreshAvailability()` | `removeButton.isEnabled == false` |
| composable-tabs-arrange-overlay-020 | move-menu-rebuilt-on-refresh | Call `refreshAvailability()` twice in a row | The Move menu's first item is still its original title item, followed by exactly 4 items, in both cases, in Left/Right/Up/Down order |
| composable-tabs-arrange-overlay-021 | move-item-enablement-tracks-available-directions | Set `availableDirections = { [.left, .above] }`, then call `refreshAvailability()` | The "Left" and "Up" items are enabled; "Right" and "Down" are disabled |
| composable-tabs-arrange-overlay-022 | move-button-enablement-tracks-items | Set `availableDirections = { [] }`, then call `refreshAvailability()` | `moveButton.isEnabled == false` |
| composable-tabs-arrange-overlay-023 | move-button-enablement-tracks-items | Set `availableDirections = { [.right] }`, then call `refreshAvailability()` | `moveButton.isEnabled == true` |
| composable-tabs-arrange-overlay-024 | move-items-icons-match-direction | Inspect the "Up" Move item after `refreshAvailability()` | Its `image` is the `arrow.up` system symbol and its `accessibilityDescription` equals "Up" |
| composable-tabs-arrange-overlay-025 | toolbar-buttons-show-icon-and-label | Inspect the Remove button after construction | `image` is the `minus` system symbol, `accessibilityDescription == "Remove"`, `imagePosition == .imageLeading` |
| composable-tabs-arrange-overlay-026 | refresh-is-caller-driven | Change what `canAdd` returns without calling `refreshAvailability()` | `addButton.isEnabled` remains at its previously computed value |
| composable-tabs-arrange-overlay-027 | computes-initial-availability-at-construction | Construct the view with `canAdd = { false }` and never call `refreshAvailability()` again | `addButton.isEnabled == false` immediately after construction |
| composable-tabs-arrange-overlay-028 | root-and-controls-carry-accessibility-identifiers | Inspect `accessibilityIdentifier()` on the root view and each control after construction | Equal `composable-tabs.arrange.scrim`, `.add`, `.remove`, `.move`, `.done`, and `.pane-name` respectively |
| composable-tabs-arrange-overlay-029 | move-items-carry-prefixed-identifiers | Call `refreshAvailability()` (it takes no parameters) after construction | The "Left" item's identifier is `composable-tabs.arrange.move.left`, produced by `refreshAvailability()`'s internal call to `moveMenu.makeItems(accessibilityPrefix: "composable-tabs.arrange.move")` |
| composable-tabs-arrange-overlay-030 | coder-initialization-unsupported | Attempt `ComposableTabsArrangeOverlayView(coder:)` | The call traps with a fatal error; no instance is returned |
| composable-tabs-arrange-overlay-031 | done-button-has-no-key-equivalent | Inspect `doneButton.keyEquivalent` after construction | Equals `""` |
| composable-tabs-arrange-overlay-032 | scrim-blocks-clicks-to-content | With the overlay installed over a pane's content view, click a point over the scrim but off any button | The content view underneath receives no mouse or key event for that click |
| composable-tabs-arrange-overlay-033 | scrim-click-still-reaches-pane-selection | With the overlay installed over an unselected pane, click a point over the scrim but off any button | The pane becomes the selected pane, via the click reaching `ComposableTabsPaneBackgroundView`'s selection handling through the responder chain |

## Edge Cases

- Null/empty input (MUST): `paneName` defaults to `""` and setting it to `""`
  is valid — the label simply shows no text; nothing in source guards or
  rejects an empty pane name. `onAdd`, `onRemove`, `onMove`, and `onDone`
  default to `nil` and are always invoked through optional chaining
  (`onAdd?()`, etc.), so an unset callback is a documented no-op, not an
  error.
- Boundary values (MUST): `availableDirections` can return the empty set
  (disabling the entire Move button) or all four directions (enabling every
  Move item); `canAdd`/`canRemove` are plain booleans with only two possible
  results, each directly reflected in the corresponding button's enabled
  state on the next `refreshAvailability()` call. The caller is expected to
  return `false` from `canRemove` for the last remaining pane and to omit a
  direction from `availableDirections` when the pane is already at that
  edge of the window (e.g. no `Up` for a
  pane already at the top). The caller's responsibility for these boundary
  decisions is the reason `refresh-is-caller-driven` exists: this view has no
  independent knowledge of "last pane" or "top of window" itself, it only
  renders whatever the closures currently report.
- Concurrent access: Not applicable — the class is declared `@MainActor`, so
  Swift's concurrency checker confines all reads and writes of its state and
  UI to the main actor; source provides no path for two threads to mutate
  this view simultaneously.
- Error states: Not applicable — every operation in this file (a button tap
  invoking a callback, `refreshAvailability()` rebuilding menu items, a
  theme change repainting colors) is synchronous and non-throwing; no
  network, database, or file-system call exists anywhere in this file that
  could fail.
- Offline/disconnected: Not applicable — this is a purely local UI overlay
  with no networking call anywhere in source.
- Stale availability between refreshes (MUST): Per `refresh-is-caller-driven`,
  if the data behind `canAdd`, `canRemove`, or `availableDirections` changes
  without a subsequent call to `refreshAvailability()`, the affected
  control(s) MUST continue to show their previously computed enabled state;
  this view performs no polling or tree observation of its own; that
  responsibility belongs to the caller (`ComposableTabsPaneViewController`
  observes `ComposableTabsViewController.layoutDidChangeNotification` and
  calls `refreshAvailability()` itself).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `paneName` | `String` | `""` | Name shown above the toolbar; setting it updates the label immediately. |
| `onAdd` | `(() -> Void)?` | `nil` | Invoked when the Add button is tapped. |
| `onRemove` | `(() -> Void)?` | `nil` | Invoked when the Remove button is tapped. |
| `onMove` | `((Direction) -> Void)?` | `nil` | Invoked with the chosen direction when a Move menu item is selected. |
| `onDone` | `(() -> Void)?` | `nil` | Invoked when the Done button is tapped. |
| `canAdd` | `() -> Bool` | `{ true }` | Re-read by `refreshAvailability()` to set the Add button's enabled state. |
| `canRemove` | `() -> Bool` | `{ true }` | Re-read by `refreshAvailability()` to set the Remove button's enabled state. |
| `availableDirections` | `() -> Set<Direction>` | `{ [] }` | Re-read by `refreshAvailability()` to decide which Move menu items are enabled. |

## Deep Linking

Not applicable: this is an internal overlay view with no URL scheme, route,
or deep-link handler in source; `ComposableTabsPaneViewController` installs
and removes it programmatically as `ComposableTabsArrangeMode` toggles for
the window.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Add" | Add button title |
| n/a (literal) | "Remove" | Remove button title |
| n/a (literal) | "Move" | Move pull-down's own fixed title item |
| n/a (literal) | "Done" | Done button title |

Not applicable beyond the table above: the pane-name text shown by
`paneName` is supplied by the caller (an already-resolved display name from
elsewhere in the app), not a literal string this file owns.

NEEDS REVIEW: Not implemented in source. The `"Add"`, `"Remove"`, and `"Done"` button titles (ComposableTabsArrangeOverlayView.swift:53–55) and the `"Move"` pull-down title are — plain `String` literals, none routed through `String(localized:)` or `NSLocalizedString`, so none reaches a string catalog. What is missing: localization keys and catalog entries for the four titles. What would settle it: routing the literals through `String(localized:)` in source.

## Accessibility Options

- **Reduce Motion**: Not applicable — no animation, transition, or
  `NSAnimationContext` call appears anywhere in this file; every state
  change (theme repaint, `refreshAvailability()`) is an instantaneous
  property assignment.
- **Increase Contrast**: Not applicable — this file has no independent
  Increase Contrast handling of its own; every color value routes through
  `SemanticPalette.nsColor(_:)`, and whether the active theme itself
  responds to increased contrast is that theme's responsibility, not this
  view's.
- **Differentiate Without Color**: Satisfied — a disabled control (Add,
  Remove, or a Move item) is conveyed by AppKit's standard dimmed rendering
  and by no longer responding to input, not by color alone; each Move item
  is additionally labeled by both a text title and a directional arrow
  icon.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
this file; the view always renders once constructed and installed by its
caller.

## Analytics

Not applicable: this file contains no analytics or telemetry call; `onAdd`,
`onRemove`, `onMove`, and `onDone` are plain consumer-supplied callbacks with
no tracking of their own.

## Privacy

- **Data collected**: None by this component — `paneName` is a display
  string supplied by the caller, held only for display.
- **Storage**: In-memory only, for the view's lifetime; nothing is written
  to disk, `UserDefaults`, or any other store by this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: None beyond the view's lifetime; state is discarded when
  `ComposableTabsPaneViewController.removeArrangeOverlay()` removes and
  releases the instance.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
logger reference anywhere in this file).

## Platform Notes

- **SwiftUI**: Layer a `ZStack` of the pane's content behind a scrim colored
  by the consumer's semantic-palette lookup for `.windowBackground` at 0.72
  opacity (SwiftUI has no built-in `Color(role:)` initializer; this is the
  same lookup `SemanticPalette.nsColor(_:)` performs on the source platform),
  and center a `VStack(spacing: 10)` of the pane-name `Text` above an
  `HStack(spacing: 8)` toolbar (`RoundedRectangle(cornerRadius: 8)` background in
  `.elevatedSurface`, `.strokeBorder(.border, lineWidth: 1)`) of `Button`s
  and a `Menu` in place of the `NSPopUpButton`. Because SwiftUI gesture
  modifiers consume the touches they attach to rather than letting them
  bubble to an ancestor the way AppKit's default `mouseDown` forwarding
  does, achieving `scrim-click-still-reaches-pane-selection` needs the
  scrim's own tap handler to explicitly re-invoke the same "select this
  pane" closure the content view uses, rather than relying on any automatic
  propagation.
- **Compose**: Use a `Box` whose bottom layer is the pane's content and
  whose top layer is a `Modifier.background(...alpha = 0.72f)` scrim,
  centering a `Column` (pane-name `Text` plus a `Card`/`Surface` toolbar
  `Row` of `Button`s, each showing a leading `Icon` plus text `Text`
  (mirroring `toolbar-buttons-show-icon-and-label`), 8dp corner radius, 1dp
  border, elevatedSurface background) via `Modifier.align(Alignment.Center)`.
  Give the scrim's `Box` a `pointerInput` block that consumes events (mirroring
  `scrim-blocks-clicks-to-content`), and, since Compose has no equivalent of
  AppKit's automatic bubble-to-ancestor for an unhandled touch, wire that
  same `pointerInput` handler to call the pane's own "select" function
  directly (mirroring `scrim-click-still-reaches-pane-selection`).
- **React/Web**: An absolutely positioned `<div>` covering the pane's
  content, with `background: rgba(<windowBackground>, 0.72)`, containing a
  centered flex column (10px gap) of the pane name above a flex row (8px
  gap, 8px padding, 8px border-radius, 1px solid border, elevatedSurface
  background) of `<button>` elements. The scrim's default `pointer-events:
  auto` already gives `scrim-blocks-clicks-to-content` for free; leave the
  scrim's own `onClick` handler unset (or set to one that does not call
  `stopPropagation()`), so an unhandled click naturally bubbles up to the
  pane container's own click listener, giving
  `scrim-click-still-reaches-pane-selection` via the DOM's own
  event-bubbling to an ancestor listener — no explicit re-invocation of the
  "select this pane" handler is needed, unlike SwiftUI/Compose, where
  gesture modifiers consume the touch before it can propagate.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsArrangeOverlayView.swift`
  as a `@MainActor`, `final` `NSView` built from `NSStackView`s and Auto
  Layout constraints, installed and removed as a subview by
  `ComposableTabsPaneViewController.installArrangeOverlay()`/
  `removeArrangeOverlay()` whenever `ComposableTabsArrangeMode` toggles for
  the window. Theming comes from `observeTheme(_:)`/`SemanticPalette`, and
  the four Move directions come from the shared `ComposableTabsMoveMenu`
  class, reused by the pane's own gear menu. There is no UIKit code path in
  source (the imports — `AppKit`, `AgenticToolkitCore`,
  `AgenticToolkitCoreMacOS` — are macOS-only); a UIKit port would replace
  `NSButton`/`NSPopUpButton` with `UIButton`/`UIMenu`, replace the
  responder-chain click-through with an explicit `UITapGestureRecognizer` on
  the scrim that calls the pane-select handler directly (UIKit has no
  equivalent of AppKit's free unhandled-`mouseDown` forwarding), and would
  need each control's tappable area grown to at least 44×44pt.
- **WinUI 3** (the reason this recipe exists): Build the scrim as a
  dedicated `Border`/`Rectangle` filling the pane,
  `Background="{ThemeResource WindowBackgroundBrush}"` with `Opacity="0.72"`
  set on that element alone — not on a `Grid` that also hosts the toolbar,
  since WinUI's `Opacity` dims an entire subtree and would otherwise fade
  the toolbar too, unlike AppKit's layer-alpha, which only dims `self`'s own
  layer while the toolbar is a separate opaque sibling layer.
  `WindowBackgroundBrush`, `ElevatedSurfaceBrush`, and `BorderBrush` are not
  built-in WinUI 3 resources; they are app-defined theme resource keys the
  consumer supplies to mirror `SemanticPalette`'s roles. Stack a `TextBlock`
  (style `SubtitleTextBlockStyle`, matching the `.heading` text role) above a
  `Border` toolbar (`CornerRadius="8"`, `BorderThickness="1"`,
  `BorderBrush="{ThemeResource BorderBrush}"`,
  `Background="{ThemeResource ElevatedSurfaceBrush}"`) containing a
  horizontal `StackPanel` (`Spacing="8"`) of `Button`s with icon+text
  `Content` (mirroring `imagePosition = .imageLeading`), replacing the
  `NSPopUpButton` pull-down with a `DropDownButton` whose `Flyout` is a
  `MenuFlyout` built the same way `ComposableTabsMoveMenu.makeItems` is: one
  `MenuFlyoutItem` per `Direction.allCases`, each `IsEnabled` bound to
  whether `availableDirections()` contains it, each `Icon` a matching arrow
  `SymbolIcon`/`FontIcon`, and `Text` set to the movement name (Left, Right,
  Up, Down). WinUI's `Tapped`/`PointerPressed` are routed events that bubble
  automatically from the source element up through its visual-tree
  ancestors, invoking any ancestor's handler unless something upstream sets
  `e.Handled = true` — the opposite of the claim that they arrive
  pre-handled. `scrim-click-still-reaches-pane-selection` therefore falls out
  of that default bubbling as long as the pane's selection handler is
  attached to an ancestor of the scrim and nothing along the way marks the
  event handled; this is the mirror image of AppKit, where it is an
  *unhandled* `mouseDown` that walks the responder chain. Implementors should
  still confirm no intervening `Border`/`Grid` handler marks `e.Handled`,
  since that is the one way the click would fail to reach the pane's
  selection handler — call this out to implementors as a deliberate platform
  difference worth verifying rather than assuming. Bind `IsEnabled` on the
  Add/Remove `Button`s to `canAdd`/`canRemove` the same way
  `refreshAvailability()` re-reads them, and leave the Done `Button` with no
  `AccessKey` bound, mirroring `done-button-has-no-key-equivalent`.

## Design Decisions

**Decision**: Implement the scrim as a real `NSView` subview with its own
translucent layer background, rather than as an alpha applied to the pane's
existing content.
**Rationale**: An alpha applied to the content would still let clicks reach
it, defeating the point of arrange mode; a real covering view intercepts
pointer clicks, while still remaining a subview of the pane's backdrop so an
unhandled click can travel up the responder chain to select the pane.
**Approved**: pending

**Decision**: Dim toward `SemanticPalette.nsColor(.windowBackground)` at 72%
opacity rather than toward black.
**Rationale**: Dimming toward the window background keeps a light theme
light — the content should read as behind something, not as switched off,
which dimming toward black would suggest regardless of the active theme.
**Approved**: pending

**Decision**: Give the Done button no key equivalent, even though Return,
Enter, and Escape already leave arrange mode.
**Rationale**: None of those existing shortcuts is visible, and a toolbar
that shows every other action arrange mode supports owes the way out the
same billing; no single button can claim the default `\r` equivalent
window-wide, since every pane in the window carries one of these buttons and
a window with four default buttons would have none.
**Approved**: pending

**Decision**: Reuse `ComposableTabsMoveMenu` for the Move pull-down's items
instead of building the four-direction list, labels, icons, and enablement
rule inline in this view.
**Rationale**: The pane's gear menu needs the identical four directions,
labels, arrows, and legality rule; keeping that knowledge in one shared
object avoids a second place to miss when a direction is added or a name
changes.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

Keyboard-navigable passes because the Add, Remove, Move, and Done controls
are all standard `NSButton`/`NSPopUpButton` instances that source never
opts out of Tab focus or Space/Return activation for. Screen-reader-support
passes because every control carries either a visible title, an
`accessibilityDescription` on its image equal to that title, or both.
Focus-management is partial because this file installs no explicit
first-responder or focus-trapping logic of its own (see **Announce state
changes** under Accessibility for the related gap in surfacing enablement
changes); whether focus is otherwise handled correctly rests on
`ComposableTabsPaneViewController`'s install/remove calls, which are outside
this file. Contrast-ratio is partial because every color comes from
`SemanticPalette`, whose actual resolved values are not stated in this
source. String-externalization is failed because "Add", "Remove", "Move",
and "Done" are hardcoded English literals with no localization key.
Touch-target-size and differentiate-without-color are omitted: the former
does not apply to this pointer/keyboard-driven macOS toolbar (AppKit's
default `.rounded` bezel height is well under the touch-platform threshold
by design, not by defect — the threshold does apply to the touch-platform
translations in Platform Notes), and the latter is not a check defined in
the accessibility compliance catalog, though the same concern is addressed
directly under **Accessibility Options** below.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: fixed scrim-opacity wording, removed unverified keystroke-blocking claim, restated source-comment citations as direct claims, qualified the Direction type, corrected the accessibility-prefix and test-vector-029 API mismatch, fixed compose/swiftui/winui/web platform-note errors, replaced "Tapping" with "clicking or activating", reformatted Design Decisions, corrected the Compliance table to only cite checks defined in the catalog, and fixed frontmatter tags/related/change-history |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Recorded the unlocalized Add/Remove/Done/Move button literals as an open question |
