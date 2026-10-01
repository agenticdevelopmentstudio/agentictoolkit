---
id: ce223be3-818a-4310-b136-9e1e84e9af54
title: Topic List
domain: agentictoolkit://cookbook/ui/navigation/topic-list
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Domain-agnostic sidebar list: sectioned rows, single selection, optional
  title/footer/header-accessory, theme-driven repaint, and an accessibility-reachable
  row label'
platforms:
- swift
- macos
tags:
- sidebar
- list
- selection
- view-controller
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/settings-panel-list
references:
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
approved-by: ''
approved-date: ''
---

# Topic List

## Overview

This is a reusable, domain-agnostic component that renders a sectioned,
single-selection sidebar list. It is "a reusable list with optional
section headers, icon-friendly rows, and closure-based selection," and it
knows nothing about settings, the host app, or any specific data domain. A
caller supplies rows through a flat-list setter (no section headers) or a
grouped setter (sections, each optionally titled) and observes the user's
selection through a selection callback. One concrete consumer subclasses
this component to back the sidebar of a split view (see `related`).

Beyond the list itself, the component owns an optional title header (shown
above the list, with an optional client accessory view such as a search
field beneath the title) and an optional client footer view pinned below
the list - both collapse to zero height when unset. The whole view
repaints itself on every theme change.

Two distinct "header" concepts are kept separate throughout this recipe:
the component's own title header (the custom title + accessory area above
the list) and the list's own built-in column header row, which this
component always disables. A section's optional title renders as a
**group header row** inside the list itself - a third, unrelated use of
"header."

## Behavioral Requirements

- **group-items-by-section**: Component MUST render every section's items,
  in the order sections and items are given to the grouped setter, as leaf
  rows of a single flat list.
- **header-row-for-titled-section**: Component MUST render a group header
  row carrying the section's title for every section whose title is a
  non-empty string.
- **omit-header-for-untitled-section**: Component MUST NOT render a group
  header row for a section whose title is empty or unset - only a
  non-empty title produces a header node.
- **flat-row-hierarchy**: Component MUST report every row - header and
  item alike - as not expandable and MUST use no per-level indentation, so
  no row is ever indented or nested under another.
- **hide-disclosure-controls**: Component MUST hide each row's disclosure
  control.
- **hide-outline-column-header**: Component MUST disable the list's
  built-in column header bar, so it is never drawn above the rows.
- **header-rows-not-selectable**: Component MUST prevent a group header
  row from becoming selected; only an item row can be selected.
- **disabled-item-selectability**: Component MUST allow selecting an item
  marked disabled through exactly the same paths, and with exactly the
  same result, as an item that is not disabled - both the
  selection-gating check and an item row's accessibility press handler
  branch only on whether a row is a header or an item, never on whether
  the item is disabled.
- **mute-disabled-item-appearance**: Component MUST render an item marked
  disabled using the tertiary text color for both its label text and its
  icon tint, instead of the primary text color (label) and the accent
  color (icon tint) used for an enabled item.
- **render-item-without-icon-when-nil**: Component MUST render an item row
  whose icon is unset with no image in its image view.
- **user-selection-callback**: Component MUST invoke the selection
  callback with the newly selected item, or none if there is no selection,
  whenever the list's selection changes as a direct result of user
  interaction (i.e. outside any selection-suppression scope - see
  **suppress-onselect-on-programmatic-selection**).
- **suppress-onselect-on-programmatic-selection**: Component MUST NOT
  invoke the selection callback for a selection change made during a
  programmatic-selection scope - i.e. the reload-and-restore performed by
  the grouped setter and by a theme change, and the selection made by
  selecting an item by id.
- **select-item-by-id**: Selecting an item by id MUST select the row of
  the first item, in section/item order, whose id matches the given id,
  without firing the selection callback.
- **missing-id-selection**: Selecting an item by id MUST leave the current
  selection unchanged when no item's id matches the given id.
- **noop-select-already-selected-id**: Selecting an item by id MUST leave
  the current selection unchanged, and MUST NOT re-issue a selection
  command, when the matching row is already the selected row.
- **restore-selection-by-id-after-resection**: The grouped setter MUST
  re-select, by id, whichever item was selected immediately before the
  call, if an item with that id is still present in the new sections.
- **restore-selection-across-theme-change**: A theme change MUST preserve
  the list's selected row indexes across the reload it performs,
  re-selecting them when they differ afterward.
