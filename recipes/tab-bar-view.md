---
id: 5c0cc9f5-bc89-4e06-8d24-3db6424ff075
title: TabBarView
domain: agentictoolkit://recipes/tab-bar-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "AppKit NSView rendering an edge-docked NSStackView of pill tab buttons for MultiTabbedViewController, with selection restyling and vertical-edge card stacking."
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/multi-tabbed-view-controller
references: []
approved-by: ''
approved-date: ''
---

# TabBarView

## Overview

`TabBarView` is a `@MainActor` `NSView`
(`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabBarView.swift`)
that renders the edge-aligned tab strip for `MultiTabbedViewController`: one
pill-style button per tab, laid out inside an `NSStackView` whose orientation
follows the bar's `Edge` (top/bottom lay tabs out in a row, left/right in a
column). It owns no selection or ordering policy of its own — `items` and
`selectedID` are handed to it by `setItems(_:selectedID:)`, and it reports user
intent back to its owner purely through three closures (`onSelect`, `onClose`,
`onReorder`) so it stays decoupled from `MultiTabbedViewController`'s public
API. Two private helper types live in the same file and are described here
because neither has a recipe of its own within this file's scope:
`TabItemHostView`, which wraps a hosted `.viewController` item's view so a
click anywhere on it selects the tab, and `TabButton`, the pill control that
renders a `.title` item with its own close icon.

## Behavioral Requirements

- **thickness-floor-by-edge**: `TabBarView.preferredThickness(for:)` MUST
  return `28pt` for `.top`/`.bottom` and `140pt` for `.left`/`.right`.
- **orientation-follows-edge**: The component MUST set its stack's
  `orientation` to `.horizontal` for a `.top`/`.bottom` bar and to `.vertical`
  for a `.left`/`.right` bar.
- **alignment-favors-workspace-side**: The component MUST set its stack's
  `alignment` to the side of the bar adjacent to the workspace/content area
  it frames: `.bottom` for `.top`, `.top` for `.bottom`, `.trailing` for
  `.left`, and `.leading` for `.right`.
- **item-spacing-by-orientation**: The component MUST set its stack's
  `spacing` to `4pt` (`itemSpacing`) when the bar is horizontal and to
  `-16pt` (`cardOverlap`, a negative gap) when it is vertical.
- **start-inset-defaults-to-end-padding**: `startInset` MUST default to
  `8pt` (`endPadding`) and MUST re-apply the stack's edge insets whenever it
  is changed.
- **host-may-override-start-inset**: A host MAY set `startInset` to a value
  other than the default, to line a bar's first item up with chrome outside
  the bar; the component itself has no opinion on what that chrome is.
- **outer-padding-on-window-side-only**: The component MUST apply `6pt`
  (`outerPadding`) of inset on the bar's outer (window) side and `0pt` on its
  workspace side, with `startInset` at the bar's start (along its length) and
  `8pt` (`endPadding`) at its end.
- **bar-fills-perpendicular-and-pins-length**: For a `.top`/`.bottom` bar, the
  component MUST pin the stack's top, leading, trailing, and bottom edges to
  its own corresponding edges and install a height constraint; for a
  `.left`/`.right` bar, MUST pin the stack's top, leading, and trailing edges
  to its own, install a width constraint, and constrain the stack's bottom
  edge only `lessThanOrEqualTo` its own bottom.
- **vertical-bar-packs-from-top**: On a `.left`/`.right` bar, unused column
  height below the stack's content MUST remain empty rather than stretching
  the arranged items, as a direct consequence of the `lessThanOrEqualTo`
  bottom constraint in **bar-fills-perpendicular-and-pins-length**.
- **bar-fills-window-background**: The component MUST paint its own layer
  background with the `.windowBackground` palette role and MUST repaint it
  whenever the resolved theme palette changes.
- **set-items-triggers-rebuild**: `setItems(_:selectedID:)` MUST store the
  given items and selected id on the component and MUST call
  `rebuildButtons()` to reconstruct the bar's arranged subviews from them.
- **set-selected-restyles-and-reorders**: `setSelected(_:)` MUST update
  `selectedID`, MUST set `isHighlighted` to `true` on exactly the `TabButton`
  and any `TabBarHostedItem`-conforming hosted controller whose id equals the
  new selection and to `false` on every other one, and MUST call
  `applyStackOrder()` afterward.
- **stack-depth-by-distance-from-selection**: `applyStackOrder()` MUST
  compute each item's depth as the absolute difference between its index and
  the selected item's index, or `1` for every item when nothing is selected,
  and MUST report that depth to any hosted controller conforming to
  `TabBarStackedItem`.
- **vertical-edge-cards-overlap-and-order-by-distance**: On a `.left`/`.right`
  bar, `applyStackOrder()` MUST re-insert each `.viewController` item's
  wrapper view, deepest-first, via `addSubview(_:positioned: .above,
  relativeTo: nil)`, so the item nearest the selection ends up frontmost in
  both z-order and hit-testing; ties in depth MUST be broken by descending
  index.
- **rename-title-item**: `renameItem(id:title:)` MUST set the matching
  item's payload to `.title(title)` and MUST update that id's `TabButton`
  title when an item with the given id exists in `items`, and MUST be a
  silent no-op when no item has that id.
- **rebuild-clears-and-repopulates**: `rebuildButtons()` MUST remove every
  current arranged subview from the stack and MUST clear the `buttons` and
  `hostViews` dictionaries before repopulating them from `items`.
