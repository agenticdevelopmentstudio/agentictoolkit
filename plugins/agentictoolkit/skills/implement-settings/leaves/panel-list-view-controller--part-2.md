<!-- leaf: implement-settings/panel-list-view-controller--part-2 · source: settings-panel-list-view-controller.md -->

# PanelListViewController — continued (part 2)

## Platform Notes

- **SwiftUI**: Rebuild as a `List` (or `NavigationSplitView`'s sidebar
  column) whose rows are grouped into `Section`s by the same
  contiguous-run rule as `buildSections(from:)` — not a flat `Dictionary`
  `groupBy`, which would silently reorder panels sharing a section title
  that are not adjacent. Drive filtering from a `@State private var
  searchQuery: String` wired to `.searchable(text:)`, matched with a port
  of `SettingsSearchIndex`'s case-insensitive, all-terms-must-match rule.
  Bind selection with `List(selection: $selectedPanelID)` against a stable
  id equal to the panel's original index (mirroring
  **original-index-row-id**), and surface it to the caller via
  `.onChange(of: selectedPanelID)` rather than a stored closure. A disabled
  row should combine `.foregroundStyle(.tertiary)` with a second, non-color
  cue (see the Differentiate Without Color gap above), such as a trailing
  "Coming Soon" `Text`.
- **Compose**: Use a `LazyColumn` with one `item`/`stickyHeader` block per
  contiguous section run (built the same way, not via Kotlin's `groupBy`,
  for the same reordering reason). Hold `searchQuery` in a
  `mutableStateOf<String>`, feeding a `derivedStateOf` filtered, re-grouped
  list on every keystroke with the same all-terms matcher. Expose an
  `onPanelSelected: (Panel?) -> Unit` lambda fired from each row's
  `onClick`, and a `selectPanel(index: Int)` function that updates a
  `selectedIndex` state directly without invoking that lambda, mirroring
  **callback-free-selection**.
- **React/Web**: Render one `<ul role="listbox">`/`<section>` per contiguous
  run of matching `section` (computed with a single pass over the ordered
  array, not `Array.reduce` into a keyed map, for the same reordering
  reason), each row a `<li role="option" aria-selected="…">` (or, if plain
  buttons are preferred over a listbox/option structure, a
  `<button aria-current="…">`) showing the descriptor's icon and label. A
  controlled `<input type="search">` drives a `searchQuery` state variable
  that re-filters on every keystroke with the same case-insensitive,
  all-terms rule. Selection fires an `onSelectPanel(panel | null)` prop on
  click/`Enter`/`Space`; a separate `selectPanel(index)` helper updates only
  the highlighted-row state (`aria-selected`/`aria-current`) without invoking
  that prop, mirroring **callback-free-selection**.
- **AppKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsPanelListViewController.swift`,
  declaring `ComposableSettings.PanelListViewController`. A macOS-only
  (`import AppKit`), `@MainActor`, `open` subclass of
  `ComposableSettings.TopicListViewController`
  (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift`).
  It composes `ComposableSettings.SettingsSearchIndex`
  (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsSearchIndex.swift`)
  for filtering and
  reads `any ComposableSettingsPanel`'s `descriptor`
  (`ComposableSettings.SettingsPanelDescriptor`,
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsPanel/SettingsPanelDescriptor.swift`)
  to build each row,
  rather than reimplementing outline-view layout, theming, or row
  accessibility — all of that stays in the ancestor. There is no UIKit code
  path; a UIKit port would need to replace `NSOutlineView`'s row/section
  model with a `UITableView`/`UICollectionView` compositional layout, since
  neither has a direct outline-view equivalent for this content-driven,
  run-based grouping.
