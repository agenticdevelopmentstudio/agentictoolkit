---
id: 5c2d7315-314e-4343-93fd-f3aa1a0c803e
title: ExtensionQuickPickViewController
domain: agentictoolkit://cookbook/macos/features/extensions/ui/extension-quick-pick-view-controller
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: macOS AppKit view controller for one showQuickPick screen — a live-filtering
  search field over a checkable or single-select NSTableView list.
platforms:
- swift
- macos
tags:
- component
- picker
- search
- table
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# ExtensionQuickPickViewController

## Overview

`ExtensionQuickPickViewController`
(`packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionQuickPickViewController.swift`)
is a macOS `NSViewController` that renders the one screen a
`vscode.window.showQuickPick` call needs: an `NSSearchField` that filters a
list of rows shown in an `NSTableView`, where each row is either a
selectable item (with an optional leading checkbox for multi-select) or a
non-selectable separator/heading. It is built from an `ExtensionQuickPickModel`
(constructor-injected, AppKit-free) that owns the filter query, the visible
row order, the highlighted row, and — in multi-select — the checked set. The
controller reports its outcome through three callbacks: `onAccept` (the
chosen indices), `onCancel` (dismissal), and `onHighlight` (the highlighted
row changed). It is modelled directly on the sibling
`CommandPaletteViewController` and shares its keyboard-routing type,
`PickerKeyboardController`, with four other pickers in the same module.

## Behavioral Requirements

- **designated-initializer**: The component MUST be constructed via
  `init(model:)` with a required, non-optional `ExtensionQuickPickModel`,
  and MUST NOT support `init(coder:)`; invoking `init(coder:)` MUST trigger
  a fatal error.
- **fixed-content-size**: The component MUST set `preferredContentSize`
  to 560×400 points during `init`, before `loadView` runs.
- **title-label**: The component MUST create and
  display a title label only when `model.request.title` is non-nil and
  non-empty; when `title` is nil or empty, the component MUST render no
  title label at all (not a hidden one).
- **title-label-position**: When a title label exists, the component MUST
  pin it 12pt from the root view's top, leading, and trailing edges.
- **search-field-position**: The component MUST pin the search field 12pt
  from the root view's leading and trailing edges, and MUST position its
  top edge 12pt below the title label's bottom when a title label exists,
  or 12pt below the root view's top when it does not.
- **table-scroll-position**: The component MUST position the table's
  scroll view 8pt below the search field's bottom edge, MUST pin its
  leading and trailing edges 12pt from the root view's edges, and MUST pin
  its bottom edge 12pt from the root view's bottom edge.
- **search-placeholder**: The component MUST set the search
  field's `placeholderString` to `model.request.placeHolder`, or to an
  empty string when `placeHolder` is nil.
- **live-filtering**: On every `controlTextDidChange`
  notification from the search field, the component MUST set `model.query`
  to the field's current text, reload the table, and re-synchronize the
  highlighted row — filtering runs on every keystroke, not only on a
  committed search string.
- **arrow-and-return-routing**: The component MUST route the search
  field's `moveDown(_:)`, `moveUp(_:)`, and `insertNewline(_:)` command
  selectors, via `PickerKeyboardController`, to moving the highlight down,
  moving it up, and choosing the highlighted/checked result, respectively.
- **escape-routing**: The component MUST route the search field's
  `cancelOperation(_:)` command selector, and a window-level Escape key
  event captured by a local event monitor installed in `viewDidAppear` and
  removed in `viewWillDisappear`, to `onCancel()`.
- **escape-idempotency**: A single physical Escape keypress MUST invoke
  `onCancel()` exactly once, never twice. The window-level local monitor
  installed for `escape-routing` runs before the key event is dispatched to
  any responder and returns `nil` for a matched key-down, discarding it —
  so the same keypress never also reaches the search field's field editor
  to raise `cancelOperation(_:)` through `control(_:textView:doCommandBy:)`.
- **search-field-focus**: The table view MUST refuse first
  responder status (`refusesFirstResponder = true`); after
  `focusSearchField()` is called, the search field MUST hold the window's
  first responder status, and no other view in this controller takes first
  responder for itself.
- **single-native-selection**: The table view MUST set
  `allowsMultipleSelection = false` at all times, including when
  `model.request.canPickMany` is true; multi-selection state MUST be
  tracked separately through `model.checkedIndices` and a per-row
  checkbox, never through native table row multi-selection.
