<!-- leaf: implement-extension/quick-pick-view-controller--edge-cases · source: extension-quick-pick-view-controller.md -->

# ExtensionQuickPickViewController

**Rules** (cite as `implement-extension/quick-pick-view-controller--edge-cases#<slug>`):

- `multi-select-empty-acceptance` MUST — A user can press Return in multi-select with zero rows checked. acceptedIndices() returns [] (not nil), and choose() …

## Edge Cases

- **Null/empty input — no items**: `model.request.items = []`. `visibleIndices`
  is empty, `highlightedIndex` is nil, the table shows zero rows, and
  `choose()` (Return) is a no-op because `acceptedIndices()` returns nil
  in single-select — computed entirely by `ExtensionQuickPickModel`, with
  no additional guard in this file.
- **Boundary values — all-separator list**: Every item in
  `model.request.items` is a separator. `highlightedIndex` stays nil (no
  selectable row exists), arrow keys and clicks are no-ops throughout, and
  `choose()` never fires `onAccept` in single-select — traceable directly
  to `ExtensionQuickPickModel.firstSelectableIndex` returning nil.
- **Boundary values — separator with no surviving section**: A filter
  query that matches nothing in a section hides that section's separator
  along with its items. This is `ExtensionQuickPickModel`'s own filtering
  rule, not this controller's; see the second entry under **Design
  Decisions** for why it exists.
- **Concurrent access**: Not applicable — the class is
  `@MainActor`-isolated, so Swift's concurrency checker serializes every
  access to its state; there is no code path by which two threads can
  mutate the controller or its model simultaneously.
- **Error states**: Not applicable — every operation in this file (query
  updates, highlight moves, row clicks, table reloads) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  `ExtensionQuickPickViewController.swift`.
- **Offline/disconnected**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ExtensionQuickPickModel` built from a request handed to it at
  construction.
- **Historical defect, now guarded — separator click accepting a stale
  highlight**: See **Design Decisions** (the guard against accepting a
  stale highlight on a separator/out-of-range click) and
  **separator-and-out-of-range-clicks**; the guard is shared by both the
  single- and multi-select branches so this cannot regress silently.
- **Multi-select empty acceptance**: A user can press Return in
  multi-select with zero rows checked. `acceptedIndices()` returns `[]`
  (not nil), and `choose()` calls `onAccept([])` — a real, reportable
  answer, not a dismissal. Callers MUST distinguish an empty array
  (`onAccept([])`) from a dismissal (`onCancel()`) — see **empty-choose**.
