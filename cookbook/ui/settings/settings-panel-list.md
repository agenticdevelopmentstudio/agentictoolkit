---
id: a41760b2-4ffd-413b-970f-c0373c9bd3b6
title: Settings Panel List
domain: agentictoolkit://cookbook/ui/settings/settings-panel-list
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The sidebar of a settings split view - maps panels to sectioned rows,
  filters them by search query, and bridges row selection back to the selected
  panel.
platforms:
- swift
- macos
tags:
- settings
- sidebar
- search
- split-view
depends-on:
- agentictoolkit://cookbook/ui/navigation/topic-list
- agentictoolkit://cookbook/ui/settings/settings-panel
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs/settings-view
references:
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
approved-by: ''
approved-date: ''
---

# Settings Panel List

## Overview

The Panel List is the sidebar of a settings split view: a domain-agnostic,
sectioned list component specialized for settings panels. Its ancestor
topic list component is a domain-agnostic sectioned list that knows nothing
about settings; this component maps an ordered array of panels onto that
ancestor's row model and translates the ancestor's generic row-selection
callback back into the specific panel the reader picked.

Beyond what its ancestor already renders and themes, this component owns
three concerns: (1) turning each panel's descriptor into a row, (2)
narrowing the visible rows by a live search query, delegated to a settings
search index, and (3) keeping a row's identity — the panel's index in the
full, unfiltered array — stable across filtering, so a caller (the settings
split view) can select, query the visibility of, and arrow-key through
panels by index no matter what the search field currently hides.

## Behavioral Requirements

- **panel-storage**: Setting the panel list MUST store the given array as
  the component's full, ordered panel list, replacing whatever was stored
  before.
- **panel-set-rebuild**: Setting the panel list MUST rebuild the sidebar's
  sections from the newly stored array before returning.
- **unchanged-query-guard**: Assigning the search query a value equal to
  its current value MUST NOT trigger a section rebuild.
- **query-change-rebuild**: Assigning the search query a value different
  from its current value MUST trigger a section rebuild.
- **empty-query-inclusion**: A search query that is empty, or contains only
  whitespace/newline characters, MUST include every stored panel among the
  visible rows.
- **all-terms-match**: A non-empty, non-whitespace search query MUST
  include a panel only if every one of its space-separated terms is found,
  case-insensitively, as a substring of that panel's searchable text
  (harvested from the descriptor's title, section, search keywords, help
  content's topic titles and bodies, and — once the panel's own view has
  loaded — the visible titles of its own non-editable controls).
- **panel-order-preservation**: Visible rows MUST appear in the same
  relative order as their panels in the array most recently set.
- **contiguous-section-grouping**: Panels MUST be grouped into sidebar
  sections by contiguous run of equal descriptor-section value among the
  panels the current query admits; a panel whose section differs from the
  immediately preceding admitted panel's section MUST start a new section,
  even when an earlier, non-adjacent panel already used that same section
  title.
- **descriptor-row-mapping**: Each row's title, icon, and
  disabled-appearance flag MUST be read from that panel's descriptor
  title, icon, and disabled flag, respectively, at the moment sections are
  rebuilt.
- **original-index-row-id**: Each row's identifier MUST be the string form
  of its panel's zero-based index in the full array most recently set,
  independent of that row's position under the current filter.
- **selection-callback-bridge**: Once constructed through its normal
  construction path, the component MUST invoke its selection callback with
  the panel resolved from the newly selected row's identifier whenever the
  underlying selection changes, and MUST invoke that callback with no panel
  when the selection is cleared.
- **callback-free-selection**: Selecting a panel by index MUST select the
  row identified by the given index without invoking the selection
  callback.
- **out-of-range-select-guard**: Selecting a panel by index MUST have no
  effect when the index falls outside the panel list's bounds.
- **panel-visibility-report**: Querying whether a panel is visible MUST
  return true if, and only if, the panel at the given index is among the
  panels the current search query admits.
- **visible-index-report**: Querying the visible panel indices MUST return
  the original-array indices of the panels the current search query
  admits, in ascending order.
- **row-id-panel-resolution**: Resolving a panel from a row's identifier
  MUST parse that identifier as an integer and MUST yield no panel when
  the identifier is not a valid integer or falls outside the panel list's
  bounds.

## Appearance

- **Corner radius**: Not set by this component. Rows are plain row views
  with no corner radius anywhere in the ancestor topic list component's
  cell factories, and this component overrides none of that layout.
- **Padding**: Not set by this component; inherited unmodified from the
  ancestor's own layout metrics — see
  `agentictoolkit://cookbook/ui/navigation/topic-list#appearance`
  for the insets this component renders with.
