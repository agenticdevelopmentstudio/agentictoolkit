<!-- leaf: implement-general-controller/topic-list-view-controller--part-2 · source: topic-list-view-controller.md -->

# TopicListViewController — continued (part 2)

## Appearance

- **Corner radius**: 4pt (`xRadius`/`yRadius`) on the selection-highlight
  rounded rect drawn by `ThemedTableRowView.drawSelection(in:)`, the row
  view this controller returns from `outlineView(_:rowViewForItem:)`. No
  other corner radius appears in this file.
- **Padding**: Title header: 10pt top / 6pt bottom inset from `headerView`'s
  edges to `headerStack`; 14pt leading (`titleLeadingInset`) and 14pt
  trailing (`headerTrailingInset`) inset from `headerView`'s edges to
  `headerStack`; 8pt vertical gap (`headerAccessorySpacing`) between the
  title label and the accessory container. Item cell: 4pt leading inset
  (`iconLeadingInset`) from the cell to the icon; 6pt gap
  (`iconToTextGap`) between icon and label; 4pt trailing inset
  (`textTrailingInset`) from the label to the cell's trailing edge. Header
  (group) cell: 2pt leading inset (`headerLeadingInset`), vertically
  centered.
- **Font**: `CellMetrics.itemFont` = `palette.font(.body)` (item labels);
  `CellMetrics.headerFont` = `palette.font(.caption)` (group header labels);
  `CellMetrics.titleFont` = `palette.font(.button)` (title label). All three
  read the live theme palette rather than a fixed point size, and are
  reapplied on every cell reuse (`viewFor tableColumn:` runs on pooled
  cells) rather than baked in once at cell creation.
- **Background**: `view`, `contentStack`, `headerView`, and `footerContainer`
  are all painted with `palette.windowBackgroundColor` via their
  `CALayer.backgroundColor` in `applyTheme(_:)`; `scrollView.backgroundColor`
  and `outlineView.backgroundColor` are set to the same value.
- **Foreground/Text**: Item label: `palette.primaryTextColor` when enabled,
  `palette.tertiaryTextColor` when `isDisabled`. Item icon tint:
  `palette.accentColor` when enabled, `palette.tertiaryTextColor` when
  `isDisabled`. Group header label: `palette.secondaryTextColor`. Title
  label: `palette.secondaryTextColor`.
- **Border**: Not set explicitly anywhere in this file; `scrollView`'s
  `borderType` is never assigned, so it keeps `NSScrollView`'s own default
  value, `.noBorder` — no border is drawn around the scroll view.
- **Shadow**: Not applicable — no shadow is drawn, and no `CALayer` shadow
  property is configured, anywhere in this file.
- **Min/Max size**: No explicit min/max width or height constraint is
  applied to the controller's own view; `preferredWidth()` instead computes
  a content-driven width for a caller (e.g. an enclosing split view) to size
  the sidebar to, rather than the sidebar enforcing its own bounds. The item
  icon has a fixed 16×16pt size (`CellMetrics.iconSize`).

## Accessibility

- **Role/trait**: Not explicitly set via `setAccessibilityRole` anywhere in
  this file; the outline, its rows, and its cells use AppKit's default
  `NSOutlineView` roles, with group header rows marked via
  `isGroupItem == true`.
