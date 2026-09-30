<!-- leaf: implement-extension/quick-pick-view-controller--part-2 · source: extension-quick-pick-view-controller.md -->

# ExtensionQuickPickViewController — continued (part 2)

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `ExtensionQuickPickModel` | — (required) | Owns `request` (title, placeholder, items, `canPickMany`, `matchOnDescription`/`matchOnDetail`), the filter query, `visibleIndices`, `highlightedIndex`, and `checkedIndices`. Supplied once at `init` and never replaced. |
| `onAccept` | `([Int]) -> Void` | no-op closure | Called with the chosen indices into `model.request.items` when the user accepts (Return, or a single-select click). |
| `onCancel` | `() -> Void` | no-op closure | Called on Escape (key or window-level monitor); not part of this file's `ignoreFocusOut`/focus-loss handling, which is `ExtensionPickerWindowController`'s concern, not this view controller's. |
| `onHighlight` | `(Int) -> Void` | no-op closure | Called from the single place the highlight is synced to the table (`syncSelection()`), whenever a row becomes highlighted. |

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in `ExtensionQuickPickViewController.swift`; every state change (filtering, highlighting, checking) is an instantaneous property assignment or table reload. |
| Increase Contrast | Not applicable to this file directly: no custom `NSColor` is ever set here; every color comes from a `ThemeRole` resolved by the active theme's `SemanticPalette`, so Increase Contrast support is the active theme's responsibility, not this component's. |
| Differentiate Without Color | Partial: the checked state itself is communicated solely by the checkbox's own on/off checkmark glyph — no color-only signal there. But the *highlighted* row (arrow-key focus) is shown only by `ThemedTableRowView`'s `.selection`-role fill (a 4pt-corner-radius, 2pt/1pt-inset rounded rect — see **States** › Focused); this file draws no separate icon, border, or text-weight change alongside that fill, so whether the highlight is distinguishable without color depends entirely on that fill's contrast against the row's normal background. |

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