- **cross-edge-move-preserves-foreign-controller**: When reconciling hosted
  controllers, `rebuildButtons()` MUST remove a superseded controller's view
  from its superview and remove the controller from its parent only when
  that view's current superview is still this bar's own (now-stale) host
  wrapper; it MUST leave the view and parent relationship untouched when the
  view has already been reparented onto a different bar.
- **rebuild-drops-stale-hosted-controllers**: `rebuildButtons()` MUST clear
  an id's entry from `hostedControllers` whenever that id's current
  `.viewController` payload differs by identity from the previously hosted
  controller (including when the id is no longer present in `items` at all),
  independent of whether **cross-edge-move-preserves-foreign-controller**
  also tore down its view.
- **title-item-becomes-button**: For each `.title(title)` item,
  `rebuildButtons()` MUST create a `TabButton`, set its `isHighlighted` to
  match `selectedID`, wire its `onSelect`/`onClose` to the bar's own
  `onSelect`/`onClose`, add it as an arranged subview, and MUST additionally
  pin its cross-axis edges (via `pinCrossAxis(_:)`) only when the stack's
  orientation is `.vertical`.
- **viewcontroller-item-becomes-hosted-view**: For each `.viewController`
  item, `rebuildButtons()` MUST add the controller as a child of
  `hostController` when it is not already its parent, set `isHighlighted` and
  `onClose` on it when it conforms to `TabBarHostedItem`, wrap its view in a
  `TabItemHostView` wired to the bar's `onSelect`, add that wrapper as an
  arranged subview, and MUST pin the wrapper's cross-axis edges unconditionally
  (regardless of the stack's orientation).
- **thickness-grows-with-hosted-content**: `updateThickness()` MUST set the
  thickness constraint's constant to the greater of
  `preferredThickness(for: edge)` and (the largest hosted controller's
  `preferredContentSize` on the bar's thickness axis, plus `6pt`/
  `outerPadding`), and MUST be recomputed at the end of every
  `rebuildButtons()` call.
- **host-view-fills-hosted-content**: `TabItemHostView` MUST pin its wrapped
  content view's top, leading, trailing, and bottom edges to its own
  corresponding edges.
- **host-view-click-selects**: `TabItemHostView.mouseDown(with:)` MUST
  invoke `onSelect(id)` for a click that lands on the wrapper itself, without
  intercepting a click an interior subview (such as a hosted item's own close
  control) already handles as the frontmost hit-tested view.
- **close-icon-hit-routes-to-close**: `TabButton.mouseDown(with:)` MUST route
  a mouse-down whose location, converted into `backgroundView`'s coordinate
  space, falls inside `closeButton.frame` to `closeButton`'s own native
  handling (via `super.mouseDown(with:)`) and MUST NOT call `onSelect` in
  that case; it MUST call `onSelect(id)` for a mouse-down anywhere else in
  the view.
- **accessibility-press-always-selects**: `TabButton.accessibilityPerformPress()`
  MUST always call `onSelect(id)` and return `true`, regardless of where an
  assistive-technology press targets the element — unlike a physical click,
  it never routes to the close action.
- **tab-button-is-accessible-element**: `TabButton.init` MUST set
  `accessibilityElement` to `true`, MUST set `accessibilityRole` to
  `.button`, and MUST set the view's initial `accessibilityTitle` and
  `accessibilityValue` from the constructor's `title` and `isHighlighted`.
- **tab-button-title-updates-accessibility**: Setting `TabButton.title` MUST
  update both `titleLabel.stringValue` and the view's `accessibilityTitle` to
  the new value.
- **tab-button-highlight-updates-accessibility-value**: Setting
  `TabButton.isHighlighted` MUST update the view's `accessibilityValue` to
  the new value and MUST call `updateAppearance()`.
- **close-button-republished-as-sole-child**: `TabButton.accessibilityChildren()`
  MUST return exactly `[closeButton]`, so the close control stays reachable
  in the accessibility tree once `TabButton` becomes a single accessibility
  element.
- **close-button-carries-per-tab-identifier**: `TabButton.init` MUST give
  `closeButton` the accessibility identifier `tab-bar.close.<id>` and MUST
  give the tab button itself `tab-bar.select.<id>`, both keyed by the tab's
  own UUID.
- **selecting-a-tab-restyles-its-button**: `TabButton.updateAppearance()`
  MUST fill `backgroundView` with the `.selection` palette role, set
  `titleLabel.role` to `.selectionText`, and set `closeButton.contentTintColor`
  to `.selectionText` when `isHighlighted` is `true`; it MUST use
  `NSColor.clear`, `.secondaryText`, and `.tertiaryText` respectively when it
  is `false`.
- **declares-reorder-callback**: The component MUST expose a public
  `onReorder: ((UUID, Int) -> Void)?` property, in addition to `onSelect` and
  `onClose`, for a caller to observe tab reordering.
- **rejects-coder-initializer**: `TabBarView`, the private `TabItemHostView`,
  and the private `TabButton` MUST each fatal-error if constructed through
  `init?(coder:)`.
- **confines-to-main-actor**: `TabBarView`, `TabItemHostView`, and `TabButton`
  MUST each be usable only on the main actor; all three are declared
  `@MainActor`.

NEEDS REVIEW: Not implemented in source. Behavior undefined.
`TabBarView.swift` declares `onReorder` and documents it, in a doc comment, as
firing "after the user finishes dragging a tab to a new index," and
`MultiTabbedViewController.swift` wires that closure straight to a delegate
callback — but nothing in `TabBarView.swift` itself ever calls `onReorder`.
There is no `NSDraggingSource` conformance, no pasteboard registration, and no
other drag-and-drop or keyboard-driven reordering mechanism anywhere in this
file; `items`' only path to a new order is a caller directly calling
`setItems(_:selectedID:)` with a different array, which does not go through
`onReorder` at all. What is missing: the interaction — mouse drag or a
keyboard equivalent — that determines a target index and invokes
`onReorder(id, newIndex)`. What would settle it: an implementation of a drag
session in `TabBarView.swift` (or the confirmation that reordering is a
future, not-yet-built feature and the callback exists ahead of it).

## Appearance

- **Corner radius**: `4pt` on `TabButton`'s `backgroundView` pill
  (`backgroundView.layer?.cornerRadius`). `TabBarView` and `TabItemHostView`
  set no corner radius of their own.
- **Padding**: Inside `TabButton`: `10pt` from `backgroundView`'s leading
  edge to `titleLabel`; `4pt` between `titleLabel` and `backgroundView`'s
  top/bottom; `6pt` between `titleLabel` and `closeButton`; `6pt` from
  `closeButton` to `backgroundView`'s trailing edge; `backgroundView` itself
  is inset `2pt` from `TabButton`'s own top and bottom. Inside `TabBarView`:
  `6pt` (`outerPadding`) between an item and the bar's outer (window) side
  only — the workspace side is flush; `8pt` (`endPadding`) at each end of the
  bar along its length, overridable per instance via `startInset`; `4pt`
  (`itemSpacing`) between items on a horizontal bar, or `-16pt`
  (`cardOverlap`, a negative gap) on a vertical bar.
- **Font**: `.caption` text role for `TabButton.titleLabel` (a `ThemedLabel`)
  — resolved size and weight come from the active theme's typography
  (`ThemeTypography.defaultStyle(.caption)` is `11pt`/`.regular` absent a
  theme override), not a literal point size in `TabBarView.swift` itself; the
  role does not change with selection, only the label's color role does (see
  Foreground/Text).