- **stable-row-node-identity**: Component MUST let the list resolve a
  given logical row to the same valid row across repeated accesses between
  one grouped-setter call and the next, rather than losing that identity
  (and failing to resolve) because a fresh row representation was
  constructed for that row on each access.
- **hide-header-when-title-and-accessory-empty**: Component MUST hide the
  title header view when the trimmed title is empty AND no header
  accessory view is set.
- **hide-footer-when-unset**: Component MUST hide the footer container
  when no footer view is set.
- **header-accessory-below-title**: When a header accessory view is set,
  component MUST lay it out directly below the title label, spanning the
  full width of the header area.
- **footer-spans-sidebar-width**: A footer view installed via the footer
  setter MUST have its leading, trailing, top, and bottom edges pinned to
  its container's, spanning the sidebar's full width.
- **content-below-titlebar-safe-area**: Component MUST keep its list
  content below the window's non-safe top inset (e.g. a full-height
  window's titlebar) by pinning its content's top edge to the root view's
  safe-area boundary rather than its plain top edge, while its
  leading/trailing/bottom edges match the root view's own edges.
- **preferred-width**: Computing the preferred width MUST return exactly
  the widest text-based candidate (the title's rendered width plus its own
  leading inset; each section header's rendered width plus its own
  leading inset; each item's rendered width plus its own chrome width;
  defaulting to 0 when there is no title, header, or item), plus a fixed
  chrome padding of 64pt (30 leading inset + 16 scroller gutter + 18
  trailing margin) - then MUST widen that further to at least the footer
  view's own fitting width (when a footer is set) and to at least the
  header accessory view's own fitting width plus the title's leading
  inset and the header's trailing inset (when an accessory is set). The
  footer and accessory floors are absolute widths, not added to the fixed
  chrome padding.
- **item-accessibility-id-from-title**: Component MUST set each item row's
  label accessibility identifier to a value derived from the item's
  **title** (slugified, and prefixed to namespace it to this component),
  not its id.
- **accessibility-press-selection**: An item row's label MUST respond to
  an accessibility press action by locating its row in the enclosing list
  and selecting it, and MUST first run the selection-gating check for that
  row and return failure without selecting when that check fails.
- **repaint-on-theme-change**: Component MUST update the background color
  of the root view, content stack, header view, and footer container, the
  title label's font and text color, and the scroll/list view background,
  to the newly observed theme palette's values every time a theme change
  is reported.
- **single-column-fills-width**: The list's one column MUST be resized to
  fill the list's available width on every layout pass, so no row ever
  clips its label regardless of when the enclosing view settles the
  sidebar's width.
- **overlay-autohide-scroller**: Component MUST configure the scroll view
  so its vertical scroller floats over content, appearing only while
  scrolling and while the list overflows, and hides itself otherwise.
- **automatic-outline-style**: Component MUST render the list with a
  theme-following material rather than a forced, fixed-appearance
  material, regardless of the active system appearance.

## Appearance

- **Corner radius**: 4pt on the selection-highlight rounded rect drawn
  behind a selected row. No other corner radius appears in this
  component.
- **Padding**: Title header: 10pt top / 6pt bottom inset from the header
  area's edges to its content; 14pt leading and 14pt trailing inset from
  the header area's edges to its content; 8pt vertical gap between the
  title label and the accessory container. Item cell: 4pt leading inset
  from the cell to the icon; 6pt gap between icon and label; 4pt trailing
  inset from the label to the cell's trailing edge. Header (group) cell:
  2pt leading inset, vertically centered.
- **Font**: Item labels use the theme's body font; group header labels use
  the theme's caption font; the title label uses the theme's button font.
  All three read the live theme palette rather than a fixed point size,
  and are reapplied on every cell reuse rather than baked in once at cell
  creation.
- **Background**: The root view, content stack, header view, and footer
  container are all painted with the theme's window-background color; the
  scroll and list backgrounds are set to the same value.
- **Foreground/Text**: Item label: the primary text color when enabled,
  the tertiary text color when disabled. Item icon tint: the accent color
  when enabled, the tertiary text color when disabled. Group header
  label: the secondary text color. Title label: the secondary text color.
- **Border**: Not set explicitly anywhere in this component; the scroll
  view's border keeps its platform default, no border - no border is
  drawn around the scroll view.
- **Shadow**: Not applicable - no shadow is drawn, and no shadow property
  is configured, anywhere in this component.
