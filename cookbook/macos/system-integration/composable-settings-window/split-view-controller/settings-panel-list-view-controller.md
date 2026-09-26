---
id: a41760b2-4ffd-413b-970f-c0373c9bd3b6
title: PanelListViewController
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/split-view-controller/settings-panel-list-view-controller
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Sidebar of ComposableSettings.SplitViewController - maps panels to sectioned
  rows, filters them by search query, and bridges row selection back to the selected
  panel
platforms:
- swift
- macos
tags:
- settings
- sidebar
- search
- split-view
- appkit
depends-on:
- agentictoolkit://cookbook/macos/ui/view-controllers/topic-list-view-controller
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/settings-panel/settings-panel-view-controller
related:
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-settings-view-controller
references:
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
approved-by: ''
approved-date: ''
---

# PanelListViewController

## Overview

`ComposableSettings.PanelListViewController` (declared in
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsPanelListViewController.swift`,
despite the file's own name) is the sidebar of `ComposableSettings.SplitViewController`
— a macOS, `@MainActor`, `open` subclass of `ComposableSettings.TopicListViewController`
(`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift`).
`TopicListViewController` is a domain-agnostic, sectioned `NSOutlineView` sidebar
that knows nothing about settings; `PanelListViewController` maps an ordered
array of `any ComposableSettingsPanel` onto that ancestor's row model
(`TopicListSection`/`TopicListItem`) and translates the ancestor's generic
row-selection callback back into the specific panel the reader picked.

Beyond what `TopicListViewController` already renders and themes, this file
owns three concerns: (1) turning each panel's `descriptor` into a row, (2)
narrowing the visible rows by a live `searchQuery`, delegated to
`ComposableSettings.SettingsSearchIndex`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsSearchIndex.swift`),
and (3) keeping a
row's identity — the panel's index in the full, unfiltered array — stable
across filtering, so a caller (`ComposableSettings.SplitViewController`) can
select, query the visibility of, and arrow-key through panels by index no
matter what the search field currently hides.

## Behavioral Requirements

- **panel-storage**: `setPanels(_:)` MUST store the given array as the
  component's full, ordered panel list, replacing whatever was stored before.
- **panel-set-rebuild**: `setPanels(_:)` MUST rebuild the
  sidebar's sections from the newly stored array before returning.
- **unchanged-query-guard**: Assigning `searchQuery` a value equal
  to its current value MUST NOT trigger a section rebuild (guarded by
  `oldValue != searchQuery`).
- **query-change-rebuild**: Assigning `searchQuery` a
  value different from its current value MUST trigger a section rebuild.
- **empty-query-inclusion**: A `searchQuery` that is empty, or
  contains only whitespace/newline characters, MUST include every stored
  panel among the visible rows.
- **all-terms-match**: A non-empty, non-whitespace `searchQuery`
  MUST include a panel only if every one of its space-separated terms is
  found, case-insensitively, as a substring of that panel's searchable text
  (per `SettingsSearchIndex.matches`, harvested from `descriptor.title`,
  `descriptor.section`, `searchKeywords`, `helpContent`'s topic titles and
  bodies, and — once the panel's own view has loaded — the titles of its
  non-editable `NSTextField`s, `NSButton`s, and `NSPopUpButton` items).
- **panel-order-preservation**: Visible rows MUST appear in the same
  relative order as their panels in the array most recently passed to
  `setPanels(_:)`.
- **contiguous-section-grouping**: Panels MUST be grouped into sidebar
  sections by contiguous run of equal `descriptor.section` value among the
  panels the current query admits; a panel whose section differs from the
  immediately preceding admitted panel's section MUST start a new section,
  even when an earlier, non-adjacent panel already used that same section
  title.
- **descriptor-row-mapping**: Each row's title, icon, and
  disabled-appearance flag MUST be read from that panel's `descriptor.title`,
  `descriptor.icon`, and `descriptor.isDisabled`, respectively, at the moment
  sections are rebuilt.
- **original-index-row-id**: Each row's identifier MUST be the string
  form of its panel's zero-based index in the full array passed to
  `setPanels(_:)`, independent of that row's position under the current
  filter.
- **selection-callback-bridge**: When constructed via
  `init(nibName:bundle:)` (the designated initializer), the component MUST
  invoke `onSelectPanel` with the panel resolved from the newly selected
  row's identifier whenever the underlying selection changes, and MUST
  invoke `onSelectPanel` with `nil` when the selection is cleared.
- **coder-init-bridge-omission**: When constructed via
  `init?(coder:)`, the component MUST NOT establish the `onSelectPanel`
  bridge described above; that initializer calls only `super.init(coder:)`
  and performs no further setup.