- **Background**: `TabBarView` fills with the `.windowBackground` palette
  role. `TabButton.backgroundView` fills with the `.selection` role when
  `isHighlighted` and `NSColor.clear` otherwise. `TabItemHostView` draws no
  background of its own.
- **Foreground/Text**: `TabButton.titleLabel.role` is `.selectionText` when
  highlighted, `.secondaryText` otherwise; `closeButton.contentTintColor`
  follows the same pair (`.selectionText` / `.tertiaryText`). Both roles are
  resolved by `SemanticPalette`, which is outside this file's own source.
- **Border**: Not drawn — no border width, color, or `bezelStyle` other than
  `closeButton`'s own `.inline`/`isBordered = false` (a borderless icon
  button) appears anywhere in `TabBarView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: A bar's thickness floor is `28pt` (top/bottom) or `140pt`
  (left/right), growing to the largest hosted item's `preferredContentSize`
  on that axis plus `6pt` when that sum is larger (**thickness-grows-with-hosted-content**).
  `TabButton` has no explicit width/height constraint of its own; its size is
  whatever its content and fixed insets produce. `closeButton`'s hit area is
  a fixed `14×14pt`; its glyph (`xmark.circle.fill`) renders at `10pt`,
  `.regular` weight.

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected) | `TabButton` background transparent; label role `.secondaryText`; close icon tint `.tertiaryText`. |
| Selected | `TabButton` background fills with `.selection`; label role `.selectionText`; close icon tint `.selectionText`; `accessibilityValue` reports `true`; a hosted `TabBarHostedItem`'s `isHighlighted` is set `true`. |
| Stacked (vertical bar, `.viewController` items only) | An item recedes behind items nearer the selection: its `stackDepth` (index distance from the selected item) is reported to any hosted `TabBarStackedItem`, and its `-16pt`-overlapping wrapper view is drawn and hit-tested beneath nearer items (see the Design Decisions entry on `.title` tabs, which receive the overlap but not this reordering). |
| Pressed | Not applicable: a mouse-down resolves directly to selection or to the close action inside the same `mouseDown` handler; there is no separate, visually distinct pressed appearance before that resolution. |
| Disabled | Not applicable: no tab, button, or bar exposes a disabled appearance in `TabBarView.swift`; any item present in `items` is always selectable. |
| Focused | Not applicable: `TabButton` and `TabItemHostView` are plain `NSView` subclasses with no first-responder or focus-ring appearance defined in source (see the Accessibility keyboard-navigation gap). |
| Loading | Not applicable: every operation (`setItems`, `setSelected`, `renameItem`, `rebuildButtons`, `applyStackOrder`, `updateThickness`) is synchronous; source defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: `TabButton` sets `accessibilityRole = .button` and
  `setAccessibilityElement(true)`, which stops AppKit from hoisting its
  subviews into the tree in its place (**tab-button-is-accessible-element**).
  `TabItemHostView` and `TabBarView` itself set no accessibility role of
  their own — they are plain layout/click-forwarding containers, not
  controls; a `.viewController` item's own accessible content is entirely
  the hosted controller's concern.
- **Label requirements**: A `.title` tab exposes its title text via
  `accessibilityTitle` (**tab-button-title-updates-accessibility**); its
  close button carries its own identifier (`tab-bar.close.<uuid>`, distinct
  per tab since several bars can be on screen at once) and the description
  "Close Tab", and is the sole entry `accessibilityChildren()` republishes
  once the tab button becomes its own element
  (**close-button-republished-as-sole-child**).
- **Announce state changes**: `TabButton.isHighlighted`'s `didSet` updates
  that button's own `accessibilityValue` on every change, whether it
  originates from a click or from a caller's `setSelected(_:)`
  (**tab-button-highlight-updates-accessibility-value**) — so, unlike a
  purely click-driven implementation, this file's own value updates are
  consistent for both origins. NEEDS REVIEW: Not implemented in source.
  Behavior undefined. Nothing in `TabBarView.swift` posts an explicit
  `NSAccessibility.post(element:notification:)` beyond `accessibilityValue`'s
  own setter when selection changes. What is missing: whether a VoiceOver
  user whose cursor is positioned elsewhere is told that a different tab
  became selected. What would settle it: a VoiceOver pass exercising a
  programmatic `setSelected(_:)` call, or an explicit decision that the
  per-element value update is sufficient on its own.
- **Keyboard / assistive-technology navigation**: NEEDS REVIEW: Not
  implemented in source. Behavior undefined. `TabButton` and
  `TabItemHostView` are plain `NSView` subclasses with no
  `acceptsFirstResponder`, `keyDown`, or key-view-loop wiring; a tab is
  reachable only by a pointer click (`mouseDown`) or an existing VoiceOver
  cursor's `accessibilityPerformPress()`. `closeButton` is a real `NSButton`
  and so remains independently reachable through the ordinary AppKit
  key-view loop (Full Keyboard Access), meaning a keyboard-only user may be
  able to close a tab yet has no way at all to select one. What is missing:
  a way for a keyboard-only or Full Keyboard Access user to move focus onto
  a tab and activate it without a pointer or VoiceOver already positioned
  there. What would settle it: a keyboard-only pass over a real window, or an
  explicit decision that tab selection is pointer/VoiceOver-only and out of
  scope.
- **Minimum tap target**: `closeButton`'s hit area is a fixed `14×14pt`; the
  rest of `TabButton` (background, label) is clickable everywhere outside
  that frame. macOS is a pointer-driven desktop platform; the `44×44pt`
  (iOS) / `48×48dp` (Android) touch-target minimums do not apply directly to
  this source and instead inform the touch-platform translations in
  Platform Notes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-bar-view-001 | thickness-floor-by-edge | `TabBarView.preferredThickness(for: .top)` / `.left` | Returns `28`; `.left` returns `140` |
| tab-bar-view-002 | orientation-follows-edge | `TabBarView(edge: .right)` constructed | `stack.orientation == .vertical` |
| tab-bar-view-003 | alignment-favors-workspace-side | `TabBarView(edge: .top)` constructed | `stack.alignment == .bottom` |
| tab-bar-view-004 | item-spacing-by-orientation | `TabBarView(edge: .left)` constructed | `stack.spacing == -16` |
| tab-bar-view-005 | start-inset-defaults-to-end-padding | New `TabBarView` | `startInset == 8`; `stack.edgeInsets`'s main-axis start constant equals `8` |
| tab-bar-view-006 | host-may-override-start-inset | `bar.startInset = 20` | `stack.edgeInsets`'s main-axis start constant becomes `20` |
| tab-bar-view-007 | outer-padding-on-window-side-only | `TabBarView(edge: .bottom)` | `stack.edgeInsets == NSEdgeInsets(top: 0, left: 8, bottom: 6, right: 8)` |
| tab-bar-view-008 | bar-fills-perpendicular-and-pins-length | `TabBarView(edge: .top)` laid out in a 300pt-wide superview | `stack`'s leading/trailing equal the bar's leading/trailing; bar's height constraint constant `== 28` at rest |
| tab-bar-view-009 | vertical-bar-packs-from-top | `TabBarView(edge: .left)` with 2 short items in a tall superview | `stack`'s frame height is less than the bar's own height; the gap below is empty, not stretched |
| tab-bar-view-010 | bar-fills-window-background | Palette changes from theme A to theme B | `layer?.backgroundColor` updates to theme B's `.windowBackground` color |
| tab-bar-view-011 | set-items-triggers-rebuild | `setItems([item], selectedID: item.id)` | `stack.arrangedSubviews.count == 1`; the new item's button/host view is present |
| tab-bar-view-012 | set-selected-restyles-and-reorders | Two `.title` items; call `setSelected(itemB.id)` | `buttons[itemB.id]?.isHighlighted == true`; `buttons[itemA.id]?.isHighlighted == false` |
| tab-bar-view-013 | stack-depth-by-distance-from-selection | 3 `.viewController` items at indices 0,1,2; select index 0 | Depths reported to `TabBarStackedItem` are `0, 1, 2` |
| tab-bar-view-014 | stack-depth-by-distance-from-selection | Same 3 items; `selectedID == nil` | Every item's reported depth is `1` |
| tab-bar-view-015 | vertical-edge-cards-overlap-and-order-by-distance | `.left` bar, 3 hosted items, middle one selected | The middle item's wrapper view is above both neighbors in `subviews` (frontmost, topmost hit-tested) |
| tab-bar-view-016 | rename-title-item | `renameItem(id: tab.id, title: "New")` on an existing `.title` tab | `items` entry's payload is `.title("New")`; `buttons[tab.id]?.title == "New"` |
| tab-bar-view-017 | rename-title-item | `renameItem(id: unknownID, title: "X")` | No crash; `items` and `buttons` are unchanged |
| tab-bar-view-018 | rebuild-clears-and-repopulates | `setItems([a, b], ...)` then `setItems([c], ...)` | `stack.arrangedSubviews.count == 1`; `buttons`/`hostViews` no longer reference `a` or `b` |
| tab-bar-view-019 | cross-edge-move-preserves-foreign-controller | A hosted controller's view is reparented onto a different bar's wrapper, then this bar's `rebuildButtons()` runs | The controller's `parent` and view are unaffected by this bar's reconciliation |
| tab-bar-view-020 | rebuild-drops-stale-hosted-controllers | A `.viewController` item is removed from `items` and `rebuildButtons()` runs | `hostedControllers` no longer has an entry for that id |
| tab-bar-view-021 | title-item-becomes-button | `.title` item on a `.left` bar | The created `TabButton` has active leading/trailing constraints pinning it to the stack |
| tab-bar-view-022 | title-item-becomes-button | `.title` item on a `.top` bar | The created `TabButton` has no cross-axis pin installed by `TabBarView` (relies on stack alignment) |
| tab-bar-view-023 | viewcontroller-item-becomes-hosted-view | `.viewController` item on a `.top` bar | The wrapping `TabItemHostView` has active top/bottom constraints pinning it to the stack |
| tab-bar-view-024 | thickness-grows-with-hosted-content | `.left` bar hosts an item with `preferredContentSize.width == 200` | `thicknessConstraint?.constant == 206` (`200 + 6`, above the `140` floor) |
| tab-bar-view-025 | thickness-grows-with-hosted-content | `.left` bar with no hosted items | `thicknessConstraint?.constant == 140` (the floor) |
| tab-bar-view-026 | host-view-fills-hosted-content | `TabItemHostView(id:, content:)` constructed | `content`'s top/leading/trailing/bottom equal the wrapper's own edges |
| tab-bar-view-027 | host-view-click-selects | `mouseDown` on a point inside the wrapper but outside any interior control | `onSelect(id)` is invoked |
| tab-bar-view-028 | close-icon-hit-routes-to-close | `mouseDown` at a point inside `closeButton.frame` | `closeAction`/`onClose` fires via the close button; `onSelect` is not called directly by `TabButton.mouseDown` |
| tab-bar-view-029 | close-icon-hit-routes-to-close | `mouseDown` at a point outside `closeButton.frame` | `onSelect(id)` is invoked; close is not triggered |
| tab-bar-view-030 | accessibility-press-always-selects | `accessibilityPerformPress()` invoked while a VoiceOver cursor is conceptually "over" the close child | `onSelect(id)` is invoked (never the close action); returns `true` |
| tab-bar-view-031 | tab-button-is-accessible-element | `TabButton(id:, title: "Notes")` constructed, `isHighlighted` left at its default `false` | `accessibilityElement == true`; `accessibilityRole == .button`; `accessibilityTitle == "Notes"`; `accessibilityValue == false` |
| tab-bar-view-032 | tab-button-title-updates-accessibility | `button.title = "Renamed"` | `titleLabel.stringValue == "Renamed"`; `accessibilityTitle == "Renamed"` |
| tab-bar-view-033 | tab-button-highlight-updates-accessibility-value | `button.isHighlighted = true` | `accessibilityValue == true`; `updateAppearance()`'s effects are visible (see vector 035) |
| tab-bar-view-034 | close-button-republished-as-sole-child | `button.accessibilityChildren()` called | Returns an array containing exactly `closeButton` |
| tab-bar-view-035 | close-button-carries-per-tab-identifier | `TabButton(id: uuid, title:)` constructed | `button.accessibilityIdentifier() == "tab-bar.select.\(uuid)"`; `closeButton.accessibilityIdentifier() == "tab-bar.close.\(uuid)"` |
| tab-bar-view-036 | selecting-a-tab-restyles-its-button | `button.isHighlighted = true` | `backgroundView.layer?.backgroundColor` equals the `.selection` color; `titleLabel.role == .selectionText`; `closeButton.contentTintColor` equals `.selectionText` |
| tab-bar-view-037 | selecting-a-tab-restyles-its-button | `button.isHighlighted = false` | `backgroundView.layer?.backgroundColor` equals clear; `titleLabel.role == .secondaryText`; `closeButton.contentTintColor` equals `.tertiaryText` |
| tab-bar-view-038 | declares-reorder-callback | `let bar = TabBarView(edge: .top)` | `bar.onReorder` is a settable, externally accessible property (compiles and assigns) |
| tab-bar-view-039 | rejects-coder-initializer | Construct `TabBarView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| tab-bar-view-040 | confines-to-main-actor | Attempt to construct or mutate a `TabBarView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- Null/empty input (MUST): `setItems([], selectedID: nil)` MUST leave the bar
  with no arranged subviews, and `updateThickness()` MUST fall back to
  `preferredThickness(for: edge)` since `hostedControllers` is empty
  (see tab-bar-view-025). `renameItem(id:title:)` for an id absent from
  `items` MUST be a silent no-op (see tab-bar-view-017).
- Boundary values (MUST): A single-item bar (`items.count == 1`) MUST
  compute a `stackDepth` of `0` for that item whether or not it is selected
  (`selected.map { abs(index - $0) } ?? 1`, and `index == selected == 0`
  when it is); `applyStackOrder()`'s vertical z-raising loop still runs with
  only one view to raise, producing no visible reordering.
- Concurrent access: Not applicable — `TabBarView`, `TabItemHostView`, and
  `TabButton` are all `@MainActor`-isolated (**confines-to-main-actor**), so
  source provides no path for two threads to mutate one instance at the same
  time.
- Error states: Not applicable — `TabBarView.swift` makes no network,
  database, or file-system call. Its only fallible lookups (`items.firstIndex(where:)`
  in `renameItem`/`applyStackOrder`, dictionary subscripts in `setSelected`/
  `updateThickness`) resolve to silent no-ops or default values rather than
  throwing or trapping.
- Offline/disconnected: Not applicable — this component performs no
  networking of any kind.
- Unset `hostController` (MUST): When `hostController` is `nil`, a
  `.viewController` item's `addChild` call is skipped entirely (`hostController?.addChild`),
  so the hosted controller never receives a parent — but its view is still
  wrapped in a `TabItemHostView` and added to the stack regardless, so the
  tab still renders and is still clickable; only parent-based lifecycle
  callbacks (e.g. `viewWillAppear`) are missing.
- Renaming a `.viewController` tab (documented quirk, not a marker — see
  Design Decisions): `renameItem(id:title:)` performs no check on the
  existing item's payload type. Calling it for an id whose current item is
  `.viewController` overwrites that entry with `.title(title)` in `items`
  while `buttons[id]` is `nil` (no button was ever created for a
  `.viewController` item), so `buttons[id]?.title = title` is a no-op — the
  model now disagrees with what is rendered until the next `rebuildButtons()`.
  `TabBarView.swift`'s own comment states this is safe only because the
  caller (`MultiTabbedViewController.renameTab`) already refuses to call it
  for a `.viewController` item.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `edge` | `Edge` | (required, set at init) | Which side of the container this bar is docked to; fixed for the bar's lifetime. |
| `startInset` | `CGFloat` | `8` (`TabBarView.endPadding`) | Where the first item begins, measured along the bar from its start. |
| `hostController` | `NSViewController?` (weak) | `nil` | Parent a `.viewController` item's controller is added to; unset means hosted controllers are never parented (see Edge Cases). |
| `onSelect` | `((UUID) -> Void)?` | `nil` | Invoked when a tab is clicked, or when an assistive-technology press activates one. |
| `onClose` | `((UUID) -> Void)?` | `nil` | Invoked when a tab's close control is activated. |
| `onReorder` | `((UUID, Int) -> Void)?` | `nil` | Declared for a caller to observe reordering; never invoked by this file itself (see the open question under Behavioral Requirements). |

## Deep Linking

Not applicable: `TabBarView.swift` defines no URL scheme, `NSUserActivity`,
route, or deep-link handler anywhere in source; it is a rendering surface
driven entirely by direct, in-process method calls from its owner.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close Tab" | `NSImage(systemSymbolName:accessibilityDescription:)`'s description for `TabButton`'s close icon |

NEEDS REVIEW: Not implemented in source. Behavior undefined. "Close Tab" is a
hardcoded English `String` literal passed directly to
`accessibilityDescription`, not routed through `NSLocalizedString` or any
other localization mechanism used in this file — it is the one non-data-driven,
user/AT-facing string this component owns (a tab's own title text is always
supplied by the caller, so it carries no localization concern of this
component's making). What is missing: a translated string table entry for
this description. What would settle it: adding it to the app's string
catalog/`.strings` file and replacing the literal with a lookup.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext`/`animator()` call anywhere in
  `TabBarView.swift`; every appearance change (selection restyle, thickness
  change, layout rebuild) applies immediately.
