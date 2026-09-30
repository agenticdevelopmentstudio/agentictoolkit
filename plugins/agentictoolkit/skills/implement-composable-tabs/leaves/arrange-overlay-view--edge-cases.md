<!-- leaf: implement-composable-tabs/arrange-overlay-view--edge-cases · source: composable-tabs-arrange-overlay-view.md -->

# ComposableTabsArrangeOverlayView

**Rules** (cite as `implement-composable-tabs/arrange-overlay-view--edge-cases#<slug>`):

- `null-empty-input-panename-defaults-setting-valid` MUST — Null/empty input (MUST): paneName defaults to "" and setting it to "" is valid — the label simply shows no text; …
- `boundary-values-availabledirections-can-return-empty` MUST — Boundary values (MUST): availableDirections can return the empty set (disabling the entire Move button) or all four …
- `availability-between-refreshes-per-refresh-caller-driven` MUST — Stale availability between refreshes (MUST): Per refresh-is-caller-driven, if the data behind canAdd, canRemove, or …

## Edge Cases

- Null/empty input (MUST): `paneName` defaults to `""` and setting it to `""`
  is valid — the label simply shows no text; nothing in source guards or
  rejects an empty pane name. `onAdd`, `onRemove`, `onMove`, and `onDone`
  default to `nil` and are always invoked through optional chaining
  (`onAdd?()`, etc.), so an unset callback is a documented no-op, not an
  error.
- Boundary values (MUST): `availableDirections` can return the empty set
  (disabling the entire Move button) or all four directions (enabling every
  Move item); `canAdd`/`canRemove` are plain booleans with only two possible
  results, each directly reflected in the corresponding button's enabled
  state on the next `refreshAvailability()` call. The caller is expected to
  return `false` from `canRemove` for the last remaining pane and to omit a
  direction from `availableDirections` when the pane is already at that
  edge of the window (e.g. no `Up` for a
  pane already at the top). The caller's responsibility for these boundary
  decisions is the reason `refresh-is-caller-driven` exists: this view has no
  independent knowledge of "last pane" or "top of window" itself, it only
  renders whatever the closures currently report.
- Concurrent access: Not applicable — the class is declared `@MainActor`, so
  Swift's concurrency checker confines all reads and writes of its state and
  UI to the main actor; source provides no path for two threads to mutate
  this view simultaneously.
- Error states: Not applicable — every operation in this file (a button tap
  invoking a callback, `refreshAvailability()` rebuilding menu items, a
  theme change repainting colors) is synchronous and non-throwing; no
  network, database, or file-system call exists anywhere in this file that
  could fail.
- Offline/disconnected: Not applicable — this is a purely local UI overlay
  with no networking call anywhere in source.
- Stale availability between refreshes (MUST): Per `refresh-is-caller-driven`,
  if the data behind `canAdd`, `canRemove`, or `availableDirections` changes
  without a subsequent call to `refreshAvailability()`, the affected
  control(s) MUST continue to show their previously computed enabled state;
  this view performs no polling or tree observation of its own; that
  responsibility belongs to the caller (`ComposableTabsPaneViewController`
  observes `ComposableTabsViewController.layoutDidChangeNotification` and
  calls `refreshAvailability()` itself).