- **Label requirements**: Each item row's label carries an explicit
  accessibility identifier, `"topic-list.item.\(AccessibilityID.slug(item.title))"`
  (see **item-accessibility-id-from-title**), and its accessible name is its
  own `stringValue` (the item's title) — no separate `accessibilityLabel`
  override is set. Group header, title, and footer/accessory views carry no
  accessibility identifier in this file.
- **Announce state changes**: Not implemented. When `setSections(_:)`
  reloads the outline with a different row count, no
  `NSAccessibility.post(element:notification:)` (or equivalent) call informs
  VoiceOver that the visible row set changed; a VoiceOver user hears nothing
  until navigating back into the outline.
- **Minimum tap target**: `outlineView.rowSizeStyle = .default` — per
  Apple's documentation, `NSTableView.rowHeight` (whose documented default
  is 16pt) "is used only if the table's `rowSizeStyle` is set to `custom`",
  so with `.default` and no delegate `tableView(_:heightOfRow:)` override
  (neither present in this file) AppKit derives the row's actual height from
  its effective style rather than a literal value this file sets. Whatever
  value that resolves to for the fonts this component uses is well under the
  44×44pt iOS minimum. This is expected for a pointer/keyboard-driven macOS
  list (not a touch surface); the 44×44pt (iOS) / 48×48dp (Android) minimum
  applies to the touch-platform translations described in Platform Notes,
  not to this AppKit control. Additionally, an item row label's
  `accessibilityPerformPress()` gives assistive technology a press path into
  a row regardless of its rendered size, since activation does not depend on
  a pointer hitting a physical target.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sections` | `[TopicListSection]` | `[]` | Full sectioned row model; set via `setSections(_:)` (grouped, headers per non-empty section title) or `setItems(_:)` (flat, wraps items in one untitled section). |
| `onSelect` | `(((any TopicListItemProtocol)?) -> Void)?` | `nil` | Invoked with the newly selected item, or `nil`, on a user-driven selection change; never invoked for a programmatic change made through `selectItem(withId:)` or a theme-triggered reload. |
| `title` (`listTitle`) | `String?` | `nil` | Text shown in the optional header above the list, set via `setTitle(_:)`; `nil` or empty hides the header unless a header accessory view is set. |
| `footerView` | `NSView?` | `nil` | Client view pinned below the list via `setFooterView(_:)`, spanning the sidebar width; `nil` collapses the footer to zero height. |
| `headerAccessoryView` | `NSView?` | `nil` | Client view shown directly beneath the title and above the list via `setHeaderAccessoryView(_:)`, spanning the header's width; `nil` collapses to nothing. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | — | This file defines no user-facing string literal of its own. |

Not applicable beyond the row above: every displayed string — item titles,
section titles, and the list's own title — comes from caller-supplied data
(`TopicListItem.title`, `TopicListSection.title`, and `setTitle(_:)`'s
parameter), not from a string table owned by this component. The only
string literals in this file (`"TopicListColumn"`, `"TopicListHeader"`,
`"TopicListItem"`, and the `"topic-list.item.…"` accessibility identifier
prefix) are internal AppKit/accessibility identifiers, never shown on
screen.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext` call anywhere in this file; every
  state change (selection, resection, theme repaint) is an instantaneous
  property assignment or a synchronous `reloadData()`.
- **Increase Contrast**: Not applicable to this file specifically —
  `TopicListViewController.swift` never assigns a raw `NSColor` literal;
  every color it uses is read from `SemanticPalette` (via
  `ThemePaletteObserver`/`view.resolvedThemeScope.palette`). Whether the
  active palette itself adjusts under Increase Contrast is that theme
  system's responsibility, not something this component decides or can
  override.
- **Differentiate Without Color**: Not implemented. A disabled item
  (`isDisabled == true`) is distinguished from an enabled one only by color —
  `tertiaryTextColor` versus `primaryTextColor`/`accentColor` (see
  **mute-disabled-item-appearance**) — with no accompanying non-color cue: no
  icon change, no strikethrough, and no opacity reduction, since `alphaValue`
  is explicitly set to `1.0` for every row.

## Privacy

- **Data collected**: None by the component itself — it only renders
  caller-supplied `TopicListItem`/`TopicListSection` values for display.
- **Storage**: In-memory only (`sections`, `rootNodesCache`), for the view
  controller's lifetime; nothing is written to disk, `UserDefaults`, or any
  other store by this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view controller's lifetime; state is
  discarded when the controller is deallocated.