- **Increase Contrast**: Not applicable — every color this component draws
  (`.selection`, `.selectionText`, `.secondaryText`, `.tertiaryText`,
  `.windowBackground`) is a semantic palette role; Increase Contrast
  handling, if any, belongs to the theme/palette system this file defers to,
  not to `TabBarView.swift` itself.
- **Differentiate Without Color**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. `TabButton.updateAppearance()` distinguishes selected
  from unselected purely by fill color (`.selection` vs. transparent) and a
  text/icon color-role swap (`.selectionText` vs. `.secondaryText`/
  `.tertiaryText`); `titleLabel`'s `textRole` (and therefore its font) never
  changes, so no weight, size, border, or icon accompanies the change. A
  `.viewController` item on a vertical bar gets a color-independent
  stacking/overlap cue from its `stackDepth`, but a `.title` tab never gets
  one, on any edge. What is missing: whether Differentiate Without Color
  should add e.g. a border or bold weight to a selected `TabButton`. What
  would settle it: a decision from the theme/accessibility owner on the
  substitute cue, or confirmation that the `.selection` background/text
  contrast alone is judged sufficient.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
`TabBarView.swift`; every item, once added via `setItems(_:selectedID:)`,
renders and behaves identically regardless of any external flag.

## Analytics

Not applicable: source contains no analytics or telemetry call anywhere in
`TabBarView.swift`; `onSelect`/`onClose`/`onReorder` are structural
notifications for the owner, not telemetry events.

