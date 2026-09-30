<!-- leaf: implement-settings/panel-list-view-controller · source: settings-panel-list-view-controller.md -->

**Rules** (cite as `implement-settings/panel-list-view-controller#<slug>`):

- `panel-storage` MUST
- `panel-set-rebuild` MUST
- `unchanged-query-guard` MUST
- `query-change-rebuild` MUST
- `empty-query-inclusion` MUST
- `all-terms-match` MUST
- `panel-order-preservation` MUST
- `contiguous-section-grouping` MUST
- `descriptor-row-mapping` MUST
- `original-index-row-id` MUST
- `selection-callback-bridge` MUST
- `coder-init-bridge-omission` MUST
- `callback-free-selection` MUST
- `out-of-range-select-guard` MUST
- `panel-visibility-report` MUST
- `visible-index-report` MUST
- `row-id-panel-resolution` MUST

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
  `agentictoolkit://recipes/topic-list-view-controller#appearance/padding`
  for the insets this component renders with.
- **Font**: Not set by this file; inherited unmodified from the same
  `CellMetrics` — see
  `agentictoolkit://recipes/topic-list-view-controller#appearance/font`.
- **Background**: Not set by this file; inherited unmodified —
  `TopicListViewController.applyTheme` paints the view, content stack,
  header, footer, and outline/scroll view background. See
  `agentictoolkit://recipes/topic-list-view-controller#appearance/background`.
- **Foreground/Text**: Not set by this file; inherited unmodified from
  `TopicListViewController.outlineView(viewFor:)`. See
  `agentictoolkit://recipes/topic-list-view-controller#appearance/foreground-text`
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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| panels | `[any ComposableSettingsPanel]` | `[]` | Full, ordered panel list backing the sidebar; set via `setPanels(_:)`. |
| searchQuery | `String` | `""` | Narrows the visible rows to panels whose harvested text matches every space-separated term; empty shows every panel. |
| onSelectPanel | `(((any ComposableSettingsPanel)?) -> Void)?` | `nil` | Invoked with the panel behind the row the user selects, or `nil` when cleared; wired to the ancestor's `onSelect` only inside `init(nibName:bundle:)`. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in this file; `setSections`/`reloadData` (inherited) apply immediately. |
| Increase Contrast | Not applicable: this file sets no custom `NSColor`; all coloring flows through the inherited `TopicListViewController` lookups against the active `SemanticPalette`, unmodified here. |
| Differentiate Without Color | Not supported: a disabled panel's row is distinguished from an enabled one by text/icon color alone (`tertiaryTextColor` vs. `primaryTextColor`/`accentColor`, in `TopicListViewController.outlineView(viewFor:)`); `cell.textField?.alphaValue` is fixed at `1.0` regardless of `isDisabled`, so there is no opacity or other non-color cue. This file inherits that behavior and adds no additional signal of its own. |

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

