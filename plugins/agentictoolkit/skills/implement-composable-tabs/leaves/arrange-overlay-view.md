<!-- leaf: implement-composable-tabs/arrange-overlay-view · source: composable-tabs-arrange-overlay-view.md -->

**Rules** (cite as `implement-composable-tabs/arrange-overlay-view#<slug>`):

- `dims-content-with-scrim` MUST
- `paints-toolbar-surface` MUST
- `applies-theme-immediately-and-on-change` MUST
- `centers-toolbar-column` MUST
- `caps-name-label-width` MUST
- `truncates-name-label-tail` MUST
- `toolbar-can-overhang-narrow-pane` MUST
- `updates-pane-name-on-assignment` MUST
- `exposes-add-button-as-anchor-view` MUST
- `invokes-add-callback-on-tap` MUST
- `invokes-remove-callback-on-tap` MUST
- `invokes-done-callback-on-tap` MUST
- `invokes-move-callback-on-selection` MUST
- `add-button-enablement-tracks-can-add` MUST
- `remove-button-enablement-tracks-can-remove` MUST
- `move-menu-rebuilt-on-refresh` MUST
- `move-item-enablement-tracks-available-directions` MUST
- `move-button-enablement-tracks-items` MUST
- `move-items-icons-match-direction` MUST
- `toolbar-buttons-show-icon-and-label` MUST
- `refresh-is-caller-driven` MUST
- `computes-initial-availability-at-construction` MUST
- `root-and-controls-carry-accessibility-identifiers` MUST
- `move-items-carry-prefixed-identifiers` MUST
- `coder-initialization-unsupported` MUST
- `done-button-has-no-key-equivalent` MUST
- `scrim-blocks-clicks-to-content` MUST
- `scrim-click-still-reaches-pane-selection` MUST

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
- **Announce state changes**: Not implemented. `refreshAvailability()`
  changes the enabled state of the Add, Remove, and Move controls (e.g.
  disabling Remove because the pane is now the last one, or disabling a
  Move direction because the pane reached the top of the window) without
  any `NSAccessibility.post(element:notification:)` call anywhere in this
  file, so a VoiceOver user hears nothing about the change until they
  navigate back onto the affected control.
- **Minimum tap target**: Each button uses AppKit's `.rounded` bezel style
  with no explicit frame set in source, so its height comes from AppKit's
  default intrinsic content size rather than a literal point value in this
  file; that default is well under the 44×44pt (iOS) / 48×48dp (Android)
  touch minimum, which is expected for a pointer/keyboard-driven macOS
  toolbar rather than a touch surface. That minimum applies to the
  touch-platform translations described in Platform Notes, not to this
  AppKit view.