- **table-header**: The table view MUST set `headerView` to nil.
- **single-item-column**: The table view MUST contain exactly one
  `NSTableColumn`, with resizing mask `.autoresizingMask` and the table's
  `columnAutoresizingStyle` set to `.firstColumnOnlyAutoresizingStyle`, so
  that one column fills the table's width.
- **single-select-click**: When
  `model.request.canPickMany` is false, clicking a non-separator,
  in-range row MUST highlight that row, synchronize the table selection,
  and immediately invoke `onAccept` with that row's index.
- **multi-select-click**: When
  `model.request.canPickMany` is true, clicking a non-separator, in-range
  row, or its own checkbox, MUST toggle that row's checked state and
  reload only that row's cell, and MUST NOT invoke `onAccept`.
- **separator-and-out-of-range-clicks**: A click on a separator
  row, or on a row index outside `model.visibleIndices`'s bounds, MUST be
  a no-op: it MUST NOT change the highlight, MUST NOT change the checked
  set, and MUST NOT invoke `onAccept`.
- **multi-select-checkbox**: Each non-separator row's
  checkbox MUST be hidden and its title label MUST anchor to the row's own
  leading edge when `model.request.canPickMany` is false; the checkbox
  MUST be shown and the title label MUST anchor to the checkbox's trailing
  edge when `canPickMany` is true.
- **checked-state**: Each non-separator row's checkbox `state`
  MUST reflect whether `model.checkedIndices` contains that row's item
  index, both when the row is first configured and after every toggle of
  that row.
- **description-and-detail**: Each non-separator row MUST
  display `item.description` trailing the title label when it is non-nil
  and non-empty, and MUST hide that label otherwise; it MUST display
  `item.detail` on a second line when non-nil and non-empty, and MUST hide
  that label otherwise.
- **separator-label**: A separator row MUST display
  `item.label` in a tertiary-text caption label when the label is
  non-empty, and MUST hide that label — leaving a blank row — when
  `item.label` is empty.
- **highlight-selection-sync**: Whenever the highlighted index
  changes, the component MUST select the corresponding row in the table
  and scroll it into view, or deselect all rows when no index is
  highlighted or the highlighted index has no corresponding visible row,
  and MUST invoke `onHighlight` with the highlighted item index whenever a
  row is selected this way.
- **empty-choose**: Invoking `choose()` (via Return) MUST
  NOT invoke `onAccept` when `model.acceptedIndices()` returns nil (a
  single-select list with nothing highlighted); it MUST invoke `onAccept`
  with an empty array when multi-select has zero checked items, since an
  empty selection is a valid answer distinct from dismissal.
- **separator-selection-guard**: The table's `tableView(_:shouldSelectRow:)`
  delegate method MUST return false for a separator row, in addition to
  the model's own refusal to highlight one.
- **test-identifiers**: The component MUST set an accessibility
  identifier of `extension-quick-pick.search-field` on the search field
  and `extension-quick-pick.table` on the table view.
- **shared-keyboard-controller**: The component MUST route all
  keyboard dispatch through the shared `PickerKeyboardController` type
  rather than implementing its own key-event handling.

## Appearance

- **Corner radius**: Not applicable — `root.wantsLayer = true` is set, but
  no `cornerRadius` or other layer shaping is configured anywhere in
  `ExtensionQuickPickViewController.swift`; any rounded panel chrome
  belongs to the hosting `ExtensionPickerWindowController`/
  `FloatingChooserPanelController`, not this file.
- **Padding**: See **title-label-position**, **search-field-position**, and
  **table-scroll-position** for exact values — 12pt root-edge insets
  throughout, and 8pt between the search field's bottom and the table
  scroll view's top.