- **callback-free-selection**: `selectPanel(at:)` MUST select the row
  identified by the given index without invoking `onSelectPanel`.
- **out-of-range-select-guard**: `selectPanel(at:)` MUST have no effect
  when `index` falls outside `panels.indices`.
- **panel-visibility-report**: `isPanelVisible(at:)` MUST return `true` if,
  and only if, the panel at the given index is among the panels the current
  `searchQuery` admits.
- **visible-index-report**: `visiblePanelIndices()` MUST return
  the original-array indices of the panels the current `searchQuery` admits,
  in ascending order.
- **row-id-panel-resolution**: Resolving a panel from a row's identifier
  MUST parse that identifier as an integer and MUST yield no panel when the
  identifier is not a valid integer or falls outside `panels.indices`.

## Appearance

- **Corner radius**: Not set by this file. Rows are plain `NSTableCellView`s
  with no corner radius anywhere in `TopicListViewController`'s cell
  factories, and this file overrides none of that layout.
- **Padding**: Not set by this file; inherited unmodified from
  `TopicListViewController.CellMetrics` — see
  `agentictoolkit://cookbook/macos/ui/view-controllers/topic-list-view-controller#appearance/padding`
  for the insets this component renders with.
- **Font**: Not set by this file; inherited unmodified from the same
  `CellMetrics` — see
  `agentictoolkit://cookbook/macos/ui/view-controllers/topic-list-view-controller#appearance/font`.
- **Background**: Not set by this file; inherited unmodified —
  `TopicListViewController.applyTheme` paints the view, content stack,
  header, footer, and outline/scroll view background. See
  `agentictoolkit://cookbook/macos/ui/view-controllers/topic-list-view-controller#appearance/background`.
- **Foreground/Text**: Not set by this file; inherited unmodified from
  `TopicListViewController.outlineView(viewFor:)`. See
  `agentictoolkit://cookbook/macos/ui/view-controllers/topic-list-view-controller#appearance/foreground-text`
  for the exact color/state mapping this component's rows use.
- **Border**: Not set by this file. `TopicListViewController` draws a 1pt
  hairline divider above every row in a card except the first, but a plain
  sidebar row (as this component uses) draws no such divider; no border is
  set anywhere in either file.
- **Shadow**: Not applicable — no shadow, `NSShadow`, or layer-shadow
  property is set anywhere in this file or in `TopicListViewController`.
- **Min/Max size**: Not set by this file. `TopicListViewController.preferredWidth()`
  computes the sidebar's content-driven width from the widest row/title, and
  this file does not override it; there is no maximum width in either file.

## States

| State | Appearance change |
|-------|------------------|
| Default | Row shows `descriptor.title`/`descriptor.icon` with `primaryTextColor`/`accentColor`, unselected. |
| Selected | Row highlight comes entirely from `NSOutlineView`'s native selection rendering (`ThemedTableRowView`, inherited); this file restyles nothing further on selection. |
| Disabled (panel) | `descriptor.isDisabled == true`: text and icon tint switch to `tertiaryTextColor` (inherited from `TopicListViewController`); the row remains selectable — `outlineView(_:shouldSelectItem:)` does not gate on `isDisabled`, so this file (and its ancestor) let a disabled row be clicked and selected like any other. |
| Filtered out | A panel `searchQuery` excludes contributes no row at all — it is absent from the sidebar entirely, not shown greyed out or struck through. |
| Pressed | Not applicable: an outline row has no separate pressed/hover visual distinct from selection; this file adds no press styling of its own. |
| Focused | Not customized: standard `NSOutlineView` keyboard-focus ring, unchanged by this file or its ancestor. |
| Loading | Not applicable: `setPanels(_:)` and every rebuild it triggers are synchronous; no asynchronous load or spinner exists anywhere in this file. |

## Accessibility

- **Role/trait**: Not customized by this file; inherited unmodified from
  `TopicListViewController`, whose item rows use a plain text-field label
  (with a custom `accessibilityPerformPress` override) and whose section
  headers are marked as group items.
- **Label requirements**: Each row's accessible name comes from
  `descriptor.title`, which this file copies directly into `TopicListItem.title`;
  the ancestor then uses that same title, slugged, as the row's accessibility
  identifier (`topic-list.item.<slug>`). This file sets no accessibility
  label or identifier of its own.
- **Announce state changes (e.g., loading, disabled)**: Selection changes
  are posted through `NSOutlineView`'s own native accessibility
  notifications (inherited, unmodified); this file issues no
  `NSAccessibility.post` call of its own for a section rebuild, a search
  filter change, a panel's `isDisabled` flip, or a descriptor mutated after
  the sidebar has already been populated (see Edge Cases).
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  keyboard-driven `NSOutlineView` row (no touch input path in this file or
  its ancestor); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| cts-panel-list-001 | panel-storage | `setPanels([panelA, panelB])` | The sidebar shows exactly two rows, for `panelA` and `panelB`, in that order |