- **WinUI 3** (the reason this recipe exists): Build the sidebar as a
  `NavigationView` (`PaneDisplayMode="Left"`) or a `ListView` with
  `CollectionViewSource.IsSourceGrouped="True"`. Do NOT let
  `CollectionViewSource`'s built-in grouping key the whole list by section
  title — per the source's own comment on `buildSections(from:)`, that
  "hoisted every unsectioned panel to the top of the sidebar, silently
  reordering a list whose author had already put it in the order they
  meant"; instead, pre-partition the flat panel list into contiguous runs
  in code, exactly as `buildSections(from:)` does, before handing the
  grouped `ObservableCollection` to the control. Bind each
  `NavigationViewItem`/`ListViewItem`'s `Content` to the panel's title and
  `Icon` to a `SymbolIcon`/`BitmapIcon`. Keep `IsEnabled=true` for a
  `descriptor.isDisabled` row — mirroring `IsEnabled` to `isDisabled` would
  make the row unselectable, contradicting the Disabled state (the row stays
  selectable, styled only) — and instead style it with a muted
  `Foreground`/`SymbolIcon` brush plus, per the Differentiate Without Color
  gap, a non-color cue (a secondary "Coming soon" `TextBlock`, not `Opacity`
  alone, which repeats the same color-only gap this recipe flags).
  Bind an `AutoSuggestBox`/`TextBox` to a `searchQuery` property on the view
  model, re-filtering and re-grouping the `ObservableCollection` on every
  `TextChanged` with the same case-insensitive, all-terms-must-match rule as
  `SettingsSearchIndex.matches`. Raise the `onSelectPanel`-equivalent event
  from `SelectionChanged`/`ItemInvoked`, and implement a `SelectPanel(int
  index)` method that assigns `SelectedItem` under a reentrancy guard
  (mirroring the ancestor's `suppressingSelectionCallbacks`), since
  assigning `SelectedItem` directly would otherwise re-fire
  `SelectionChanged` and violate **callback-free-selection**.

## Design Decisions

- **Decision**: Identify each row by the panel's original index in the full,
  unfiltered array, rather than by its position in the currently filtered
  list.
  **Rationale**: Per the source's own doc comment on `visiblePanelIndices()`,
  "the position is the row's identity, so a filtered row still selects the
  panel it names" — a stable id under filtering is what lets
  `selectPanel(at:)`, `isPanelVisible(at:)`, and `SplitViewController`'s
  arrow-key stepping keep working correctly while a search query is active.
  **Approved**: pending
- **Decision**: Group panels into sections by contiguous run of matching
  `descriptor.section`, rather than by collecting every panel that shares a
  section title regardless of position.
  **Rationale**: Per the source's own comment on `buildSections(from:)`,
  "Sections come out in the order the panels arrive, and a run of panels
  sharing one section title is one section. Grouping by title across the
  whole list instead hoisted every unsectioned panel to the top of the
  sidebar, silently reordering a list whose author had already put it in
  the order they meant."
  **Approved**: pending
- **Decision**: Filter the sidebar in place (hiding non-matching rows) instead
  of replacing it with a separate search-results list.
  **Rationale**: Per the source's own doc comment on `searchQuery`, "Filtering
  the sidebar (rather than replacing it with a results list) is what keeps
  a search reversible: the row the user is reading stays where it was in
  the list, and deleting the query puts its neighbours back around it."
  **Approved**: pending
- **Decision**: Expose `isPanelVisible(at:)` as a separate query rather than
  having `selectPanel(at:)` silently clear the search query whenever the
  target row is currently filtered out.
  **Rationale**: Per the source's own doc comment on `isPanelVisible(at:)`,
  "clearing the search on the caller's behalf when it was not needed throws
  away a filter the user is still reading by" — the caller
  (`SplitViewController`) is expected to check visibility first and decide
  for itself whether to clear the query.
  **Approved**: pending
- **Decision**: `selectPanel(at:)` never invokes `onSelectPanel`.
  **Rationale**: Per the source's own doc comment, "programmatic selection
  flows through `SplitViewController.selectPanel`" (the comment predates a
  rename and still says `SettingsViewController`, but `SplitViewController`
  is the only caller in source that drives `selectPanel(at:)`), so the
  callback exists only to report a user-driven row pick, not to echo back a
  selection the caller itself just made.
  **Approved**: pending
- **Decision**: Declare `PanelListViewController` as `open`, letting a host
  app subclass it to customize row presentation or add secondary actions,
  rather than sealing it or exposing customization through composition only.
  **Rationale**: Per the source's own doc comment, "Open so client apps can
  customize row presentation or add secondary actions."
  **Approved**: pending
