<!-- leaf: implement-general-controller/topic-list-view-controller--edge-cases · source: topic-list-view-controller.md -->

# TopicListViewController

**Rules** (cite as `implement-general-controller/topic-list-view-controller--edge-cases#<slug>`):

- `null-empty-input-setsections-yields-empty-rootnodescache` MUST — Null/empty input (MUST): setSections([]) yields an empty rootNodesCache; the outline shows zero rows and selectedItem …
- `boundary-values-sections-title-footer-header` MUST — Boundary values (MUST): With no sections, no title, no footer, and no header accessory, preferredWidth() returns …
- `duplicate-item-ids-selectitem-withid-resolves-via` SHOULD — Duplicate item ids (SHOULD): selectItem(withId:) resolves via a first-match lookup; if two items across sections share …
- `reached-via-selecteditem-selecteditem-guard-case-item` MUST — Header row reached via selectedItem (MUST): selectedItem's guard (case .item(let item) = node.kind else { return nil }) …
- `selection-suppression-scopes-selectionsuppressiondepth-integer-nesting-counter` MUST — Nested selection-suppression scopes (MUST): selectionSuppressionDepth is an integer nesting counter, not a boolean, …

## Edge Cases

- Null/empty input (MUST): `setSections([])` yields an empty
  `rootNodesCache`; the outline shows zero rows and `selectedItem` returns
  `nil`. `TopicListItem.icon` and `TopicListSection.title` are both
  optional and handled per **render-item-without-icon-when-nil** and
  **omit-header-for-untitled-section**; `TopicListItem.id`/`title` are
  non-optional `String`s, so Swift's type system rules out `nil` for them.
- Boundary values (MUST): With no sections, no title, no footer, and no
  header accessory, `preferredWidth()` returns exactly
  `outlineChromePadding` (64pt) — the minimum value this method can produce.
  Source imposes no maximum on section or item count; any array size is
  handled uniformly through the same `rootNodesCache`/`NSOutlineView` row
  model.
- Duplicate item ids (SHOULD): `selectItem(withId:)` resolves via a
  first-match lookup; if two items across sections share an id, only the row
  for the first match in outline order is ever selected by this method —
  source performs no uniqueness validation. Callers SHOULD supply unique ids
  across all sections passed to one `setSections(_:)` call; this is
  undocumented in source and left to caller discipline. This SHOULD needs no
  separate test vector: the behavior described here is a direct,
  deterministic consequence of the same first-match lookup **select-item-by-id**'s
  vector (topic-list-012) already exercises, and a second, near-identical
  vector for the duplicate-id case would not exercise any additional code
  path.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so Swift's concurrency checker confines all reads and writes of
  `sections`, `rootNodesCache`, and `selectionSuppressionDepth` to the main
  actor; source provides no path for two threads to mutate this view
  controller's state simultaneously.
- Error states: Not applicable — this file contains no throwing function,
  no `Result`, and no network or file-system call; `setItems`, `setSections`,
  and `selectItem(withId:)` are synchronous, non-throwing operations with no
  failure mode to represent beyond the silent no-ops already described
  above (missing id, already-selected id).
- Offline/disconnected: Not applicable — the component performs no
  networking anywhere in source; it only renders caller-supplied in-memory
  data.
- Header row reached via `selectedItem` (MUST): `selectedItem`'s guard
  (`case .item(let item) = node.kind else { return nil }`) returns `nil`
  defensively if `outlineView.selectedRow` were ever a group header row;
  in practice this cannot occur because `shouldSelectItem` already refuses
  to select header rows, but the accessor does not rely on that invariant
  holding elsewhere in the outline's delegate chain.
- Nested selection-suppression scopes (MUST): `selectionSuppressionDepth`
  is an integer nesting counter, not a boolean, specifically so that a
  suppression scope nested inside another still leaves suppression active
  until the outer scope also exits; no call site in this file nests scopes
  today, but `suppressingSelectionCallbacks` supports it without change if
  a future call site does.