## Privacy

- **Data collected**: None by this component itself. It holds only the tab
  ids, titles, and view-controller references it is given, describing how
  tabs are arranged — never content a hosted view controller chooses to
  display.
- **Storage**: In-memory only, for the life of the `TabBarView` instance
  (`items`, `buttons`, `hostedControllers`, `hostViews`). Nothing in this
  source persists tab state to disk.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view's own lifetime; all state is discarded
  when the `TabBarView` is deallocated.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
`Logger`/`Loggable` reference) anywhere in `TabBarView.swift`.

## Platform Notes

- **SwiftUI**: Model the item list as an array of a lightweight identifiable
  struct plus an external `selectedID`, both owned by the caller (mirroring
  `items`/`selectedID` being handed in rather than owned). Render one edge's
  bar as an `HStack` (top/bottom) or `VStack` (left/right) of pill `Button`s,
  each with a `.background(Capsule().fill(...))` that swaps between the
  `.selection` and clear fills and a text-color swap between
  `.selectionText`/`.secondaryText`, matching `updateAppearance()`; overlay a
  trailing close `Button` sized `14×14` the way `closeButton` sits inside
  `backgroundView`, giving it its own tap target so a tap there does not also
  select (SwiftUI's default hit-testing already scopes a nested `Button`'s
  tap to itself, unlike the manual frame-containment check
  **close-icon-hit-routes-to-close** performs). There is no SwiftUI analog to
  `NSStackView.addSubview(_:positioned:relativeTo:)`; reproduce the
  vertical-edge overlap and depth ordering with `.offset`/`.zIndex` driven by
  each item's index distance from the selection, recomputed the way
  `applyStackOrder()` does.