- **Font**: Not set by this component; inherited unmodified from the same
  layout metrics — see
  `agentictoolkit://cookbook/ui/navigation/topic-list#appearance`.
- **Background**: Not set by this component; inherited unmodified — the
  ancestor's theme-application step paints the view, content stack,
  header, footer, and list/scroll background. See
  `agentictoolkit://cookbook/ui/navigation/topic-list#appearance`.
- **Foreground/Text**: Not set by this component; inherited unmodified
  from the ancestor's row-rendering step. See
  `agentictoolkit://cookbook/ui/navigation/topic-list#appearance`
  for the exact color/state mapping this component's rows use.
- **Border**: Not set by this component. The ancestor draws a 1pt hairline
  divider above every row in a card except the first, but a plain sidebar
  row (as this component uses) draws no such divider; no border is set
  anywhere in either component.
- **Shadow**: Not applicable — no shadow or layer-shadow property is set
  anywhere in this component or its ancestor.
- **Min/Max size**: Not set by this component. The ancestor computes the
  sidebar's content-driven width from the widest row/title, and this
  component does not override it; there is no maximum width in either
  component.

## States

| State | Appearance change |
|-------|------------------|
| Default | Row shows the panel's title/icon with the primary-text/accent color roles, unselected. |
| Selected | Row highlight comes entirely from the ancestor's native selection rendering; this component restyles nothing further on selection. |
| Disabled (panel) | The descriptor's disabled flag set: text and icon tint switch to the tertiary-text color role (inherited from the ancestor); the row remains selectable — selection is not gated on the disabled flag, so this component (and its ancestor) let a disabled row be clicked and selected like any other. |
| Filtered out | A panel the search query excludes contributes no row at all — it is absent from the sidebar entirely, not shown greyed out or struck through. |
| Pressed | Not applicable: a list row has no separate pressed/hover visual distinct from selection; this component adds no press styling of its own. |
| Focused | Not customized: standard list keyboard-focus ring, unchanged by this component or its ancestor. |
| Loading | Not applicable: setting the panel list and every rebuild it triggers are synchronous; no asynchronous load or spinner exists anywhere in this component. |

## Accessibility

- **Role/trait**: Not customized by this component; inherited unmodified
  from the ancestor, whose item rows use a plain text label (with a custom
  accessible-activation override) and whose section headers are marked as
  group items.
- **Label requirements**: Each row's accessible name comes from the
  descriptor's title, which this component copies directly into the
  ancestor's row-item title; the ancestor then uses that same title,
  slugged, as the row's accessibility identifier. This component sets no
  accessibility label or identifier of its own.
- **Announce state changes (e.g., loading, disabled)**: Selection changes
  are posted through the ancestor's own native accessibility notifications
  (inherited, unmodified); this component issues no accessibility
  announcement of its own for a section rebuild, a search filter change, a
  panel's disabled flag flipping, or a descriptor mutated after the
  sidebar has already been populated (see Edge Cases).
- **Minimum tap target**: Not applicable — this is a pointer/keyboard-
  driven list row (no touch input path in this component or its
  ancestor); the 44×44pt minimum is touch guidance, not a pointer-
  interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| cts-panel-list-001 | panel-storage | Set the panel list to `[panelA, panelB]` | The sidebar shows exactly two rows, for `panelA` and `panelB`, in that order |