- **Font**: The title label uses `ThemedLabel(role: .primaryText, textRole:
  .heading)`; each item row's title label uses `role: .primaryText,
  textRole: .body`; each item row's description label uses `role:
  .secondaryText, textRole: .caption`; each item row's detail label and
  the separator row's label both use `role: .tertiaryText, textRole:
  .caption`. `ThemedLabel` resolves the actual point size and weight at
  draw time from the active theme's typography scale
  (`SemanticPalette.font(_:)`, itself
  `theme.typography.style(role).nsFont(scaledSize:)`), so no literal point
  size or font weight is hardcoded anywhere in this file.
- **Background**: `tableScroll.drawsBackground = true`, and `ThemedTableView`
  (role defaulting to `.surface`) paints the active theme's surface color
  as the table's background, repainting live on a theme change; no
  explicit background color is set on the root view or on either search
  field or table beyond that.
- **Foreground/Text**: Every label's text color follows its `ThemeRole`
  (`.primaryText`, `.secondaryText`, or `.tertiaryText`), resolved by the
  active theme's `SemanticPalette`; no literal `NSColor` value appears
  anywhere in this file.
- **Border**: `tableScroll.borderType = .noBorder` is set explicitly; no
  other border is configured on any view in this file.
- **Shadow**: Not applicable — no shadow property or `CALayer` shadow is
  configured anywhere in `ExtensionQuickPickViewController.swift`.
- **Min/Max size**: `preferredContentSize` is fixed at 560×400 points with
  no separate min/max constraint; the table's `rowHeight` is fixed at
  24pt.

## States

| State | Appearance change |
|-------|------------------|
| Default | Title label (if any) shown; search field shows `model.request.placeHolder` (or empty); table lists `model.visibleIndices`; the highlighted row, if any, is selected via `syncSelection()`. |
| Pressed | Single-select: clicking a row highlights it, syncs selection, and immediately calls `onAccept` (accept-on-click). Multi-select: clicking a row or its checkbox toggles that row's check and reloads only that row; the panel stays open. Either mode: a click on a separator or out-of-range row is a no-op. |
| Disabled | Not applicable: `isEnabled` is never set on any control in `ExtensionQuickPickViewController.swift`; every view is always enabled. |
| Focused | The search field holds first responder from the moment `focusSearchField()` is called (invoked externally by `ExtensionPickerWindowController.takeInitialFocus()`) — see **search-field-focus**; the table refuses first responder (`refusesFirstResponder = true`) and is never itself focused — the highlighted row is instead shown through table selection plus `ThemedTableRowView`'s own rounded selection fill (`.selection` role, 4pt corner radius, inset 2pt/1pt), not a native focus ring. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading flag appears anywhere in `ExtensionQuickPickViewController.swift`; the model is built synchronously from the request in `init`. |

## Accessibility

- **Role/trait**: Not set explicitly anywhere in this file. `NSSearchField`,
  `NSTableView`, and the row checkbox (`NSButton(checkboxWithTitle:)`) each
  carry AppKit's own default accessibility role for their control type;
  the title/description/detail/separator labels are plain `NSTextField`s
  (via `ThemedLabel`), which AppKit exposes as static text by default.
- **Label requirements**: The search field's `placeholderString` supplies
  its own accessible hint through AppKit's stock `NSSearchField` behavior.
  The multi-select checkbox is built as `NSButton(checkboxWithTitle: "",
  target: nil, action: nil)` — an empty title — and `ItemRowCellView`
  never calls an accessibility-label or title-linking API (no
  `setAccessibilityLabel`, no `setAccessibilityTitleUIElement`) to
  associate the checkbox with the row's own title label, so VoiceOver
  announces the checkbox by its generic checkbox role only, with no
  descriptive label tying it to the row it belongs to.
- **Announce state changes (e.g., loading, disabled)**: Highlight changes
  move the native table selection (`tableView.selectRowIndexes` plus
  `scrollRowToVisible`), which is AppKit's own stock `NSTableView`
  accessibility behavior for a real, undisguised table; nothing in this
  file suppresses or replaces that default notification. There is no
  loading or disabled state to announce (see States).
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/trackpad-driven `NSViewController` composition with no touch
  input path anywhere in source; `tableView.rowHeight = 24` sizes rows for
  pointer hit-testing on this platform, not against a touch-target
  guideline.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-quick-pick-view-controller-001 | designated-initializer | Call `ExtensionQuickPickViewController(model:)` with a valid model | Controller initializes; attempting `init(coder:)` traps with a fatal error |
| extension-quick-pick-view-controller-002 | fixed-content-size | Read `preferredContentSize` immediately after `init`, before `loadView` is triggered | `preferredContentSize == NSSize(width: 560, height: 400)` |
| extension-quick-pick-view-controller-003 | title-label | `model.request.title = nil`, then load the view | No title label subview exists in the view hierarchy |
| extension-quick-pick-view-controller-004 | title-label | `model.request.title = "Pick a file"`, then load the view | A `ThemedLabel` subview showing "Pick a file" exists |
| extension-quick-pick-view-controller-005 | title-label-position | `model.request.title` non-empty, view loaded | Title label's top/leading/trailing constraints resolve to 12pt from the root view's respective edges |
| extension-quick-pick-view-controller-006 | search-field-position | `model.request.title = nil`, view loaded | Search field's top edge is 12pt below the root view's top |
| extension-quick-pick-view-controller-007 | table-scroll-position | View loaded with any request | Table scroll's top is 8pt below the search field's bottom; leading/trailing are 12pt from root edges; bottom is 12pt from the root's bottom |
| extension-quick-pick-view-controller-008 | search-placeholder | `model.request.placeHolder = nil`, view loaded | `searchField.placeholderString == ""` |
| extension-quick-pick-view-controller-009 | live-filtering | Type a character into the search field, triggering `controlTextDidChange` | `model.query` updates to the field's text, `tableView.reloadData()` is called, and the highlighted row is re-synced |
| extension-quick-pick-view-controller-010 | arrow-and-return-routing | With the search field focused, press the Down arrow key | `control(_:textView:doCommandBy:)` routes `moveDown(_:)` to `PickerKeyboardController`, which calls the controller's move-selection handler |
| extension-quick-pick-view-controller-011 | escape-routing | With the panel's window key, press Escape | The window-level local event monitor fires and `onCancel()` is invoked |
| extension-quick-pick-view-controller-012 | search-field-focus | Call `focusSearchField()` | `view.window?.firstResponder` becomes the search field; `tableView.acceptsFirstResponder == false` |
| extension-quick-pick-view-controller-013 | single-native-selection | `model.request.canPickMany = true`, view loaded | `tableView.allowsMultipleSelection == false` |
| extension-quick-pick-view-controller-014 | table-header | View loaded with any request | `tableView.headerView == nil` |
| extension-quick-pick-view-controller-015 | single-item-column | View loaded with any request | `tableView.tableColumns.count == 1`, with resizing mask `.autoresizingMask` |
| extension-quick-pick-view-controller-016 | single-select-click | `canPickMany = false`; call `handleRowClick(_:)` on a valid non-separator row | `model.highlightedIndex` becomes that row's item index, selection syncs, and `onAccept` is invoked with `[itemIndex]` |
| extension-quick-pick-view-controller-017 | multi-select-click | `canPickMany = true`; call `handleRowClick(_:)` on a valid non-separator row | `model.checkedIndices` toggles that item index, only that row reloads, and `onAccept` is not invoked |
| extension-quick-pick-view-controller-018 | separator-and-out-of-range-clicks | Call `handleRowClick(_:)` on a separator row's index | No change to `model.highlightedIndex` or `model.checkedIndices`; `onAccept` is not invoked |
| extension-quick-pick-view-controller-019 | multi-select-checkbox | `canPickMany = false`, a non-separator row is rendered | The row's checkbox is hidden; the title label's leading constraint is anchored to the row's own leading edge |
| extension-quick-pick-view-controller-020 | checked-state | `canPickMany = true`, item index already in `model.checkedIndices`, row rendered | The row's checkbox `state == .on` |
| extension-quick-pick-view-controller-021 | description-and-detail | `item.description = nil`, `item.detail = "extra"`, row rendered | Description label is hidden; detail label shows "extra" and is visible |
| extension-quick-pick-view-controller-022 | separator-label | Separator `item.label = ""`, row rendered | Separator cell's label is hidden, producing a blank row |
| extension-quick-pick-view-controller-023 | highlight-selection-sync | `model.highlightedIndex` set to an index with no corresponding row in `model.visibleIndices` | `tableView.deselectAll(nil)` is called; `onHighlight` is not invoked |
| extension-quick-pick-view-controller-024 | empty-choose | `canPickMany = false`, `model.highlightedIndex = nil`; invoke `choose()` via Return | `onAccept` is not invoked |
| extension-quick-pick-view-controller-025 | empty-choose | `canPickMany = true`, `model.checkedIndices` empty; invoke `choose()` via Return | `onAccept` is invoked with `[]` |
| extension-quick-pick-view-controller-026 | separator-selection-guard | Call `tableView(_:shouldSelectRow:)` for a separator row's index | Returns `false` |
| extension-quick-pick-view-controller-027 | test-identifiers | View loaded with any request | `searchField.accessibilityIdentifier() == "extension-quick-pick.search-field"`; `tableView.accessibilityIdentifier() == "extension-quick-pick.table"` |
| extension-quick-pick-view-controller-028 | shared-keyboard-controller | With the search field focused, invoke `control(_:textView:doCommandBy:)` with `moveUp(_:)`, `moveDown(_:)`, and `insertNewline(_:)` in turn | Each call returns `true` and reaches `model` only via `PickerKeyboardController.handle(_:)` — `model.highlightedIndex` moves down then up, and `choose()` runs on `insertNewline(_:)`; no separate key-handling path in this file intercepts any of the three |
| extension-quick-pick-view-controller-029 | escape-idempotency | With the panel's window key and the search field focused, deliver one keyCode-53 key-down event | `onCancel()` is invoked exactly once; `control(_:textView:doCommandBy:)` is never called with `cancelOperation(_:)` for that same event |
| extension-quick-pick-view-controller-030 | search-field-position | `model.request.title = "Pick a file"`, view loaded | Search field's top edge is 12pt below the title label's bottom |
| extension-quick-pick-view-controller-031 | search-placeholder | `model.request.placeHolder = "Search extensions"`, view loaded | `searchField.placeholderString == "Search extensions"` |
| extension-quick-pick-view-controller-032 | arrow-and-return-routing | With the search field focused and a highlighted row that is not the first selectable row, press the Up arrow key | `control(_:textView:doCommandBy:)` routes `moveUp(_:)` to `PickerKeyboardController`, which calls the controller's move-selection handler and `model.highlightedIndex` moves to the previous selectable row |
| extension-quick-pick-view-controller-033 | arrow-and-return-routing | `canPickMany = false`, `model.highlightedIndex` set to a valid item; press Return | `control(_:textView:doCommandBy:)` routes `insertNewline(_:)` to `choose()`, and `onAccept` is invoked with `[highlightedIndex]` |
| extension-quick-pick-view-controller-034 | highlight-selection-sync | `model.highlightedIndex` set to an index with a corresponding row in `model.visibleIndices`, `syncSelection()` runs | `tableView.selectRowIndexes` is called for that row and `onHighlight` is invoked with that index |
| extension-quick-pick-view-controller-035 | multi-select-checkbox | `canPickMany = true`, a non-separator row is rendered | The row's checkbox is visible; the title label's leading constraint is anchored to the checkbox's trailing edge |
| extension-quick-pick-view-controller-036 | description-and-detail | `item.description = "extra info"`, row rendered | Description label is visible and shows "extra info" |

## Edge Cases

- **Null/empty input — no items**: `model.request.items = []`. `visibleIndices`
  is empty, `highlightedIndex` is nil, the table shows zero rows, and
  `choose()` (Return) is a no-op because `acceptedIndices()` returns nil
  in single-select — computed entirely by `ExtensionQuickPickModel`, with
  no additional guard in this file.
- **Boundary values — all-separator list**: Every item in
  `model.request.items` is a separator. `highlightedIndex` stays nil (no
  selectable row exists), arrow keys and clicks are no-ops throughout, and
  `choose()` never fires `onAccept` in single-select — traceable directly
  to `ExtensionQuickPickModel.firstSelectableIndex` returning nil.
- **Boundary values — separator with no surviving section**: A filter
  query that matches nothing in a section hides that section's separator
  along with its items. This is `ExtensionQuickPickModel`'s own filtering
  rule, not this controller's; see the second entry under **Design
  Decisions** for why it exists.
- **Concurrent access**: Not applicable — the class is
  `@MainActor`-isolated, so Swift's concurrency checker serializes every
  access to its state; there is no code path by which two threads can
  mutate the controller or its model simultaneously.
- **Error states**: Not applicable — every operation in this file (query
  updates, highlight moves, row clicks, table reloads) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  `ExtensionQuickPickViewController.swift`.
- **Offline/disconnected**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ExtensionQuickPickModel` built from a request handed to it at
  construction.
