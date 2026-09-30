<!-- leaf: implement-composable-tabs/add-pane-view-controller--edge-cases · source: composable-tabs-add-pane-view-controller.md -->

# ComposableTabsAddPaneViewController

**Rules** (cite as `implement-composable-tabs/add-pane-view-controller--edge-cases#<slug>`):

- `null-empty-input-choices-yields-add-popup` MUST — Null/empty input (MUST): choices == [] yields an "Add" popup with zero items and a selected index of -1; per …
- `null-empty-input-onadd-choices-both-non` MUST — Null/empty input (MUST): onAdd and choices are both non-optional initializer parameters, so Swift's type system rules …

## Edge Cases

- Null/empty input (MUST): `choices == []` yields an "Add" popup with zero
  items and a selected index of -1; per **ok-button-disabled-when-choices-empty**
  OK is disabled at load, and per
  **confirm-dismisses-without-onadd-on-invalid-selection** even a forced
  confirm dismisses without invoking `onAdd`, since -1 is never a valid
  index into `choices`.
- Null/empty input (MUST): `onAdd` and `choices` are both non-optional
  initializer parameters, so Swift's type system rules out passing `nil`
  for either; the component provides, and needs, no nil-handling path for
  them.
- Boundary values (observed): the "Where" popup always contains exactly the
  four fixed directions, so its selected index is always valid (0 through
  3) through ordinary UI interaction; the bounds guard in the confirm
  action only ever fails, for "Where", in a hypothetical, non-UI-driven
  case.
- Boundary values (observed): the fallback that picks index 0 if "Right"
  were ever absent from the fixed direction list is unreachable dead code
  in the current source, since that list is a hardcoded four-case literal
  that always contains "Right" (see **Design Decisions**).
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so Swift's concurrency checker confines all reads and writes of
  `choices`, the two popups, and the two buttons to the main actor.
- Error states: Not applicable — the component performs no I/O, no
  throwing call, and no asynchronous work; its only defensive path is the
  index-bounds guard in the confirm action, documented above as a
  boundary-value case rather than an error state.
- Offline/disconnected: Not applicable — the component makes no network
  call anywhere in source.
