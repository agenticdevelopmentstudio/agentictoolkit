<!-- leaf: implement-general-view-2/log-view--part-2 · source: log-view.md -->

# Log View — continued (part 2)

**Rules** (cite as `implement-general-view-2/log-view--part-2#<slug>`):

- `decision` MUST — Route click hooks only through the table's own click/double-click actions, and expose the click-dispatch method …

## Accessibility

- Role/trait: The component adds no custom `NSAccessibility` conformance or
  role override; VoiceOver sees AppKit's built-in table accessibility
  hierarchy (table, then row, then cell) unmodified.
- Label requirements: Each cell's accessible value is its own displayed
  text, which AppKit exposes automatically as the text field's accessibility
  value; column headers get their accessible name from the caller-supplied,
  required `LogColumn.title`. No cell or column is left without a label.
- Minimum tap target: Not applicable. This is a pointer-driven macOS
  control, not a touch surface; row height is left to AppKit's system
  default for `rowSizeStyle: .default`, and no explicit width or height is
  set on the table, its columns, or its cells.
- Contrast: Not applicable at this component's level. The component fixes
  no numeric color value itself — it selects semantic theme roles
  (`.windowBackground`, `.divider`, `.selection`, and `ThemedLabel`'s
  default `.primaryText`) whose concrete colors, and therefore their
  contrast ratios, are resolved by the active theme palette at runtime.
  Meeting a contrast standard is that palette's responsibility, not
  something decidable from this file.
- Keyboard operability: The per-column `onClick`/`onDoubleClick` hooks are
  wired only to the table's mouse click and double-click actions
  (`tableClicked`/`tableDoubleClicked`, both driven by `NSTableView`'s
  `target`/`action`/`doubleAction`); no key-event handler calls
  `dispatchClick(columnIndex:row:kind:)`, so a keyboard-only or
  switch-control user who selects a row with the keyboard has no way to
  trigger that row's column click hook.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `provider` | `any LogProvider` | required (no default) | The backing data source; its `columns` are captured once at init, its `lines` are re-read on every table reload. |
| `followTail` | `Bool` | `true` | Whether newly appended rows auto-scroll into view and whether a full replace re-anchors to the bottom; setting it to `false` is how a caller builds a "pause auto-scroll" control. |

`LogColumn` (id, title, widths, alignment, click hooks) and `LogLine`
(values, context) are separate value types defined in sibling files, not
owned by this component; this table covers only the options `LogView`
itself exposes.

## Accessibility Options

- **Reduce Motion**: Not applicable. The component calls the
  scroll-to-visible operation directly, with no animation context or
  animator proxy wrapping it, so there is no motion effect to suppress.
- **Increase Contrast**: Not applicable at this component's level. Colors
  are drawn entirely from semantic theme roles; neither this component nor
  the themed view types it uses branch on an increase-contrast accessibility
  setting, so any such adaptation would live in the theme/palette system,
  not here.
- **color-only-selection-cue**: The selected row is conveyed by a background color fill alone (`selected-row-uses-theme-selection-color`) with no additional shape, border, or icon; the component does not respond to Differentiate Without Color.

## Privacy

- **Data collected**: None collected by this component itself. It only
  renders whatever `LogLine`s the provider already holds, including each
  line's opaque `context` payload, which `LogView` never reads itself — it
  only forwards the whole line to a column's click hooks.
- **Storage**: None. The component writes nothing to disk or
  `UserDefaults`.
- **Transmission**: None. The component makes no network calls.
- **Retention**: Determined entirely by the provider. `LogView` keeps no
  copy of the data beyond what it reads from `provider.lines` at render
  time; any row-count cap (`maxLines`) is the provider's own concern, not
  this component's.

## Platform Notes

- **SwiftUI**: The source is pure AppKit (`NSView`/`NSTableView`), not
  SwiftUI. A SwiftUI counterpart would use `Table` (or `List` for a
  single-column case) driven by an `ObservableObject` wrapping the same
  `LogProvider` contract, one `TableColumn` per `LogColumn`, a tap gesture
  or context menu in place of `onClick`/`onDoubleClick`, and a
  `ScrollViewReader` with `scrollTo(id:anchor:.bottom)` in place of the
  scroll-to-end operation and `followTail`.
- **Compose**: Start from a `LazyColumn` (or a row of independently-scrolled
  `LazyColumn`s for true per-column widths) backed by a `StateFlow<List
  <LogLine>>` equivalent to `provider.lines`; per-column click hooks map to
  `Modifier.pointerInput` with `detectTapGestures(onTap, onDoubleTap)`; tail
  follow maps to `LazyListState.animateScrollToItem` on the last index,
  gated the same way — only when already near the bottom, or unconditionally
  on a full replace.
