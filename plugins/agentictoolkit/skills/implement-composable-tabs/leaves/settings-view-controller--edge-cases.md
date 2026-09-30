<!-- leaf: implement-composable-tabs/settings-view-controller--edge-cases · source: composable-tabs-settings-view-controller.md -->

# ComposableTabsSettingsViewController

## Edge Cases

- Null/empty input: `isEdgeEnabled` and `setEdgeEnabled` are non-optional,
  escaping closure parameters; Swift's type system rules out `nil`. A
  closure that always returns `false` from `isEdgeEnabled` is well-defined
  here: every checkbox initializes `.off`. No string or collection input
  in this file can be empty in a way that changes its behavior. The
  component provides, and needs, no nil-handling path for either closure
  parameter.
- Boundary values: The four checkboxes are two-valued (on/off); there is no
  numeric boundary in the Tabs panel. The Spacing panel's numeric range
  (`0...40`) is the default of `SpacingControl.boundToSettings`'s `range`
  parameter — this file passes no explicit `range:` argument to either
  `boundToSettings` call, so both the frame and divider controls inherit
  `0...40` unmodified. Clamping behavior at 0 or 40 is `SpacingControl`'s
  own responsibility, not decided in this file.
- Concurrent access: All four classes in this file are `@MainActor`, so the
  Swift compiler serializes every construction and mutation to the main
  actor — this file itself has no concurrency hazard. Worth noting, though:
  `PaneSpacing.edgeSettings`/`gutterSettings` are shared, app-wide
  `UserSetting<Int>` instances (per `PaneSpacing`'s own doc comment:
  "App-wide, deliberately... A window whose panes are spaced differently
  from the window beside it reads as a bug"), so opening this sheet on two
  project windows at once and editing spacing in one updates the bound
  control's displayed value in the other, since both bind live to the same
  setting objects.
- Error states: Not applicable — every call in this file (layout,
  `dismiss(self)`, `setEdgeEnabled`, `SpacingControl.boundToSettings`) is
  synchronous and non-throwing; no `try`, `Result`, or completion-with-error
  API appears anywhere in source.
- Offline/disconnected: Not applicable — this file performs no networking;
  every dependency it touches (`UserSetting`, the injected closures, the
  theme palette) is in-process, local state.
- Last-edge-disable refusal: Per **reverts-checkbox-to-authoritative-state**,
  this file has no independent rule of its own that keeps at least one edge
  enabled; it only reflects whatever `isEdgeEnabled` reports after calling
  `setEdgeEnabled`. The actual "refuse to disable the last edge" logic — and
  its persistence — live entirely outside this file, behind the injected
  closures.
- Out-of-range checkbox tag: Per **guards-invalid-checkbox-tag**,
  `toggleEdge(_:)` guards `Self.edges.indices.contains(sender.tag)` before
  indexing; this file's own construction path only ever assigns tags
  `0...3`, so the guard is dead code under normal use, but it is
  source-present, testable behavior: a checkbox retagged to an
  out-of-range value externally (e.g., from test code) causes the action to
  silently no-op rather than trap.