- **Historical defect, now guarded — separator click accepting a stale
  highlight**: See **Design Decisions** (the guard against accepting a
  stale highlight on a separator/out-of-range click) and
  **separator-and-out-of-range-clicks**; the guard is shared by both the
  single- and multi-select branches so this cannot regress silently.
- **Multi-select empty acceptance**: A user can press Return in
  multi-select with zero rows checked. `acceptedIndices()` returns `[]`
  (not nil), and `choose()` calls `onAccept([])` — a real, reportable
  answer, not a dismissal. Callers MUST distinguish an empty array
  (`onAccept([])`) from a dismissal (`onCancel()`) — see **empty-choose**.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `ExtensionQuickPickModel` | — (required) | Owns `request` (title, placeholder, items, `canPickMany`, `matchOnDescription`/`matchOnDetail`), the filter query, `visibleIndices`, `highlightedIndex`, and `checkedIndices`. Supplied once at `init` and never replaced. |
| `onAccept` | `([Int]) -> Void` | no-op closure | Called with the chosen indices into `model.request.items` when the user accepts (Return, or a single-select click). |
| `onCancel` | `() -> Void` | no-op closure | Called on Escape (key or window-level monitor); not part of this file's `ignoreFocusOut`/focus-loss handling, which is `ExtensionPickerWindowController`'s concern, not this view controller's. |
| `onHighlight` | `(Int) -> Void` | no-op closure | Called from the single place the highlight is synced to the table (`syncSelection()`), whenever a row becomes highlighted. |