| cts-panel-list-002 | panel-set-rebuild | `setPanels([panelA])`, then `setPanels([panelA, panelB])` | The sidebar shows two rows after the second call, without a separate rebuild call being needed |
| cts-panel-list-003 | unchanged-query-guard | Construct a test subclass overriding `setSections(_:)` to increment a counter; `setPanels([panelA, panelB])`; set `searchQuery = "x"`; record the counter; set `searchQuery = "x"` again (identical) | The counter after the second assignment equals the counter recorded after the first — `setSections(_:)` was not called again |
| cts-panel-list-004 | query-change-rebuild | Same counter subclass as cts-panel-list-003; `setPanels([panelA, panelB])`; set `searchQuery = "a"`; record the counter; set `searchQuery = "b"` | The counter after the second assignment is one greater than after the first — `setSections(_:)` was called again |
| cts-panel-list-005 | empty-query-inclusion | `setPanels([panelA, panelB])`, then `searchQuery = "   "` | Both rows remain visible |
| cts-panel-list-006 | all-terms-match | `setPanels([panelA])` where `panelA.descriptor.title == "General"` and `panelA.descriptor.section == "App"`, then `searchQuery = "app general"` | `panelA`'s row is visible; `searchQuery = "app missing"` then hides it |
| cts-panel-list-007 | panel-order-preservation | `setPanels([panelB, panelA])`, `searchQuery = ""` | Rows appear in the order `panelB`, `panelA` |
| cts-panel-list-008 | contiguous-section-grouping | `setPanels([p1(section: "A"), p2(section: "B"), p3(section: "A")])` | Three sections render, in order A, B, A — not two sections of A merged |
| cts-panel-list-009 | descriptor-row-mapping | `setPanels([panelA])` where `panelA.descriptor` has a specific title, icon, and `isDisabled == true` | The row shows that title and icon and renders in the disabled appearance |
| cts-panel-list-010 | original-index-row-id | Construct via `init(nibName:bundle:)`; `setPanels([panelA, panelB])`, `searchQuery = "panelB-only-term"` (hides `panelA`); select the surviving row through the outline view directly (not via `selectPanel(at:)`) | `visiblePanelIndices() == [1]`, and `onSelectPanel` is invoked with `panelB` — proving the surviving row's id still resolves to index `1`, not re-indexed to `0` |
| cts-panel-list-011 | selection-callback-bridge | Construct via `init(nibName:bundle:)`, `setPanels([panelA])`, click `panelA`'s row | `onSelectPanel` is invoked once with `panelA` |
| cts-panel-list-012 | coder-init-bridge-omission | Construct via `init?(coder:)`, `setPanels([panelA])`, select `panelA`'s row through the outline view directly | `onSelectPanel` is never invoked (it was never wired) |
| cts-panel-list-013 | callback-free-selection | Set `onSelectPanel` to a spy closure, call `selectPanel(at: 0)` | The row at index 0 becomes selected; the spy closure is not called |
| cts-panel-list-014 | out-of-range-select-guard | `setPanels([panelA])`, call `selectPanel(at: 5)` | No row's selection changes; no crash |
| cts-panel-list-015 | panel-visibility-report | `setPanels([panelA, panelB])`, `searchQuery` set to a term matching only `panelB` | `isPanelVisible(at: 0) == false`, `isPanelVisible(at: 1) == true` |
| cts-panel-list-016 | visible-index-report | `setPanels([p0, p1, p2])`, `searchQuery` set to a term matching only `p0` and `p2` | `visiblePanelIndices() == [0, 2]` |
| cts-panel-list-017 | row-id-panel-resolution | Select a row whose underlying id is `"1"` for `setPanels([panelA, panelB])` | `onSelectPanel` receives `panelB`; simulating a stale/malformed id (e.g. `"not-a-number"` or `"9"`) resolves to no panel |

## Edge Cases

- **Null/empty input**: `setPanels([])` MUST leave the sidebar with no
  sections and no rows, with no crash — `buildSections(from:)` over an empty
  sequence returns an empty array. `searchQuery = ""` MUST match every panel
  (see **empty-query-inclusion**).
- **Boundary values**: `selectPanel(at:)`, `isPanelVisible(at:)`, and the
  internal row-id resolver MUST behave correctly at the first (`0`) and last
  (`panels.count - 1`) valid indices, and MUST silently no-op (rather than
  trap) for any index `< 0` or `>= panels.count`, since each guards with
  `panels.indices.contains(index)` before acting.