| cts-panel-list-002 | panel-set-rebuild | Set the panel list to `[panelA]`, then to `[panelA, panelB]` | The sidebar shows two rows after the second call, without a separate rebuild call being needed |
| cts-panel-list-003 | unchanged-query-guard | Construct a test subclass overriding the section-rebuild step to increment a counter; set the panel list to `[panelA, panelB]`; set the search query to `"x"`; record the counter; set the search query to `"x"` again (identical) | The counter after the second assignment equals the counter recorded after the first — the rebuild step was not called again |
| cts-panel-list-004 | query-change-rebuild | Same counter subclass as cts-panel-list-003; set the panel list to `[panelA, panelB]`; set the search query to `"a"`; record the counter; set the search query to `"b"` | The counter after the second assignment is one greater than after the first — the rebuild step was called again |
| cts-panel-list-005 | empty-query-inclusion | Set the panel list to `[panelA, panelB]`, then set the search query to `"   "` | Both rows remain visible |
| cts-panel-list-006 | all-terms-match | Set the panel list to `[panelA]` where `panelA`'s title is `"General"` and its section is `"App"`, then set the search query to `"app general"` | `panelA`'s row is visible; setting the search query to `"app missing"` then hides it |
| cts-panel-list-007 | panel-order-preservation | Set the panel list to `[panelB, panelA]`, search query `""` | Rows appear in the order `panelB`, `panelA` |
| cts-panel-list-008 | contiguous-section-grouping | Set the panel list to `[p1(section: "A"), p2(section: "B"), p3(section: "A")]` | Three sections render, in order A, B, A — not two sections of A merged |
| cts-panel-list-009 | descriptor-row-mapping | Set the panel list to `[panelA]` where `panelA`'s descriptor has a specific title, icon, and disabled flag set to true | The row shows that title and icon and renders in the disabled appearance |
| cts-panel-list-010 | original-index-row-id | Construct the component normally; set the panel list to `[panelA, panelB]`, search query set to a term matching only `panelB` (hides `panelA`); select the surviving row directly (not via the index-based selection method) | The visible-index query returns `[1]`, and the selection callback is invoked with `panelB` — proving the surviving row's id still resolves to index `1`, not re-indexed to `0` |
| cts-panel-list-011 | selection-callback-bridge | Construct the component normally, set the panel list to `[panelA]`, click `panelA`'s row | The selection callback is invoked once with `panelA` |
| cts-panel-list-012 | callback-free-selection | Set the selection callback to a spy closure, select the panel at index 0 by index | The row at index 0 becomes selected; the spy closure is not called |
| cts-panel-list-013 | out-of-range-select-guard | Set the panel list to `[panelA]`, select the panel at index 5 by index | No row's selection changes; no crash |
| cts-panel-list-014 | panel-visibility-report | Set the panel list to `[panelA, panelB]`, search query set to a term matching only `panelB` | Visibility for index 0 is false, for index 1 is true |
| cts-panel-list-015 | visible-index-report | Set the panel list to `[p0, p1, p2]`, search query set to a term matching only `p0` and `p2` | The visible-index query returns `[0, 2]` |
| cts-panel-list-016 | row-id-panel-resolution | Select a row whose underlying id is `"1"` for a panel list of `[panelA, panelB]` | The selection callback receives `panelB`; simulating a stale/malformed id (e.g. `"not-a-number"` or `"9"`) resolves to no panel |

## Edge Cases

- **Null/empty input**: Setting the panel list to `[]` MUST leave the
  sidebar with no sections and no rows, with no crash. Setting the search
  query to `""` MUST match every panel (see **empty-query-inclusion**).
- **Boundary values**: Index-based selection, visibility querying, and the
  internal row-id resolver MUST behave correctly at the first (`0`) and
  last (`count - 1`) valid indices, and MUST silently no-op (rather than
  trap) for any index outside that range, since each guards against
  out-of-bounds access before acting.
- **Concurrent access**: Not a runtime race condition to defend against —
  the component's state is confined to a single, serialized execution
  context by construction, so simultaneous mutation of the panel list,
  search query, or selection callback from multiple threads is rejected at
  compile time; the source adds no additional locking because none is
  needed.
- **Error states**: Not applicable — setting the panel list, the search
  query, and index-based selection are synchronous, always-succeeding,
  in-memory operations with no fallible dependency (no network, disk, or
  database call) anywhere in this component.
- **Offline/disconnected state**: Not applicable — no networking of any
  kind appears anywhere in this component.
- **Query with repeated whitespace**: A search query containing multiple
  consecutive spaces (e.g. `"a  b"`) MUST narrow the same way a
  single-spaced query does — splitting on whitespace omits empty
  subsequences by default, so extra spacing does not introduce a term that
  trivially matches everything.
- **Panel with a blank title**: A panel whose descriptor title is `""`
  renders a row with an empty label; this component performs no
  validation or fallback text for a blank title.
- **Descriptor mutated after the panel list is set**: A descriptor's
  title, icon, disabled flag, and section fields are all individually
  observable, but this component subscribes to none of them — rows are
  built once, when the panel list or a search-query change triggers a
  rebuild. A panel's descriptor mutated after the sidebar has already been
  populated leaves that row showing stale text/icon/disabled-state until
  some later panel-list or search-query change triggers a rebuild; this
  component does not subscribe to the descriptor's own change
  notifications or otherwise refresh a row automatically.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| panels | array of panels | `[]` | Full, ordered panel list backing the sidebar. |
| searchQuery | string | `""` | Narrows the visible rows to panels whose harvested text matches every space-separated term; empty shows every panel. |
| onSelectPanel | callback taking an optional panel | none | Invoked with the panel behind the row the user selects, or no panel when cleared; wired to the ancestor's own selection callback only through the component's normal construction path. |