## Deep Linking

Not applicable: `ExtensionQuickPickViewController` is one screen of a
floating panel presented in response to an internal
`vscode.window.showQuickPick` call, not a navigable app screen; no URL
scheme, route, or deep-link handler appears anywhere in
`ExtensionQuickPickViewController.swift`.

## Localization

Not applicable: every user-visible string this component renders — the
title, the placeholder, and each item's label/description/detail — comes
from the caller-supplied `ExtensionQuickPickRequest`/`ExtensionQuickPickItem`
(originating from the VS Code extension that called `showQuickPick`), not
from a static string owned by this component. The only literal strings in
`ExtensionQuickPickViewController.swift` are the two accessibility
identifiers (`extension-quick-pick.search-field`,
`extension-quick-pick.table`) and the checkbox's empty title, none of
which is user-facing text requiring localization.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in `ExtensionQuickPickViewController.swift`; every state change (filtering, highlighting, checking) is an instantaneous property assignment or table reload. |
| Increase Contrast | Not applicable to this file directly: no custom `NSColor` is ever set here; every color comes from a `ThemeRole` resolved by the active theme's `SemanticPalette`, so Increase Contrast support is the active theme's responsibility, not this component's. |
| Differentiate Without Color | Partial: the checked state itself is communicated solely by the checkbox's own on/off checkmark glyph — no color-only signal there. But the *highlighted* row (arrow-key focus) is shown only by `ThemedTableRowView`'s `.selection`-role fill (a 4pt-corner-radius, 2pt/1pt-inset rounded rect — see **States** › Focused); this file draws no separate icon, border, or text-weight change alongside that fill, so whether the highlight is distinguishable without color depends entirely on that fill's contrast against the row's normal background. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in `ExtensionQuickPickViewController.swift`; the picker always
renders once constructed from its model.

