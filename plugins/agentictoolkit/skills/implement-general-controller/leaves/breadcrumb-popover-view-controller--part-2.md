<!-- leaf: implement-general-controller/breadcrumb-popover-view-controller--part-2 · source: breadcrumb-popover-view-controller.md -->

# BreadcrumbPopoverViewController — continued (part 2)

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext` call; every state change (selection,
  filtering) is an instantaneous property assignment or synchronous
  `reloadData()`.
- **Increase Contrast**: Not applicable — `BreadcrumbPopoverViewController.swift`
  sets no custom `NSColor` anywhere; row and search-field appearance come
  entirely from AppKit's default control/label rendering.
- **Differentiate Without Color**: Satisfied — matched filter characters are
  conveyed by bold font weight (`attributedTitle(for:)`), not by color; row
  selection is AppKit's default highlight, not a component-defined color
  cue.

## Privacy

- **Data collected**: None by the component itself — it reads local
  file/directory names via `FileTreeNode.loadChildren(for:)` for display
  only.
- **Storage**: In-memory only (`entries`, `filtered` arrays), for the view
  controller's lifetime; nothing is written to disk, `UserDefaults`, or any
  other store by this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view controller's lifetime; state is
  discarded when the popover closes.

## Platform Notes

- **SwiftUI**: Use a `List(filteredEntries, selection: $selectedID)` inside a
  `.popover`/sheet, with a `.searchable(text: $filterText)` modifier feeding
  the same substring-match predicate as `applyFilter`. Bind arrow-key,
  Return, and Escape handling via `.onKeyPress(_:)` in place of
  `PickerKeyboardController`'s command-selector routing, and highlight
  matched-range substrings by building an `AttributedString` per row with
  `.bold()` applied to the matched runs, mirroring `attributedTitle(for:)`.
  Give the list a fixed `.frame(width: 280, height: 320)` (matching
  fixed-content-size) in place of `preferredContentSize`. A directory row's
  tap/selection action should be a no-op, mirroring `guard !node.isDirectory`.
- **Compose**: Host in a `Popup` or `DropdownMenu` sized to a fixed
  280×320dp `Box` (matching fixed-content-size). Compose's `LazyColumn` has
  no built-in keyboard-driven
  single selection the way `NSTableView` plus `PickerKeyboardController`
  provides, so intercept Up/Down/Enter/Escape with
  `Modifier.onPreviewKeyEvent` on the filter `OutlinedTextField`, moving a
  `selectedIndex` state and calling `LazyListState.animateScrollToItem` — the
  Compose analog of `scrollRowToVisible`. Render matched substrings with
  `buildAnnotatedString` and `SpanStyle(fontWeight = FontWeight.Bold)` over
  the matched ranges. A directory row's `onClick` should be a no-op,
  mirroring `guard !node.isDirectory`.
- **React/Web**: A fixed 280×320px container (matching fixed-content-size)
  with an `<input type="search">`
  for the filter (its `onChange` re-filters immediately, mirroring
  `sendsSearchStringImmediately`/`controlTextDidChange`) above a
  `<ul role="listbox">` of `<li role="option">` rows. Implement Up/Down/
  Enter/Escape in the input's `onKeyDown` handler, updating a `selectedIndex`
  state and calling `element.scrollIntoView({ block: "nearest" })` on the
  newly selected row, mirroring `scrollRowToVisible`. Render matched
  substrings by wrapping the matched ranges in a bold `<strong>`/span,
  mirroring `attributedTitle(for:)`. A directory row should ignore both click
  and Enter-to-choose, mirroring `guard !node.isDirectory`.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/BreadcrumbPopoverViewController.swift`.
  A `@MainActor`, `final` `NSViewController` presented as the content view
  controller of an `NSPopover` opened by a `BreadcrumbView` crumb. It builds
  its view by hand in `loadView()` — an `NSSearchField` above an
  `NSTableView` wrapped in an `NSScrollView`, laid out with Auto Layout
  constraints against a root `NSView` given an explicit 280×320 frame (see
  the loadView-frame Design Decision) — rather than loading a nib or using
  SwiftUI. Filtering (`applyFilter`), keyboard navigation
  (`PickerKeyboardController`, wired in `viewDidAppear`), and match
  highlighting (`ProjectFilter.ranges(of:in:)`, applied in
  `attributedTitle(for:)`) are shared collaborators reused from the app's
  other filterable pickers, not reimplemented locally. Keyboard routing
  (arrow-keys-move-selection, return-key-chooses-selection,
  escape-key-cancels) is wired in `viewDidAppear` by assigning
  `keyboard.onMoveSelection`, `keyboard.onChoose`, and `keyboard.onCancel`
  closures and calling `keyboard.startEscapeMonitor(for: view.window)`; the
  monitor is stopped in `viewWillDisappear`. Because `NSSearchField` normally
  consumes arrow keys, Return, and Escape as ordinary text-editing commands,
  the `NSSearchFieldDelegate` method
  `control(_:textView:doCommandBy:)` intercepts those command selectors
  first and forwards them to `keyboard.handle(_:)`, returning its `Bool`
  result so AppKit knows the key was handled. Row views (reuse-row-views)
  come from `tableView.makeView(withIdentifier:owner:) as? NSTableCellView`,
  falling back to constructing a new `NSTableCellView` only when none is
  available for reuse. There is no UIKit code path in source; a UIKit port
  would replace `NSSearchField`/`NSTableView` with `UISearchBar`/
  `UITableView`, present the whole thing in a
  `UIPopoverPresentationController` (iPad) or a sheet (iPhone) instead of
  `NSPopover`, would need to grow the 20pt AppKit row height to at least a
  44pt touch target, and would need `UIKeyCommand`-based hardware-keyboard
  handling to reach parity with `PickerKeyboardController`'s arrow-key/
  Return/Escape routing, since UIKit has no built-in equivalent.
