<!-- leaf: implement-general-controller/split-view-controller--part-4 · source: split-view-controller.md -->

# SplitViewController — continued (part 4)

## Platform Notes

- **SwiftUI**: Use `NavigationSplitView` with a `List` (built from `panels`)
  as the sidebar column and the selected panel's view as the detail column.
  For `contentSizedSidebar == true`, set the sidebar column's
  `.navigationSplitViewColumnWidth(min:ideal:max:)` to the same fixed value
  (min == ideal == max), the nearest SwiftUI analog of a pinned,
  non-draggable width; for the draggable default, use `min: 160, ideal:
  <persisted>, max: 360` and persist the ideal width yourself (SwiftUI has
  no built-in per-split autosave equivalent to `NSSplitView.autosaveName`).
  Use `.searchable(text:)` on the sidebar for `showsSidebarSearch`, and
  drive back/forward with a small custom index stack, since
  `NavigationSplitView` has no built-in in-place trail matching
  `SettingsNavigationHistory`'s discard-forward-on-new-step semantics.
- **Compose**: Compose a two-pane `ListDetailPaneScaffold` (Material 3
  adaptive) or a manual `Row` of a fixed-width `LazyColumn` sidebar plus a
  weighted detail `Box`. Size the sidebar with
  `Modifier.width(IntrinsicSize.Max)` for the content-sized case, or a
  draggable divider whose width is saved to `DataStore`/`SharedPreferences`
  (mirroring the autosave) for the default case. Filter the list with an
  `OutlinedTextField` bound to a `mutableStateOf` query; implement
  back/forward as a small `MutableList<Int>` index trail, since Compose
  Navigation's back stack tracks destinations, not row selections within
  one screen.
- **React/Web**: A CSS Grid two-column layout
  (`grid-template-columns: <sidebar> 1fr`), sidebar `<nav>` of `<button>`s
  or links, detail `<main>`. For the content-sized case, size the sidebar
  column `max-content`; for the draggable default, add a resizer handle
  that persists its width to `localStorage` under a key analogous to
  `sidebarAutosaveName`. Filter with a controlled `<input type="search">`;
  implement back/forward as an in-memory index stack rather than the
  browser History API, since each panel is not necessarily its own route.
- **AppKit / UIKit** (source platform): Source file
  `SplitViewController.swift` (`ComposableSettingsWindow/SplitViewController/`),
  AppKit-only — an `NSSplitViewController` subclass of `ThemedSplitViewController`,
  composing a `PanelListViewController` sidebar item and a `PanelHostView`-hosted
  detail item, wrapping non-self-scrolling panel content in a
  `PanelScrollView`, and tracking navigation with a
  `SettingsNavigationHistory` value type. `panels` is declared
  `private(set)`, enforcing **exposes-hosted-panels-read-only** at compile
  time. `init(coder:)` is `@available(*, unavailable)` and its body is
  `fatalError()`, giving **rejects-coder-initialization** its fatal error.
  The sidebar item's `holdingPriority` is `.defaultLow + 1` against the
  detail item's `.defaultLow`, which is how
  **prioritizes-detail-pane-on-resize** is implemented. `currentPanel` is
  computed by reading `detailContainer.children.first`, and
  `enclosingSettingsSplit` walks `parent` upward looking for the nearest
  `ComposableSettings.SplitViewController` — the mechanisms behind
  **reports-current-panel-from-detail-container** and
  **locates-enclosing-split-by-parent-chain**. No UIKit counterpart exists in
  this codebase (`ComposableSettingsWindow/` is entirely AppKit); a UIKit
  port would reach for `UISplitViewController` with `.doubleColumn` style,
  though it has no analog of `contentSizedSidebar`'s pinned min==max
  thickness or of `NSSplitView`'s dragging-based `autosaveName` persistence.