- **Min/Max size**: No explicit min/max width or height constraint is
  applied to the component's own view; the preferred-width computation
  instead computes a content-driven width for a caller (e.g. an enclosing
  split view) to size the sidebar to, rather than the sidebar enforcing
  its own bounds. The item icon has a fixed 16x16pt size.

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected, enabled item row) | Item font, primary text color label, accent-color-tinted icon; row background follows the window-background color. |
| Disabled item row | Item font, tertiary text color label, tertiary-text-color-tinted icon; identical selection/press behavior to an enabled row (see **disabled-item-selectability**). |
| Selected row | A 4pt-corner-radius rect, inset 2pt horizontally / 1pt vertically, filled with the theme's selection color, drawn behind the row. |
| Group header row | Header font, secondary text color, marked as a group row; not selectable; no disclosure control. |
| Pressed | Not applicable: this component defines no visual state distinct from Selected for a row's press - a click or an accessibility press both resolve directly to the same selection action, with no separate transient "pressed" appearance. |
| Focused | Not applicable beyond the platform's own default keyboard-focus-ring behavior on the list; source sets no custom focus-ring color, width, or override. |
| Loading | Not applicable: the flat and grouped setters apply their row model synchronously; source defines no async load and no loading/pending indicator. |

## Accessibility

- **Role/trait**: Not explicitly set via a custom accessibility role
  anywhere in this component; the list, its rows, and its cells use the
  platform's default roles, with group header rows marked as group rows.