- **WinUI 3** (the reason this recipe exists): Build the popover content as
  a `TextBox` with a `TextChanged` handler (not an `AutoSuggestBox`: its
  built-in suggestion flyout would open its own popup list directly under
  the box, clashing with the separate `ListView` this recipe already needs
  below it) stacked above that `ListView`, bound to the filtered collection,
  both hosted inside a `Flyout` (not a `MenuFlyout`, since arbitrary content —
  a search box plus a list — is needed, mirroring the AppKit choice of
  `NSPopover` over a plain menu) anchored to the breadcrumb crumb's button,
  sized to a fixed 280×320 epx `Grid` (matching fixed-content-size) in place
  of `preferredContentSize`. Update the `ListView`'s bound collection on
  every `TextBox.TextChanged` event, mirroring `applyFilter`'s
  `query.isEmpty ? entries : entries.filter { ... }` substring match, and
  reselect index 0 after every filter change, mirroring
  `reselect-first-row-after-filter`. Since WinUI has no `doCommandBy:`-style
  command-selector routing, intercept Up/Down/Enter/Escape in the
  `TextBox`'s `PreviewKeyDown` handler, moving
  `ListView.SelectedIndex` and calling `ListView.ScrollIntoView(item)` — the
  direct analog of `scrollRowToVisible` — for Up/Down, invoking the choose
  logic for Enter, and calling `Flyout.Hide()` for Escape, the analog of
  `onCancel`. Render each row as a `TextBlock` containing multiple `Run`
  elements with `FontWeight="Bold"` applied to the matched ranges from the
  same substring-match logic, mirroring `attributedTitle(for:)`, and set
  `TextTrimming="CharacterEllipsis"`; note that WinUI's built-in ellipsis
  trims from the end, so approximating AppKit's middle-truncation
  (`truncate-row-label-middle`) requires either manual string splitting
  around the matched range or accepting end-truncation as the closest native
  equivalent — call this out to implementors as a deliberate platform
  difference. A `ListViewItem` bound to a directory entry should be a no-op
  in the `ItemClick`/`SelectionChanged` handler, mirroring
  `guard !node.isDirectory`.

## Design Decisions

- **Decision**: Give the popover's root view an explicit pixel frame
  (`NSRect(origin: .zero, size: Self.contentSize)`) in `loadView()`,
  alongside setting `preferredContentSize` in `init`.
  **Rationale**: Per the `loadView` source comment, `NSPopover` sizes an
  Auto-Layout content view to that view's fitting size and ignores its own
  `contentSize`; with no subview here having an intrinsic width, an unsized
  root would collapse to a 16×46pt sliver. The frame gives the root view an
  explicit width and height (since `translatesAutoresizingMaskIntoConstraints`
  stays `true` on it) for the constrained subviews to hang from, matching
  what `preferredContentSize` tells the popover separately.
  **Approved**: pending
- **Decision**: Reuse `PickerKeyboardController` for keyboard wiring and
  `ProjectFilter.ranges(of:in:)` for match highlighting instead of
  implementing either locally.
  **Rationale**: Per the type's doc comment, these are "the same two pieces
  the provider and model pickers already share" — reusing them keeps
  keyboard behavior and match highlighting consistent across every
  filterable picker in the app instead of a fourth, divergent implementation.
  **Approved**: pending
- **Decision**: Guard `chooseAction()` so choosing a directory row is a
  no-op instead of navigating into the subdirectory.
  **Rationale**: Per the type's doc comment, "Choosing a directory row does
  nothing; only files can be opened from here" — this popover is scoped to
  opening a file at the crumb's own directory level, not to browsing further
  down the tree.
  **Approved**: pending
- **Decision**: Unconditionally reselect row 0 in `applyFilter()` after
  every filter change, rather than preserving the previous selection or
  re-selecting the closest surviving match.
  **Rationale**: `applyFilter()` calls `selectRow(0)` on every invocation
  with no branch to preserve prior selection identity; this keeps the
  type-to-narrow-then-Return flow always landing on the top result without
  added logic to track selection identity across filter changes.
  **Approved**: pending