- **WinUI 3** (the reason this recipe exists): Use a `NavigationView` with
  `PaneDisplayMode="Left"` as the sidebar and its `Content`/`Frame` as the
  detail region. Bind `MenuItems` to the panel list — one
  `NavigationViewItem` per panel, grouped under a `NavigationViewItemHeader`
  per `descriptor.section` run, mirroring `PanelListViewController`'s
  section grouping — and drive selection through `SelectionChanged`
  (analogous to `listViewController.onSelectPanel`). For the draggable
  default (`contentSizedSidebar == false`), set
  `IsPaneToggleButtonVisible="False"` and bind `OpenPaneLength` to a value
  restored from `ApplicationData.LocalSettings` keyed by
  `sidebarAutosaveName`, constrained to a `160`–`360`-equivalent range; for
  `contentSizedSidebar == true`, fix `OpenPaneLength` to the pane's measured
  content width and skip persistence entirely, exactly as this file does.
  There is no WinUI analog of `NSSplitViewItem.minimumThickness` on the
  content side, so approximate `detailMinimumThickness` (and the raised
  nested-sibling floor) with a `MinWidth` on the `Frame`/`ContentPresenter`
  hosting `Content`. For search, add an `AutoSuggestBox` as
  `NavigationView.PaneCustomContent`, wire `TextChanged` to filter
  `MenuItems.Source` the way `searchQueryChanged` filters
  `PanelListViewController`, and forward the list's Up/Down `KeyDown` to
  move `SelectedItem` while the `AutoSuggestBox` keeps focus — mirroring
  `control(_:textView:doCommandBy:)`. Implement back/forward with two
  `Stack<int>`s alongside `NavigationView.BackRequested`, since
  `SettingsNavigationHistory`'s trail semantics (discard-forward-on-new-
  step, no-op on re-selecting the current row) have no built-in WinUI
  equivalent; for a nested `NavigationView` acting as
  `SettingsPanelSplitViewController` does, forward whichever inner item is
  selected up to the outer shell's single help affordance, mirroring
  `effectiveHelp`/`refreshHelp()`'s outward chain.

## Design Decisions

**Decision**: `detailMinimumThickness` floors the detail pane's
`NSSplitViewItem.minimumThickness` rather than a required-width constraint
on the detail content.
**Rationale**: Per the source's own comment, this "lets the detail grow
freely, unlike a required width constraint on the content, which pins the
window"; it is "the proper lever for the window's minimum width (window
min = sidebar thickness + this)."
**Approved**: pending

**Decision**: `contentSizedSidebar` defaults to `false` for this base class
(the draggable, autosaved band), even though nested splits generally want
`true`.
**Rationale**: Per the source's own comment, "the full-height *root* window
sidebar keeps the draggable behaviour (its outline's column-fill misbehaves
under a fixed width). Nested topic/detail splits opt in — they're the ones
that visibly 'move around' as you switch between them."
**Approved**: pending

**Decision**: `showsSidebarSearch` and `sortsPanelsByTitle` both default to
`false` and are switched on only for the window's root split.
**Rationale**: Per the source's own comments, a nested split's sidebar is
"a table of contents for one panel" written in an intentional order, while
the root window's list is "a set of unrelated destinations" a reader can
only find by name or by search; a second search field inside an outer
split's already-filtered results "is a maze."
**Approved**: pending

**Decision**: `moveSelection(by:)` (arrow-key stepping) leaves the search
field's text and query untouched, unlike `selectPanel`/`goBack`/`goForward`,
which all clear it.
**Rationale**: Per the source's own comment, "the query is the very thing
the reader is steering by when they press Down, so clearing it would throw
away the list they are moving through and jump the highlight somewhere
else."
**Approved**: pending

**Decision**: `SplitViewController` conforms to `NSSearchFieldDelegate`
solely to intercept `moveDown(_:)`/`moveUp(_:)`, returning `false` for
every other command selector.
**Rationale**: Per the source's own comment, this is answered in the
delegate callback "rather than in a `keyDown` override because AppKit has
already turned the key into the reader's intent by this point — and
returning false for every other command leaves the rest of text editing
exactly as it was."
**Approved**: pending

**Decision**: `currentPanelTitle` and `effectiveHelp` both recurse into a
selected panel that is itself a `SplitViewController`, reporting that
inner split's own title/help rather than this instance's.
**Rationale**: Per the source's own comment, "a split whose selected panel
is itself a split answers with the topic selected *inside* it: that is the
panel the reader is looking at," and naming the outer container instead
"left the toolbar stuck on the container's name while the reader moved
down its list."
**Approved**: pending

**Decision**: `unifyNestedSidebars()` leaves `nestedDetailFloor` unchanged
(rather than resetting it toward `0`) whenever the current panel set has
fewer than two nested `SplitViewController` panels.
**Rationale**: Not stated in source. The method's guard clause returns
before recomputing the floor, so a detail-pane floor raised while two or
more nested splits were present can outlive their removal until a later
state again has two or more. Documented here as observed behavior (see
Edge Cases and split-view-controller-054), not as a deliberate design
tradeoff.
**Approved**: pending