## Deep Linking

Not applicable: this component contains no URL scheme, route, or
deep-link handling. Row selection is driven entirely by in-process panel
objects and integer indices, never by a URL.

## Localization

Not applicable to this component: it defines no string literal of its
own. Every row's displayed text (title) is read at runtime from the
caller-supplied panel's descriptor title. Localizing that text is the
responsibility of whichever type constructs each descriptor, outside this
component.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation or transition appears anywhere in this component; a rebuild or reload applies immediately. |
| Increase Contrast | Not applicable: this component sets no custom color; all coloring flows through the inherited theme-lookup mechanism, unmodified here. |
| Differentiate Without Color | Not supported: a disabled panel's row is distinguished from an enabled one by text/icon color alone (tertiary-text vs. primary-text/accent color roles); opacity is fixed regardless of the disabled flag, so there is no opacity or other non-color cue. This component inherits that behavior and adds no additional signal of its own. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component; row-building and filtering always run the same way.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: None of its own. The panel list and search query are
  transient, in-memory UI state describing which settings panels exist and
  what the reader has typed to filter them.
- **Storage**: None — the panel list and search query live only in memory
  for the lifetime of the component; this component writes nothing to any
  persistent store.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this component.
- **Retention**: Not applicable — nothing this component holds outlives
  the component's own instance; there is no persistence to retain or
  expire.

## Logging

Not applicable: this component contains no logging call.

## Platform Notes

- **SwiftUI**: Rebuild as a `List` (or `NavigationSplitView`'s sidebar
  column) whose rows are grouped into `Section`s by the same
  contiguous-run rule as this component's section builder — not a flat
  `Dictionary` `groupBy`, which would silently reorder panels sharing a
  section title that are not adjacent. Drive filtering from a `@State
  private var searchQuery: String` wired to `.searchable(text:)`, matched
  with a port of this component's case-insensitive, all-terms-must-match
  rule. Bind selection with `List(selection: $selectedPanelID)` against a
  stable id equal to the panel's original index (mirroring
  **original-index-row-id**), and surface it to the caller via
  `.onChange(of: selectedPanelID)` rather than a stored closure. A
  disabled row should combine `.foregroundStyle(.tertiary)` with a second,
  non-color cue (see the Differentiate Without Color gap above), such as a
  trailing "Coming Soon" label.
- **Compose**: Use a `LazyColumn` with one `item`/`stickyHeader` block per
  contiguous section run (built the same way, not via Kotlin's `groupBy`,
  for the same reordering reason). Hold `searchQuery` in a
  `mutableStateOf<String>`, feeding a `derivedStateOf` filtered, re-grouped
  list on every keystroke with the same all-terms matcher. Expose an
  `onPanelSelected: (Panel?) -> Unit` lambda fired from each row's
  `onClick`, and a `selectPanel(index: Int)` function that updates a
  `selectedIndex` state directly without invoking that lambda, mirroring
  **callback-free-selection**.
- **React/Web**: Render one `<ul role="listbox">`/`<section>` per
  contiguous run of matching section (computed with a single pass over the
  ordered array, not `Array.reduce` into a keyed map, for the same
  reordering reason), each row a `<li role="option" aria-selected="…">`
  (or, if plain buttons are preferred over a listbox/option structure, a
  `<button aria-current="…">`) showing the descriptor's icon and label. A
  controlled `<input type="search">` drives a `searchQuery` state variable
  that re-filters on every keystroke with the same case-insensitive,
  all-terms rule. Selection fires an `onSelectPanel(panel | null)` prop on
  click/`Enter`/`Space`; a separate `selectPanel(index)` helper updates
  only the highlighted-row state (`aria-selected`/`aria-current`) without
  invoking that prop, mirroring **callback-free-selection**.
- **AppKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsPanelListViewController.swift`,
  declaring `ComposableSettings.PanelListViewController`. A macOS-only,
  `@MainActor`, `open` subclass of `ComposableSettings.TopicListViewController`
  (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift`).
  It composes `ComposableSettings.SettingsSearchIndex`
  (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsSearchIndex.swift`)
  for filtering and reads `any ComposableSettingsPanel`'s `descriptor`
  (`ComposableSettings.SettingsPanelDescriptor`,
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsPanel/SettingsPanelDescriptor.swift`)
  to build each row, rather than reimplementing outline-view layout,
  theming, or row accessibility — all of that stays in the ancestor. The
  selection-callback bridge (**selection-callback-bridge**) is wired only
  inside the designated initializer, `init(nibName:bundle:)`; when the
  class is instead constructed through `init?(coder:)`, that initializer
  calls only `super.init(coder:)` and performs no further setup, so the
  bridge described above is never established on an instance built that
  way. There is no UIKit code path; a UIKit port would need to replace
  `NSOutlineView`'s row/section model with a `UITableView`/
  `UICollectionView` compositional layout, since neither has a direct
  outline-view equivalent for this content-driven, run-based grouping.