- **Label requirements**: Each item row's label carries an explicit
  accessibility identifier (a slugified form of the item's title,
  prefixed for this component - see **item-accessibility-id-from-title**),
  and its accessible name is its own displayed text (the item's title) -
  no separate accessibility-label override is set. Group header, title,
  and footer/accessory views carry no accessibility identifier in this
  component.
- **Announce state changes**: Not implemented. When the grouped setter
  reloads the list with a different row count, no accessibility change
  notification informs assistive technology that the visible row set
  changed; a screen-reader user hears nothing until navigating back into
  the list.
- **Minimum tap target**: The list uses its platform's default row-sizing
  style rather than a custom row height, so the row's actual height is
  derived from that default style rather than a literal value this
  component sets. Whatever value that resolves to for the fonts this
  component uses is well under the 44x44pt iOS minimum. This is expected
  for a pointer/keyboard-driven desktop list (not a touch surface); the
  44x44pt (iOS) / 48x48dp (Android) minimum applies to the touch-platform
  translations described in Platform Notes, not to this desktop control.
  Additionally, an item row label's accessibility press handler gives
  assistive technology a press path into a row regardless of its rendered
  size, since activation does not depend on a pointer hitting a physical
  target.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| topic-list-001 | group-items-by-section | Populating the list with two sections, each holding two items, in a given order | The list's rows, top to bottom, are exactly those items in the given section/item order |
| topic-list-002 | header-row-for-titled-section | A section titled "Recents" with one item | A group header row reading "Recents" appears above that item's row |
| topic-list-003 | omit-header-for-untitled-section | A section with no title and two items | No group header row appears; only the two item rows are shown |
| topic-list-004 | flat-row-hierarchy, hide-disclosure-controls | Any populated list | Every node is reported as not expandable, and no row shows a disclosure control |
| topic-list-005 | hide-outline-column-header | Inspect the list after it loads | The list's built-in column header bar is disabled and never drawn |
| topic-list-006 | header-rows-not-selectable | Click, or send an accessibility press action to, a group header row | The selection-gating check fails; the row does not become selected |
| topic-list-007 | disabled-item-selectability | An item marked disabled; select it by click | The row becomes selected and the selection callback is invoked with that item, identically to an enabled item |
| topic-list-008 | mute-disabled-item-appearance | Two items, one marked disabled, one not | The disabled row's label/icon use the tertiary text color; the enabled row's use the primary text color/accent color |
| topic-list-009 | render-item-without-icon-when-nil | An item constructed with no icon | Its row's image view holds no image; no placeholder or broken image appears |
| topic-list-010 | user-selection-callback | User clicks an unselected item row | The selection callback is invoked exactly once with that item |
| topic-list-011 | suppress-onselect-on-programmatic-selection | Select an item by id for an unselected, present id | The row becomes selected but the selection callback is NOT invoked |
| topic-list-012 | select-item-by-id, missing-id-selection | Two items with ids "a" and "b"; select by id "b", then select by id "z" | The first call selects "b"'s row; the second call leaves "b" selected (no change, no crash) |
| topic-list-013 | noop-select-already-selected-id | The row for id "b" is already selected; select by id "b" again | No selection command is re-issued; selection and the selection callback are unaffected |
| topic-list-014 | restore-selection-by-id-after-resection | Item "b" selected; call the grouped setter with a new section list that still contains an item with id "b" | After reload, the row for id "b" is selected again, with no selection callback firing for the transient deselection |
| topic-list-015 | restore-selection-across-theme-change | A row is selected; the active theme changes | After the theme change is applied, the same row is still selected, with no spurious empty-selection callback |
| topic-list-016 | stable-row-node-identity | Call the grouped setter once, then select by id an item present since that call | The list resolves a valid row for that item |
| topic-list-017 | hide-header-when-title-and-accessory-empty | Set the title to none and no header accessory view set | The header view is hidden |
| topic-list-018 | hide-footer-when-unset | Set the footer view to none | The footer container is hidden |
| topic-list-019 | header-accessory-below-title | Set the title to "Panels" and set a header accessory view (e.g. a search field) | The header shows the title label above the accessory view, both spanning the header's width |
| topic-list-020 | footer-spans-sidebar-width | Set a footer view (e.g. an actions bar) | The footer view's leading/trailing edges equal the footer container's; it visually spans the sidebar |
| topic-list-021 | content-below-titlebar-safe-area | Host the component's view in a window whose content extends under the titlebar | The content's top sits at the safe-area inset, not the raw top of the view, so the titlebar does not overlap the list |
| topic-list-022 | preferred-width | One item titled "A very long item title" and no title/footer/accessory | Computing the preferred width returns exactly the item's chrome width plus the rendered width of "A very long item title" in the item font, plus the fixed chrome padding (64pt) |
| topic-list-023 | item-accessibility-id-from-title | An item with id "row-7", title "Appearance" | The row label's accessibility identifier is derived from "appearance" (its slugified title), not from "row-7" |
| topic-list-024 | accessibility-press-selection | Send an accessibility press action to an item row's label | The press selects the row and reports success |
| topic-list-024b | accessibility-press-selection | Install a selection-gating override that fails; send an accessibility press action to an item row's label | The press reports failure; the row does not become selected |
| topic-list-025 | repaint-on-theme-change | Active theme changes from light to dark | Root view, content stack, header view, footer container backgrounds, title label font/color, and list/scroll backgrounds all update to the new palette's values |
| topic-list-026 | single-column-fills-width | Enclosing split view widens the sidebar by 40pt | The list's single column widens by the same amount on the next layout pass; no row clips its label |
| topic-list-027 | overlay-autohide-scroller | Inspect the scroll view after it loads | The vertical scroller floats over content and auto-hides when not scrolling |
| topic-list-028 | automatic-outline-style | Inspect the list's rendering style after it loads | The list renders with the theme-following material, not the forced dark material |

## Edge Cases

- Null/empty input (MUST): An empty grouped setter call yields an empty
  row cache; the list shows zero rows and the selected-item query returns
  none. An item's icon and a section's title are both optional and handled
  per **render-item-without-icon-when-nil** and
  **omit-header-for-untitled-section**; an item's id/title are
  non-optional, so the type system rules out a missing value for them.
- Boundary values (MUST): With no sections, no title, no footer, and no
  header accessory, computing the preferred width returns exactly the
  fixed chrome padding (64pt) - the minimum value this computation can
  produce. Source imposes no maximum on section or item count; any array
  size is handled uniformly through the same row model.
- Duplicate item ids (SHOULD): Selecting by id resolves via a first-match
  lookup; if two items across sections share an id, only the row for the
  first match in list order is ever selected by this operation - source
  performs no uniqueness validation. Callers SHOULD supply unique ids
  across all sections passed to one grouped-setter call; this is
  undocumented in source and left to caller discipline. This SHOULD needs
  no separate test vector: the behavior described here is a direct,
  deterministic consequence of the same first-match lookup
  **select-item-by-id**'s vector (topic-list-012) already exercises, and
  a second, near-identical vector for the duplicate-id case would not
  exercise any additional code path.
- Concurrent access: Not applicable - the component confines all reads
  and writes of its section list, row cache, and selection-suppression
  counter to a single execution context (see Platform Notes for the exact
  confinement mechanism); source provides no path for two threads to
  mutate this component's state simultaneously.
- Error states: Not applicable - this component contains no throwing
  function, no result type, and no network or file-system call; the
  flat/grouped setters and selecting an item by id are synchronous,
  non-failing operations with no failure mode to represent beyond the
  silent no-ops already described above (missing id, already-selected
  id).
- Offline/disconnected: Not applicable - the component performs no
  networking anywhere in source; it only renders caller-supplied
  in-memory data.
- Header row reached via selected-item query (MUST): The selected-item
  query's guard returns none defensively if the current selection were
  ever a group header row; in practice this cannot occur because the
  selection-gating check already refuses to select header rows, but the
  accessor does not rely on that invariant holding elsewhere in the
  delegate chain.
- Nested selection-suppression scopes (MUST): The selection-suppression
  counter is an integer nesting counter, not a boolean, specifically so
  that a suppression scope nested inside another still leaves suppression
  active until the outer scope also exits; no call site in this component
  nests scopes today, but the suppression mechanism supports it without
  change if a future call site does.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Sections (set via the grouped or flat setter) | A list of sections (each with an optional title and items) | Empty | Full sectioned row model; the grouped setter groups rows with headers per non-empty section title, the flat setter wraps items in one untitled section. |
| Selection callback | A callback receiving the newly selected item, or none | none | Invoked with the newly selected item, or none, on a user-driven selection change; never invoked for a programmatic change made through selecting by id or a theme-triggered reload. |
| Title | An optional string | none | Text shown in the optional header above the list, set via the title setter; empty or unset hides the header unless a header accessory view is set. |
| Footer view | An optional view | none | Client view pinned below the list via the footer setter, spanning the sidebar width; unset collapses the footer to zero height. |
| Header accessory view | An optional view | none | Client view shown directly beneath the title and above the list via the accessory setter, spanning the header's width; unset collapses to nothing. |

## Deep Linking

Not applicable: this is a reusable, embeddable sidebar component with no
URL scheme, route, or deep-link handler anywhere in source; a host decides
how and where to present it.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | — | This component defines no user-facing string literal of its own. |

Not applicable beyond the row above: every displayed string - item titles,
section titles, and the list's own title - comes from caller-supplied
data, not from a string table owned by this component. The only string
literals in this component are internal identifiers used for the list's
own bookkeeping and accessibility, never shown on screen.

## Accessibility Options

- **Reduce Motion**: Not applicable - source defines no animation or
  transition anywhere in this component; every state change (selection,
  resection, theme repaint) is an instantaneous property assignment or a
  synchronous reload.
- **Increase Contrast**: Not applicable to this component specifically -
  it never assigns a raw color literal; every color it uses is read from
  the active theme palette. Whether the active palette itself adjusts
  under Increase Contrast is that theme system's responsibility, not
  something this component decides or can override.
- **Differentiate Without Color**: Not implemented. A disabled item is
  distinguished from an enabled one only by color - the tertiary text
  color versus the primary text color/accent color (see
  **mute-disabled-item-appearance**) - with no accompanying non-color
  cue: no icon change, no strikethrough, and no opacity reduction, since
  full opacity is explicitly set for every row.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere
in this component; the sidebar always renders whatever it is given.

## Analytics

Not applicable: this component contains no analytics or telemetry call.
The selection callback is the only observable callback, and it is
entirely consumer-supplied - this component neither logs nor reports on
its own selection changes.

## Privacy

- **Data collected**: None by the component itself - it only renders
  caller-supplied item/section values for display.
- **Storage**: In-memory only, for the component's lifetime; nothing is
  written to disk, a settings store, or any other store by this
  component.
- **Transmission**: Not applicable - no networking call appears anywhere
  in source.
- **Retention**: None beyond the component's lifetime; state is discarded
  when the component is deallocated.

## Logging

Not applicable: source contains no logging call anywhere in this
component.

## Platform Notes

- **SwiftUI**: Use a `List(selection: $selectedID)` built from the same
  `TopicListSection`/`TopicListItem` model, with `Section(header: Text(title))`
  wherever a section's title is non-nil (mirroring
  **header-row-for-titled-section** / **omit-header-for-untitled-section**),
  and a plain, unsectioned `ForEach` when it is nil. Render a disabled row's
  label and `Label` icon with `.foregroundStyle(.tertiary)` while still
  leaving the row tappable/selectable (mirroring
  **disabled-item-selectability** - do not use SwiftUI's `.disabled()`
  modifier, since that would also block selection, unlike the source
  behavior). Compose the optional title/accessory/footer as sibling views
  above and below the `List` in a `VStack`, collapsing each with
  `if let` rather than SwiftUI's `.hidden()` (which still reserves layout
  space), mirroring the zero-height collapse behavior of `isHidden` on a
  `NSStackView` arranged subview. Read the row's rendered text width with
  `(text as NSString).size(withAttributes:)` if a content-driven sidebar
  width equivalent to **preferred-width** is needed.
