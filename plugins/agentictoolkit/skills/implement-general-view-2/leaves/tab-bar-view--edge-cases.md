<!-- leaf: implement-general-view-2/tab-bar-view--edge-cases · source: tab-bar-view.md -->

# TabBarView

**Rules** (cite as `implement-general-view-2/tab-bar-view--edge-cases#<slug>`):

- `null-empty-input-setitems-selectedid-nil-leave` MUST — Null/empty input (MUST): setItems([], selectedID: nil) MUST leave the bar with no arranged subviews, and …
- `boundary-values-single-item-bar-items` MUST — Boundary values (MUST): A single-item bar (items.count == 1) MUST compute a stackDepth of 0 for that item whether or …
- `unset-hostcontroller-hostcontroller-nil-viewcontroller-item` MUST — Unset hostController (MUST): When hostController is nil, a .viewController item's addChild call is skipped entirely …

## Edge Cases

- Null/empty input (MUST): `setItems([], selectedID: nil)` MUST leave the bar
  with no arranged subviews, and `updateThickness()` MUST fall back to
  `preferredThickness(for: edge)` since `hostedControllers` is empty
  (see tab-bar-view-025). `renameItem(id:title:)` for an id absent from
  `items` MUST be a silent no-op (see tab-bar-view-017).
- Boundary values (MUST): A single-item bar (`items.count == 1`) MUST
  compute a `stackDepth` of `0` for that item whether or not it is selected
  (`selected.map { abs(index - $0) } ?? 1`, and `index == selected == 0`
  when it is); `applyStackOrder()`'s vertical z-raising loop still runs with
  only one view to raise, producing no visible reordering.
- Concurrent access: Not applicable — `TabBarView`, `TabItemHostView`, and
  `TabButton` are all `@MainActor`-isolated (**confines-to-main-actor**), so
  source provides no path for two threads to mutate one instance at the same
  time.
- Error states: Not applicable — `TabBarView.swift` makes no network,
  database, or file-system call. Its only fallible lookups (`items.firstIndex(where:)`
  in `renameItem`/`applyStackOrder`, dictionary subscripts in `setSelected`/
  `updateThickness`) resolve to silent no-ops or default values rather than
  throwing or trapping.
- Offline/disconnected: Not applicable — this component performs no
  networking of any kind.
- Unset `hostController` (MUST): When `hostController` is `nil`, a
  `.viewController` item's `addChild` call is skipped entirely (`hostController?.addChild`),
  so the hosted controller never receives a parent — but its view is still
  wrapped in a `TabItemHostView` and added to the stack regardless, so the
  tab still renders and is still clickable; only parent-based lifecycle
  callbacks (e.g. `viewWillAppear`) are missing.
- Renaming a `.viewController` tab (documented quirk, not a deliberate design
  choice): `renameItem(id:title:)` performs no check on the existing item's
  payload type. Calling it for an id whose current item is `.viewController`
  overwrites that entry with `.title(title)` in `items` while `buttons[id]`
  is `nil` (no button was ever created for a `.viewController` item), so
  `buttons[id]?.title = title` is a no-op — the model now disagrees with what
  is rendered until the next `rebuildButtons()`. `TabBarView.swift`'s own
  comment states this is safe only because the caller
  (`MultiTabbedViewController.renameTab`) already refuses to call it for a
  `.viewController` item, so there is nothing left to guard against here; the
  invariant is enforced entirely by the caller, not by `TabBarView` itself.
  This is recorded as technical debt rather than a supported code path.
- Title tabs on a vertical bar are not depth-reordered (documented quirk, not
  a deliberate design choice): a `.title` `TabButton` on a `.left`/`.right`
  bar receives the same `-16pt` overlapping spacing as a hosted
  `.viewController` item (see **item-spacing-by-orientation**), but
  **vertical-edge-cards-overlap-and-order-by-distance**'s front-to-back
  reordering only ever touches hosted `.viewController` items — a title
  tab's z-order (and so which overlapping title tab draws and hit-tests on
  top) is whatever order it was originally added in, regardless of
  selection. Nothing in source suggests this was a deliberate choice for the
  title-tab case rather than an oversight; it is recorded here, per source
  fidelity, rather than smoothed over.