- **WinUI 3** (the reason this recipe exists): Build the sidebar as a
  `NavigationView` (`PaneDisplayMode="Left"`) or a `ListView` with
  `CollectionViewSource.IsSourceGrouped="True"`. Do NOT let
  `CollectionViewSource`'s built-in grouping key the whole list by section
  title — per the source's own comment, that "hoisted every unsectioned
  panel to the top of the sidebar, silently reordering a list whose author
  had already put it in the order they meant"; instead, pre-partition the
  flat panel list into contiguous runs in code, exactly as this component's
  section builder does, before handing the grouped `ObservableCollection`
  to the control. Bind each `NavigationViewItem`/`ListViewItem`'s `Content`
  to the panel's title and `Icon` to a `SymbolIcon`/`BitmapIcon`. Keep
  `IsEnabled=true` for a disabled row — mirroring `IsEnabled` to the
  disabled flag would make the row unselectable, contradicting the
  Disabled state (the row stays selectable, styled only) — and instead
  style it with a muted `Foreground`/`SymbolIcon` brush plus, per the
  Differentiate Without Color gap, a non-color cue (a secondary "Coming
  soon" `TextBlock`, not `Opacity` alone, which repeats the same
  color-only gap this recipe flags). Bind an `AutoSuggestBox`/`TextBox` to
  a `searchQuery` property on the view model, re-filtering and re-grouping
  the `ObservableCollection` on every `TextChanged` with the same
  case-insensitive, all-terms-must-match rule. Raise the
  `onSelectPanel`-equivalent event from `SelectionChanged`/`ItemInvoked`,
  and implement a `SelectPanel(int index)` method that assigns
  `SelectedItem` under a reentrancy guard, since assigning `SelectedItem`
  directly would otherwise re-fire `SelectionChanged` and violate
  **callback-free-selection**.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SettingsPanelListViewController.swift` |

## Design Decisions

- **Decision**: Identify each row by the panel's original index in the
  full, unfiltered array, rather than by its position in the currently
  filtered list.
  **Rationale**: Per the source's own doc comment, "the position is the
  row's identity, so a filtered row still selects the panel it names" — a
  stable id under filtering is what lets index-based selection, visibility
  querying, and the hosting split view's arrow-key stepping keep working
  correctly while a search query is active.
  **Approved**: pending
- **Decision**: Group panels into sections by contiguous run of matching
  section value, rather than by collecting every panel that shares a
  section title regardless of position.
  **Rationale**: Per the source's own comment, "Sections come out in the
  order the panels arrive, and a run of panels sharing one section title
  is one section. Grouping by title across the whole list instead hoisted
  every unsectioned panel to the top of the sidebar, silently reordering a
  list whose author had already put it in the order they meant."
  **Approved**: pending
- **Decision**: Filter the sidebar in place (hiding non-matching rows)
  instead of replacing it with a separate search-results list.
  **Rationale**: Per the source's own doc comment, "Filtering the sidebar
  (rather than replacing it with a results list) is what keeps a search
  reversible: the row the user is reading stays where it was in the list,
  and deleting the query puts its neighbours back around it."
  **Approved**: pending
- **Decision**: Expose a visibility query as a separate operation rather
  than having index-based selection silently clear the search query
  whenever the target row is currently filtered out.
  **Rationale**: Per the source's own doc comment, "clearing the search on
  the caller's behalf when it was not needed throws away a filter the user
  is still reading by" — the caller (the settings split view) is expected
  to check visibility first and decide for itself whether to clear the
  query.
  **Approved**: pending
- **Decision**: Selecting a panel by index never invokes the selection
  callback.
  **Rationale**: Per the source's own doc comment, "programmatic selection
  flows through the hosting split view's own selection method" (the
  comment predates a rename and still names an older type, but the
  hosting split view is the only caller in source that drives index-based
  selection), so the callback exists only to report a user-driven row
  pick, not to echo back a selection the caller itself just made.
  **Approved**: pending
- **Decision**: Declare the component `open`, letting a host app subclass
  it to customize row presentation or add secondary actions, rather than
  sealing it or exposing customization through composition only. (AppKit.)
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/. |