- **Compose**: Build the outline as a `LazyColumn` with `stickyHeader` items
  for each section whose title is non-nil, and plain items otherwise. Style
  a disabled item's `Text`/`Icon` with `MaterialTheme.colorScheme.onSurfaceVariant`
  (or `LocalContentColor.current.copy(alpha = …)`) while leaving its
  `Modifier.clickable` active, mirroring **disabled-item-selectability**
  (Compose's built-in `enabled = false` on `clickable` would, like SwiftUI's
  `.disabled()`, block the click entirely - do not use it here; `contentColorFor`
  is also the wrong tool, since it returns the content color paired with a
  given background, not a muted tone). Wrap the whole sidebar
  column in a `Surface` whose `color` is read from the active
  `MaterialTheme.colorScheme` so it repaints on theme change, mirroring
  **repaint-on-theme-change**. Compose an optional title/accessory header
  and footer as sibling composables that emit nothing (`if (condition) { … }`)
  when unset, rather than an `AnimatedVisibility` that would animate a
  collapse this component never animates.
- **React/Web**: Render the sidebar as a `<nav>` containing a single
  `<ul role="listbox">` for the whole list, mirroring **flat-row-hierarchy**'s
  single-outline model - never one `listbox` per section, which would split
  keyboard navigation and single selection across sections. Wrap each titled
  section's rows in an `<li role="group" aria-labelledby="section-id">`
  containing an `<h3 id="section-id">` for the title followed by that
  section's `<li role="option" aria-selected>` rows; an untitled section's
  rows sit directly in the listbox with no wrapping `group`. Style a disabled item with a muted text/icon color
  class while still attaching its `onClick`/keyboard handlers, mirroring
  **disabled-item-selectability** (do not set the native `disabled`
  attribute, which - like SwiftUI's `.disabled()` - would remove it from the
  tab order and block activation). Give each item's element an `id` or
  `data-testid` derived from a slugified title, mirroring
  **item-accessibility-id-from-title**, and drive CSS custom properties
  (`--surface-bg`, `--text-primary`, etc.) from the active theme so a theme
  switch repaints them, mirroring **repaint-on-theme-change**. Collapse an
  unset header/footer with `display: none` (which removes layout space, like
  AppKit's `isHidden` on a stack view's arranged subview) rather than
  `visibility: hidden`.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift`
  as a `@MainActor`, `open` `NSViewController` that builds its entire view
  hierarchy by hand in `loadView()` - a single-column `NSOutlineView`
  (`ColumnFillingOutlineView`) inside an `NSScrollView`, stacked with an
  optional title/accessory header and an optional client footer in a
  vertical `NSStackView`. It is its own `NSOutlineViewDataSource`/
  `NSOutlineViewDelegate`, with row appearance and theming driven by
  `SemanticPalette` via `ThemePaletteObserver` and `ThemedTableRowView`
  (both defined in the vendored `AgenticDeveloperToolkitUI` framework this
  target re-exports). There is no UIKit code path in source; a UIKit port
  would replace `NSOutlineView`/`NSScrollView` with a `UITableView` (a flat
  list needs no `UICollectionView` compositional layout), use
  `tableView(_:titleForHeaderInSection:)` for group headers, and would need
  to grow the AppKit `.default` row height - well under 44pt - to at least a
  44pt touch target, since UIKit has no keyboard-first,
  `NSOutlineView`-style default row navigation to fall back on for
  pointer-free selection.
- **WinUI 3**: Build the sidebar as a
  `NavigationView` in `Left`/`LeftCompact` display mode, or - if
  `NavigationView`'s chrome (back button, pane toggle) is unwanted - a plain
  `ListView` bound to a flattened collection of `TopicListSection`/
  `TopicListItem` view models, grouped with `CollectionViewSource.IsSourceGrouped
  = true` and a `GroupStyle` whose `HeaderTemplate` renders the section
  title only when it is non-empty (mirroring
  **header-row-for-titled-section**/**omit-header-for-untitled-section** -
  WinUI's `CollectionViewSource` grouping is the direct analog of
  `buildRootNodes(from:)`'s header/item interleaving). Bind each
  `ListViewItem`'s `IsEnabled` to nothing (leave it `true`) and instead bind
  its `Foreground`/icon `Fill` to a converter that returns a muted
  `SolidColorBrush` when the item's `IsDisabled` is set, mirroring
  **disabled-item-selectability** - WinUI's `IsEnabled = false`
  would, like SwiftUI's `.disabled()` and Compose's `enabled = false`,
  also block selection, which source does not do. Use
  `ListView.SelectionMode="Single"` with `SelectedItem`/`SelectionChanged`
  as the analog of the selection callback, and select an item by identity
  (`ListView.SelectedItem = viewModels.First(vm => vm.Id == id)`) as the
  analog of **select-item-by-id**, no-oping when no match is found
  (mirroring **missing-id-selection**). Give the optional title a
  `TextBlock` and the optional accessory/footer `ContentPresenter`s bound to
  nullable view-model properties, collapsing each to `Visibility.Collapsed`
  (which, like AppKit's `isHidden` on a stack panel child, removes it from
  layout - not `Opacity="0"`) when unset, mirroring
  **hide-header-when-title-and-accessory-empty**/**hide-footer-when-unset**.
  Re-theme the `NavigationView`/`ListView`'s brushes from
  `Application.Current.Resources` `ThemeResource`s (or re-apply them in an
  `ActualThemeChanged` handler) so a theme switch repaints the sidebar,
  mirroring **repaint-on-theme-change**. Set `AutomationProperties.AutomationId`
  on each `ListViewItem` to the slugified title (mirroring
  **item-accessibility-id-from-title**) while `AutomationProperties.Name`
  carries the plain title as the item's accessible name, since WinUI's UI
  Automation tree, like AppKit's, exposes the item's own element rather than
  a synthesized row wrapper as the natural place to attach an identifier and
  a name.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift` |