- **React/Web**: Use a virtualized table/grid fed the same column and line
  shape; per-column click handlers become `onClick`/`onDoubleClick` on each
  cell; tail follow is the common scrollback pattern — check whether the
  scroll container is within a small threshold of its bottom before an
  append, then scroll it to the bottom after the DOM updates, mirroring this
  component's pre-reload scroll check.
- **AppKit / UIKit**: This is the source platform (AppKit, macOS). A UIKit
  counterpart has no first-class multi-column table equivalent to
  `NSTableView`; it would use a `UITableView`/`UICollectionView` with a
  compositional, multi-column cell layout, a diffable data source driven by
  the same `LogProvider` contract, a tap and a long-press or double-tap
  gesture recognizer in place of the table's click and double-click
  actions, and a scroll-to-row operation in place of the scroll-to-visible
  call.
- **WinUI 3**: Model the table as a `DataGrid` (from the Windows Community
  Toolkit's WinUI controls), the closest match to a multi-column,
  user-resizable, per-cell-styled `NSTableView`; a plain `ListView` with a
  `Grid`-based row template is the alternative if avoiding that dependency.
  Map each `LogColumn` to a `DataGridTextColumn`/`DataGridTemplateColumn`
  with its `Width`, `MinWidth`, and `MaxWidth` bound from the column model;
  bind `ItemsSource` to an observable collection standing in for
  `provider.lines`; wire a tapped and a double-tapped handler on each cell
  to the same per-column `onClick`/`onDoubleClick` hooks; drive the selected
  row's highlight from a style targeting the row's background in its
  selected visual state, using the app's selection brush — WinUI's
  selection highlight is typically full-bleed rectangular, not the 4pt
  rounded, inset rectangle this AppKit view draws, which is worth calling
  out to implementers as an intentional visual difference rather than a
  bug; and implement tail follow by checking the scroll viewer's vertical
  offset against its scrollable height, using the same 2-point tolerance
  this file uses, before appending, then scrolling to the last item after
  the collection updates.

## Design Decisions

**Decision**: Fill the table with the `.windowBackground` theme role rather
than `.surface`.
**Rationale**: source comments state the log should read as the full
content of its own window or pane, rather than as a sidebar, matching how a
related timeline's table is themed — so it blends into the backdrop instead
of reading as its own plane.
**Approved**: pending.

**Decision**: Turn off alternating row background colors and rely on a
horizontal-only grid line for row separation instead of banding.
**Rationale**: source comments state banding comes from a system color pair
the theme has no say in, and that without any row separator the log read as
an unbroken block of text with no row boundaries at all — the horizontal
grid line is the theme-controlled substitute.
**Approved**: pending.

**Decision**: Capture `provider.columns` once, at `init(provider:)`, and
never rebuild the table's column set afterward.
**Rationale**: the provider's own documentation states columns are expected
to be stable for the lifetime of the provider and that this component
captures them at init time; later column changes are out of contract.
**Approved**: pending.

**Decision**: Compute the scroll-position check before calling reload on an
appended change, rather than after.
**Rationale**: the tail-follow decision needs the scroll position as it was
before new rows were inserted — checking after the reload would measure
geometry that already includes the newly appended rows, which would always
read as "not at bottom" whenever new content is what pushed the content
taller than the viewport.
**Approved**: pending.

**Decision**: Return a newly constructed row view on every delegate
callback instead of reusing a dequeued instance by identifier.
**Rationale**: source comments state each row needs to own its own theme
observer, since a selection fill baked in at creation would draw stale after
a theme change if the instance were pooled and reused across it; AppKit
still recycles the row views this method returns internally regardless of
whether the caller dequeues them itself. This is the mechanism behind
`selection-fill-reflects-current-theme`.
**Approved**: pending.

**Decision**: Request cell views through `makeView(withIdentifier:owner:)`
with a per-column reuse identifier (`cell.<columnID>`), rather than always
constructing a new `ThemedLabel` for every rendered row.
**Rationale**: source code routes every cell request through AppKit's own
view-reuse pool keyed by that identifier, so a cached view is served back
when one is available; this is the mechanism behind
`cell-request-uses-column-reuse-identifier`.
**Approved**: pending.

**Decision**: Route click hooks only through the table's own click/double-click
actions, and expose the click-dispatch method publicly.
**Rationale**: source comments state this lets tests (and callers doing
programmatic dispatch) drive the same entry point AppKit uses, without
needing to synthesize real mouse events. This is why
`public-dispatch-applies-same-guards` is stated as a MUST rather than left
as an API-visibility note.
**Approved**: pending.
