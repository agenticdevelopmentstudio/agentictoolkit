<!-- leaf: implement-settings/panel-list-view-controller--edge-cases · source: settings-panel-list-view-controller.md -->

# PanelListViewController

**Rules** (cite as `implement-settings/panel-list-view-controller--edge-cases#<slug>`):

- `null-empty-input` MUST — setPanels([]) MUST leave the sidebar with no sections and no rows, with no crash — buildSections(from:) over an empty …
- `boundary-values` MUST — selectPanel(at:), isPanelVisible(at:), and the internal row-id resolver MUST behave correctly at the first (0) and last …
- `query-with-repeated-whitespace` MUST — A searchQuery containing multiple consecutive spaces (e.g. "a b") MUST narrow the same way a single-spaced query does — …

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