## Design Decisions

- Decision (AppKit): Cache `TopicListNode` instances in `rootNodesCache`
  across accesses, rebuilding them only inside `setSections(_:)`, instead
  of recomputing `rootNodes` fresh on every access.
  Rationale: Per the property's doc comment, `NSOutlineView` identifies
  items by reference; rebuilding on every access (the prior behavior) made
  `outlineView.row(forItem:)` always return -1, which silently broke
  `selectItem(withId:)`.
  Approved: pending
- Decision: Let `shouldSelectItem` and `TopicListItemLabel.accessibilityPerformPress()`
  gate selection only on node kind (`.item` vs. `.header`), never on
  `TopicListItem.isDisabled`.
  Rationale: Source draws no such distinction - a "coming soon" placeholder
  item stays reachable and selectable by mouse, keyboard, and assistive
  technology alike; only its rendered appearance is muted. A consumer that
  wants a disabled item to be truly inert must check `isDisabled` itself
  inside its `onSelect` handler.
  Approved: pending
- Decision (AppKit): Track suppression of `onSelect` with an integer
  nesting counter (`selectionSuppressionDepth`), not a boolean flag.
  Rationale: Per the property's doc comment, a single suppression scope must
  absorb both the notification `reloadData()` posts when it drops the
  selection and the one the following re-selection posts - AppKit delivers
  both synchronously within the scope - so the counter, not a one-shot
  flag, is what keeps a single scope correct.
  Approved: pending