- **Concurrent access**: Not a runtime race condition to defend against —
  the class and its stored state are `@MainActor`-isolated
  (`@MainActor open class PanelListViewController`), so the Swift compiler
  rejects off-main mutation of `panels`, `searchQuery`, or `onSelectPanel`
  at compile time; the source adds no additional locking because none is
  needed.
- **Error states**: Not applicable — `setPanels`, `searchQuery`, and
  `selectPanel(at:)` are synchronous, always-succeeding, in-memory
  operations with no fallible dependency (no network, disk, or database
  call) anywhere in this file.
- **Offline/disconnected state**: Not applicable — no networking of any
  kind appears anywhere in this file.
- **Query with repeated whitespace**: A `searchQuery` containing multiple
  consecutive spaces (e.g. `"a  b"`) MUST narrow the same way a single-spaced
  query does — `split(separator: " ")` omits empty subsequences by default,
  so extra spacing does not introduce a term that trivially matches
  everything.
- **Panel with a blank title**: A panel whose `descriptor.title == ""`
  renders a row with an empty label; this file performs no validation or
  fallback text for a blank title.
- **Descriptor mutated after `setPanels(_:)`**: `descriptor.title`,
  `.icon`, `.isDisabled`, and `.section` are all `@Published`
  (`ComposableSettings.SettingsPanelDescriptor: ObservableObject`), but this
  file subscribes to none of them — rows are built once, when
  `setPanels(_:)` or a `searchQuery` change triggers `rebuildSections()`. A
  panel's descriptor mutated after the sidebar has already been populated
  leaves that row showing stale text/icon/disabled-state until some later
  `setPanels(_:)` or `searchQuery` change triggers a rebuild; this file does
  not subscribe to `descriptor.objectWillChange` or otherwise refresh a row
  automatically.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| panels | `[any ComposableSettingsPanel]` | `[]` | Full, ordered panel list backing the sidebar; set via `setPanels(_:)`. |
| searchQuery | `String` | `""` | Narrows the visible rows to panels whose harvested text matches every space-separated term; empty shows every panel. |
| onSelectPanel | `(((any ComposableSettingsPanel)?) -> Void)?` | `nil` | Invoked with the panel behind the row the user selects, or `nil` when cleared; wired to the ancestor's `onSelect` only inside `init(nibName:bundle:)`. |

## Deep Linking

Not applicable: this file contains no URL scheme, route, or deep-link
handling. Row selection is driven entirely by in-process panel objects and
integer indices, never by a URL.

## Localization

Not applicable to this file: it defines no string literal of its own. Every
row's displayed text (`title`) is read at runtime from the caller-supplied
`panel.descriptor.title` (a plain `String`, since this is AppKit, not
SwiftUI — there is no `LocalizedStringKey` inference here). Localizing that
text is the responsibility of whichever type constructs each
`ComposableSettings.SettingsPanelDescriptor`, outside this file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in this file; `setSections`/`reloadData` (inherited) apply immediately. |
| Increase Contrast | Not applicable: this file sets no custom `NSColor`; all coloring flows through the inherited `TopicListViewController` lookups against the active `SemanticPalette`, unmodified here. |
| Differentiate Without Color | Not supported: a disabled panel's row is distinguished from an enabled one by text/icon color alone (`tertiaryTextColor` vs. `primaryTextColor`/`accentColor`, in `TopicListViewController.outlineView(viewFor:)`); `cell.textField?.alphaValue` is fixed at `1.0` regardless of `isDisabled`, so there is no opacity or other non-color cue. This file inherits that behavior and adds no additional signal of its own. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this file; row-building and filtering always run the same way.

## Analytics

Not applicable: this file contains no analytics or telemetry call.

## Privacy

- **Data collected**: None of its own. `panels` and `searchQuery` are
  transient, in-memory UI state describing which settings panels exist and
  what the reader has typed to filter them.
- **Storage**: None — `panels` and `searchQuery` live only in memory for the
  lifetime of the view controller; this file writes nothing to
  `UserDefaults`, disk, or any persistent store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: Not applicable — nothing this file holds outlives the view
  controller instance; there is no persistence to retain or expire.

## Logging

Not applicable: this file contains no logging call (no `print`, `os_log`, or
logger reference anywhere in source).

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsPanelListViewController.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only kebab-case and updated every citation; deduped Appearance against the `TopicListViewController` recipe and added it to `depends-on` along with `settings-panel-view-controller`; dropped the `macos` tag; fixed the WinUI 3 and React/Web platform notes; replaced two unobservable test vectors with an observable rebuild-counter seam and strengthened cts-panel-list-010; reformatted Design Decisions to the bold three-line form, corrected a stale `SettingsViewController` citation, and added a decision for `open` subclassing (moved out of Behavioral Requirements/test vectors); fixed the `needs-review` compliance status to `partial` |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