## Analytics

Not applicable: `ExtensionQuickPickViewController.swift` contains no
analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it renders the title/placeholder/item text the caller supplied
  in `ExtensionQuickPickRequest` and reports back selected indices through
  `onAccept`/`onHighlight`.
- **Storage**: Not applicable — no read/write to disk, `UserDefaults`, or
  any other store occurs anywhere in this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in `ExtensionQuickPickViewController.swift`; how the originating request
  reached the host process is outside this file's scope.
- **Retention**: Not applicable — the controller retains only its own
  subviews and its `model` reference for its own lifetime; it persists
  nothing beyond that.

## Logging

Not applicable: `ExtensionQuickPickViewController.swift` contains no
logging call (no `print`, `os_log`, or logger reference anywhere in
source).

## Platform Notes

- **SwiftUI**: Compose a `List`/`ForEach` over the model's visible items
  with a `TextField` (or `.searchable`) driving the filter text, but plan
  explicitly for keyboard routing: SwiftUI's default `List` moves system
  focus into row items on arrow-key navigation, which would break the
  source's "search field never loses first responder" behavior
  (`search-field-focus`) unless arrow/return/escape are intercepted
  with `.onKeyPress` (or an `NSEvent` local monitor bridged in) at the
  text field itself, mirroring `PickerKeyboardController`. Represent
  `visibleIndices`/`highlightedIndex`/`checkedIndices` as `@Published`
  properties on an `ObservableObject` wrapping the same filtering rules as
  `ExtensionQuickPickModel`.