- Decision (AppKit): Override `layout()` on `ColumnFillingOutlineView` to
  call `sizeLastColumnToFit()` after `super.layout()`, rather than setting
  the column's `width` directly.
  Rationale: Per the class's doc comment, setting `column.width` directly
  from `layout()` re-enters `NSTableView.tile`/`setFrameSize` and throws;
  `sizeLastColumnToFit()` after `super.layout()` is the safe primitive.
  Approved: pending
- Decision (AppKit): Set `outlineView.style = .automatic` rather than the
  more visually apt `.sourceList`.
  Rationale: Per the source comment, `.sourceList` forces an internal
  `NSVisualEffectView` dark material regardless of `NSApp.appearance`;
  `.automatic` lets the outline's background follow this component's own
  theme instead.
  Approved: pending
- Decision (AppKit): Pin `contentStack`'s top anchor to the root view's
  `safeAreaLayoutGuide.topAnchor` instead of its plain `topAnchor`.
  Rationale: Per the source comment, in a window whose content runs the
  full height (so the sidebar's fill reaches up behind the window buttons)
  the titlebar overlaps this view, and the list must begin below it;
  everywhere else that inset is zero and nothing moves.
  Approved: pending
- Decision (AppKit): Put the accessibility identifier and `AXPress`
  handling on the item's `NSTextField` label (`TopicListItemLabel`), not
  on `NSTableCellView` or `NSTableRowView`.
  Rationale: Per the source comment, AppKit synthesizes a table's `AXRow`
  and `AXCell` elements itself; an identifier or action attached to
  `NSTableRowView`/`NSTableCellView` never reaches the accessibility tree,
  so the label is the row's one real element in it.
  Approved: pending
- Decision: Derive an item row's accessibility identifier from its `title`
  (slugified), not from its `id`.
  Rationale: Per the source comment, `id` is the caller's private key - in
  the settings window it is a panel's index in an array - so it names
  whichever row a given index currently holds and renames itself whenever a
  row is inserted above it. The title is what the row is called on screen,
  which is what someone driving the list actually knows about it.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | passed | Internationalization |

Keyboard-navigable passes because `NSOutlineView`'s default arrow-key row
navigation is never disabled or overridden, and `shouldSelectItem` gates
keyboard-driven selection the same way it gates a click; every item row's
accessible name is also its own title text, with a stable, title-derived
accessibility identifier alongside it. Screen-reader-support is partial:
labels and an `AXPress` path exist, but no announcement is posted when
`setSections(_:)` changes the visible row set, and a disabled item is
distinguished from an enabled one by color alone with no secondary cue (see
**Announce state changes** under Accessibility and **Differentiate Without
Color** under Accessibility Options).
Dynamic-type-support is partial because `CellMetrics.itemFont`/`headerFont`/
`titleFont` all read live palette fonts (`palette.font(.body)` etc.) rather
than a fixed point size, but this file cannot confirm whether
`SemanticPalette.font(_:)` itself scales with the system's text-size
setting. Contrast-ratio is partial because every color comes from
`SemanticPalette` tokens whose actual contrast values are not stated in this
file's source. Platform-theming passes because the root view, `contentStack`,
`headerView`, `footerContainer`, title label, and outline/scroll backgrounds
all repaint from `SemanticPalette` on every `ThemePaletteObserver` change
(see **repaint-on-theme-change**). String-externalization passes because
this file defines no user-facing string literal of its own - every
displayed string is caller-supplied data. `touch-target-size` is not listed:
AppKit's `.default` row-size style yields a row height well under 44×44pt,
but that check governs touch surfaces and this is a pointer/keyboard-driven
macOS list - not a defect, and not an applicable check for this control (the
44×44pt/48×48dp threshold does apply to the touch-platform translations
described in Platform Notes).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: rewrote requirements and test vectors to remove private AppKit identifiers (`rootNodesCache`, `TopicListNode`, `buildRootNodes(from:)`, `sizeLastColumnToFit()`, `ColumnFillingOutlineView`) in favor of observable behavior, keeping the mechanism under Platform Notes/Design Decisions; renamed five action-phrased requirements to subject-only names (`disabled-item-selectability`, `ax-press-selection`, `preferred-width`, `missing-id-selection`, `user-selection-callback`) and updated every citation; gave the Border and Minimum-tap-target Appearance/Accessibility entries concrete, source-grounded values instead of vague claims; stated the exact `preferred-width` formula and made its test vector assert equality; split the ax-press test vector into a positive and a gated-false case and made the scroller/outline-style vectors deterministic; fixed a false Design-Decisions cross-reference in the duplicate-item-ids edge case; corrected the WinUI `AutomationId`/`Name` mapping, removed an editorializing WinUI aside, fixed the Compose disabled-item color guidance, and restructured the React/Web notes to one listbox with grouped sections; dropped the redundant `macos` tag; rewrote the Compliance table to cite only real catalog checks (dropping fabricated ones and the inapplicable `touch-target-size` row, adding `dynamic-type-support` and `platform-theming`). |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/navigation/. |