- **Compose**: Keep the item list and `selectedId` in a `ViewModel`. Render a
  horizontal bar as a `Row` and a vertical bar as a `Column` of
  `Surface`/`FilterChip`-based pill composables, driving the same fill/text/
  icon-tint swap from `MaterialTheme`-derived colors; give each pill a
  trailing icon `IconButton` for close, sized to mirror the `14×14pt` hit
  area, and let Compose's own click-consumption on that inner control keep it
  from also triggering the pill's `Modifier.clickable` (no manual
  frame-containment test is needed, unlike the source's `mouseDown` check).
  Reproduce the `-16dp` vertical overlap and depth ordering with
  `Modifier.offset` and `zIndex()` computed from each item's index distance
  from the selected one.
- **React/Web**: Keep the tab array and `selectedId` in component state.
  Render a bar as a flex container (`flex-direction: row` for top/bottom,
  `column` for left/right), each tab a `<button>` toggling a selected/
  unselected class (background + text/icon color, matching
  `updateAppearance()`'s role swap) and containing a nested close `<button>`
  whose click handler calls `event.stopPropagation()` — the direct web analog
  of `TabButton.mouseDown`'s frame-containment check — so a close click never
  also selects. Reproduce the vertical overlap with a negative `margin-top`
  (mirroring `-16pt`) and a `z-index` computed from each item's index
  distance from the selected tab.
- **AppKit/UIKit** (source platform): Implemented entirely in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabBarView.swift`
  as three types: `TabBarView` (an `NSView` hosting an `NSStackView`), the
  private `TabItemHostView` (click-to-select wrapper for a `.viewController`
  item's view), and the private `TabButton` (the `.title` item's pill,
  including its own `NSButton`-based close icon). This is macOS/AppKit-only —
  there is no UIKit code path in source. A UIKit/iPadOS port would replace
  `NSStackView` with `UIStackView`, `closeButton`'s `.inline` `NSButton` bezel
  with a plain `UIButton` (`.image(systemName: "xmark.circle.fill")`), and the
  `mouseDown`-based frame-containment hit test with a `UITapGestureRecognizer`
  on the wrapper plus the close button's own `.touchUpInside`, ordered (or
  `cancelsTouchesInView`-configured) so the close button's own target fires
  instead of the wrapper's when both would otherwise match.
- **WinUI 3** (the reason this recipe exists): No built-in WinUI 3 control is
  shaped like this — `TabView` supports only a single top-docked strip, not
  a per-edge bar with vertical overlap. Build the bar as a `StackPanel`
  (`Orientation="Horizontal"` for top/bottom, `"Vertical"` for left/right)
  hosting an `ItemsRepeater` (or `ListView` with its `ItemsPanel` swapped to
  a `StackPanel`), one `ToggleButton`-templated pill per tab: a `Border` with
  `CornerRadius="4"` (mirroring `backgroundView.layer.cornerRadius`) around a
  `TextBlock` bound to the tab title (`FontSize`/`FontWeight` from the
  theme's caption-equivalent resource, mirroring the `.caption` text role)
  and a small close `Button` templated to the Segoe Fluent Icons "Cancel"
  glyph (``), sized to `14×14` `Width`/`Height` to mirror `closeButton`'s
  fixed hit area. Drive the selected/unselected swap with a
  `VisualStateManager` `Selected`/`Unselected` state group that swaps
  `Background`/`Foreground` brush resources — matching
  `.selection`/`.selectionText` vs. transparent/`.secondaryText` — rather
  than `ToggleButton`'s own default checked brush, so one brush pair serves
  every tab. Apply `outerPadding`/`endPadding` as `Margin` on the strip's
  outer (window) edge and at its two length-wise ends only, leaving the
  workspace-side edge flush (mirroring `applyEdgeInsets()`). Reproduce the
  vertical bar's card overlap and depth ordering with a negative `Margin`
  (`-16`) between items plus `Canvas.ZIndex` recomputed from each item's
  index distance from the selected one, the same calculation
  `applyStackOrder()` performs, since `ItemsRepeater`/`StackPanel` has no
  native reordering-on-selection behavior. There is no WinUI analog to
  `mouseDown`'s point-in-`closeButton`-frame test: set `e.Handled = true` in
  the close `Button`'s own `Click`/`PointerPressed` handler so the event never
  bubbles up to fire the pill's own selection `Click`.

## Design Decisions

**Decision**: `startInset` defaults to `endPadding` (`8pt`) rather than `0`.
**Rationale**: Per the source's own doc comment, this is "where the first
item begins... `endPadding` unless a host says otherwise. A host whose
workspace has chrome of its own can line the first tab up with it, and the
bar stays ignorant of what it is lining up with" — the default keeps a bar
with no special host chrome visually consistent with its own trailing-end
inset.
**Approved**: pending

**Decision**: `TabButton`'s cross-axis pin (`pinCrossAxis(_:)`) is applied
only on a vertical bar, while a `.viewController` item's `TabItemHostView`
gets it unconditionally, on every edge.
**Rationale**: Per the source's own comments, a vertical bar's buttons "fill
the bar's interior width so labels and close buttons line up flush," while a
hosted item's content "reports no intrinsic size" on the cross axis and "has
to be told to fill the bar's interior" regardless of orientation, since only
its length along the stack's main axis is otherwise constrained (via
`preferredContentSize`). The asymmetry is a direct consequence of `TabButton`
having its own intrinsic cross-axis size (from its label and padding) on a
horizontal bar, and a hosted controller's view not having one on either axis.
**Approved**: pending

**Decision**: `rebuildButtons()` tears down a superseded hosted controller's
view only when that view's current superview is still this bar's own
(now-stale) `TabItemHostView`.
**Rationale**: Per the method's own comment, a cross-edge move "reparents the
controller's view onto the new bar's wrapper before the old bar notices the
id is gone from its own items," so tearing it down unconditionally there too
"would rip the view out of the new bar's display and cut the controller's
`preferredContentSizeDidChange` routing."
**Approved**: pending

**Decision (documented quirk, not a deliberate design choice)**: The
front-to-back z-reordering in `applyStackOrder()` only ever touches
`hostViews`, which is populated solely by `.viewController` items. A `.title`
`TabButton` on a vertical bar still receives the same `-16pt` overlapping
`stack.spacing` as a hosted item, but is never reordered by distance from the
selected item — its z-order (and so which overlapping title tab draws and
hit-tests on top) is whatever order `addArrangedSubview` produced, regardless
of selection.
**Rationale**: `hostViews`/`hostedControllers` are populated only for
`.viewController` items, so `applyStackOrder()`'s reordering loop has nothing
to reorder for title tabs. Nothing in source suggests this was a deliberate
choice for the title-tab case rather than an oversight; it is recorded here,
per source fidelity, rather than smoothed over.
**Approved**: pending

**Decision (documented quirk, not a deliberate design choice)**:
`renameItem(id:title:)` performs no check on the existing item's payload
type before overwriting it with `.title(title)`.
**Rationale**: The method's own comment states "the caller
(`MultiTabbedViewController.renameTab`) already refuses to call this for a
`.viewController` item, so there is nothing left to guard against here" —
the invariant is enforced entirely by the caller, not by `TabBarView` itself.
Calling it directly on a `.viewController` item (see Edge Cases) would desync
the model from the rendered bar until the next `rebuildButtons()`; this is
recorded as technical debt rather than a supported code path.
**Approved**: pending

**Decision**: `TabButton.accessibilityPerformPress()` always selects the
tab, even though a physical click can instead route to the close action.
**Rationale**: The source's own comment reads "`AXPress` selects the tab, the
same call `mouseDown` makes — so a driven press and a click are the same
event as far as anything downstream knows." Assistive technology presses the
element as a whole (the tab), not a sub-region of it the way a pointer click
can land inside `closeButton`'s frame; the close control is reached
separately, as its own republished accessibility child.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | failed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [live-region-announcements](agenticdevelopercookbook://compliance/accessibility#live-region-announcements) | flagged | accessibility |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | failed | accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | not-applicable | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | not-applicable | accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

Main-actor-confined passes because `TabBarView`, `TabItemHostView`, and
`TabButton` are all declared `@MainActor`. Keyboard-navigable is failed
because neither `TabButton` nor `TabItemHostView` has any key-view-loop or
`keyDown` wiring (see Accessibility). Screen-reader-support passes for
`.title` tabs: `TabButton` sets a real accessibility role, title, value, and
a republished close-button child. Live-region-announcements is flagged
because no accessibility notification beyond `accessibilityValue`'s own
setter is posted for a programmatic selection change (see Accessibility).
Differentiate-without-color is failed because a `.title` tab's selected
state is conveyed by color alone, with no non-color cue (see Accessibility
Options). Touch-target-size and contrast-ratio are not-applicable because
this is a pointer-driven macOS desktop control, not a touch surface, and its
colors are palette tokens whose resolution and contrast are defined entirely
outside `TabBarView.swift`, in the theme/palette system it defers to.
String-externalization is failed because the close button's "Close Tab"
accessibility description is a hardcoded English literal (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
