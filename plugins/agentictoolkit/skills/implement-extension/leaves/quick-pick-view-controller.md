<!-- leaf: implement-extension/quick-pick-view-controller · source: extension-quick-pick-view-controller.md -->

**Rules** (cite as `implement-extension/quick-pick-view-controller#<slug>`):

- `designated-initializer` MUST
- `fixed-content-size` MUST
- `title-label` MUST
- `title-label-position` MUST
- `search-field-position` MUST
- `table-scroll-position` MUST
- `search-placeholder` MUST
- `live-filtering` MUST
- `arrow-and-return-routing` MUST
- `escape-routing` MUST
- `escape-idempotency` MUST
- `search-field-focus` MUST
- `single-native-selection` MUST
- `table-header` MUST
- `single-item-column` MUST
- `single-select-click` MUST
- `multi-select-click` MUST
- `separator-and-out-of-range-clicks` MUST
- `multi-select-checkbox` MUST
- `checked-state` MUST
- `description-and-detail` MUST
- `separator-label` MUST
- `highlight-selection-sync` MUST
- `empty-choose` MUST
- `separator-selection-guard` MUST
- `test-identifiers` MUST
- `shared-keyboard-controller` MUST

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