- **Compose**: Use a `LazyColumn` of filtered items with an
  `OutlinedTextField` for search, and register `Modifier.onKeyEvent` (or a
  hardware key listener) on the text field for Up/Down/Enter/Escape so
  Compose's own focus system does not move focus into row items — the
  same risk as SwiftUI's `List`. Track "highlighted" as separate state
  from Compose's own selection, and drive an optional leading `Checkbox`
  per row from a `Set<Int>` mirroring `checkedIndices`, rather than
  `LazyColumn`'s own multi-select gesture handling.
- **React/Web**: An `<input type="search">` feeding a filtered `<ul>`/`<div
  role="listbox">` list, with `onKeyDown` handling `ArrowUp`/`ArrowDown`/
  `Enter`/`Escape` while keeping DOM focus in the input and using
  `aria-activedescendant` to indicate the highlighted row — mirroring the
  source's `refusesFirstResponder` table plus focused search field, rather
  than moving DOM focus into list items. Render an optional leading
  `<input type="checkbox">` per row for multi-select, explicitly paired
  with a `<label>` (or `aria-labelledby`) referencing that row's title —
  closing the accessible-label gap flagged in Accessibility above rather
  than reproducing it.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionQuickPickViewController.swift`.
  A macOS-only (`import AppKit`) `NSViewController`, `@MainActor`,
  composing an `NSSearchField` and a `ThemedTableView` inside an
  `NSScrollView`, with `PickerKeyboardController` for keyboard routing and
  a private `NSEvent` local monitor for Escape. There is no UIKit code
  path in source; a UIKit port would replace the search field with
  `UISearchController`/`UISearchBar`, the table with `UITableView`, and
  would need its own keyboard-routing solution via `UIKeyCommand` in place
  of `doCommandBy:`, since UIKit has no equivalent hook.
- **WinUI 3**: Build the list with a `ListView` bound to the filtered
  items, each row a `DataTemplate` — a `Grid` with an optional `CheckBox`
  column (bound to a per-item `IsChecked` property mirroring
  `checkedIndices`, shown only when multi-select is active, mirroring
  `multi-select-checkbox`) and a `StackPanel` of `TextBlock`s for
  title/description/detail. Drive the search with a `TextBox` (or
  `AutoSuggestBox`) whose `TextChanged` event updates the filter on every
  keystroke, mirroring `live-filtering`; handle the `TextBox`'s
  `PreviewKeyDown` for Up/Down/Enter/Escape so focus stays in the
  `TextBox` rather than moving into the `ListView` — the WinUI analog of
  `refusesFirstResponder` plus `search-field-focus`. Set
  `ListView.SelectionMode="None"` and track "highlighted" as a bound index
  plus a custom `VisualStateManager` state on the `ListViewItem` container
  (a theme-brush-driven selection fill, mirroring `ThemedTableRowView`'s
  `.selection`-role rounded rect), rather than `ListView`'s own selection
  input gesture — `ListView` selects and closes on click by default,
  which would conflict with the source's rule that a click in multi-select
  toggles a checkbox and never closes the panel (`multi-select-click`);
  drive the checkbox/accept flow entirely from the row template's own
  click and `CheckBox.Checked`/`Unchecked` events instead. Bind every row
  color to a `ThemeResource` brush — never a `StaticResource` (which does
  not update on a theme change) or a literal `Color` — mirroring the
  source's `ThemeRole` indirection.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionQuickPickViewController.swift` |

## Design Decisions

- **Decision**: Keep `tableView.allowsMultipleSelection` false even when
  `model.request.canPickMany` is true.
  **Rationale**: "Highlight" always means exactly one row (the arrow-key
  focus), while multi-select is tracked separately through
  `model.checkedIndices` and rendered as a leading checkbox column — never
  through native table multi-row selection — matching the source's own
  design-intent comment about this being the one shape the command
  palette does not need.
  **Approved**: pending
- **Decision**: Hide a separator whose section has no surviving item during
  filtering, rather than mirroring an unverified upstream (VS Code) rule.
  **Rationale**: `ExtensionQuickPickModel`'s own documentation states this
  is "our rule, not a quoted upstream one" and explicitly notes the brief
  did not verify VS Code's own behavior here; documented as a known
  deviation per source-fidelity rather than smoothed over.
  **Approved**: pending
- **Decision**: Re-check `!isSeparator` in `tableView(_:shouldSelectRow:)`
  even though `ExtensionQuickPickModel.highlightRow`/`moveHighlight`
  already refuse to land on a separator.
  **Rationale**: Source documents this as a deliberate belt-and-braces
  redundancy — a second guard against a mouse click doing what the arrow
  keys cannot — and it is kept as observed rather than simplified away.
  **Approved**: pending
- **Decision**: Guard `handleRowClick(_:)` against accepting a stale
  highlight on a separator or out-of-range click, in both the single- and
  multi-select branches.
  **Rationale**: Source documents this guard as the fix for a real prior
  defect — a click on a separator/section heading used to silently accept
  whatever row was highlighted before the click.
  **Approved**: pending
- **Decision**: Document that `SeparatorRowCellView`'s own doc comment
  claims an empty-label separator renders "a plain divider," while the
  implementation only sets `label.isHidden = true` with no additional
  divider line or box drawn.
  **Rationale**: Source-fidelity requires recording a mismatch between a
  source doc comment's claim and its implementation rather than
  idealizing the described-but-unbuilt behavior; an empty-label separator
  is blank space, not a drawn divider line, in this file as written.
  **Approved**: pending
- **Decision**: Note that `searchField.sendsWholeSearchString = false` and
  `searchField.sendsSearchStringImmediately = true` are set even though no
  `target`/`action` is ever assigned to the search field.
  **Rationale**: Filtering is actually driven entirely by
  `NSSearchFieldDelegate.controlTextDidChange`, which already fires on
  every keystroke regardless of these two flags; they configure a
  target-action search-submission behavior this class never wires up, so
  they read as vestigial configuration rather than load-bearing — recorded
  as observed, not treated as a functional requirement.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference` and `platform-design-language` pass because
every control (`NSSearchField`, `NSTableView`, the checkbox `NSButton`) is
a stock AppKit control themed via `ThemeRole`, not a custom-drawn
substitute; `keyboard-navigable` passes because arrow keys, Return, and
Escape all reach the model through `PickerKeyboardController`;
`screen-reader-support` is partial because the multi-select checkbox
carries no accessibility label linking it to its row's title (see
Accessibility above); `separation-of-concerns` passes because all
filtering, selection, and checked-set state lives in the AppKit-free
`ExtensionQuickPickModel`, not in this view controller.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ExtensionQuickPickViewController, covering fixed-size layout, live filtering, single-select accept-on-click versus multi-select checkbox-toggle behavior, shared keyboard routing, and one open accessibility question (multi-select checkbox has no accessible label) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed every requirement to subject-only kebab-case and updated all cross-references; added an escape-idempotency requirement and vector clarifying one Escape press invokes `onCancel()` exactly once; reformatted Design Decisions into the template's bold three-line form; dropped the redundant `macos` tag, the non-catalog `meaningful-labels` compliance check, and the disallowed `not-applicable` `touch-target-size` compliance row, and added the required grounding sentence under Compliance; removed the dangling "(Rule 15)" citation and the noise `model` parameter edge case; deduplicated the Appearance/Padding text and the historical-defect edge case against their source-of-truth requirements and decisions, and reworded three edge cases from implied MUSTs to plain descriptions of model-owned behavior; marked Differentiate Without Color partial for the color-only highlight fill; fixed the WinUI 3 note to bind colors via `ThemeResource` only, pick one consistent selection approach, and drop an unsupported "reason this recipe exists" claim; and added test vectors for the title-present search-field position, a non-nil placeholder, the Up arrow, Return-with-a-highlight, a positive `onHighlight` fire, a shown multi-select checkbox, and a shown description label, replacing vector 028 with a behavior-based check of the shared keyboard controller. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
