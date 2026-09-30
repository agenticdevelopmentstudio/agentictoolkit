<!-- leaf: implement-settings/panel-split-view-controller--edge-cases · source: settings-panel-split-view-controller.md -->

# SettingsPanelSplitViewController

**Rules** (cite as `implement-settings/panel-split-view-controller--edge-cases#<slug>`):

- `null-empty-input` MUST — init(with: nil) MUST use SettingsPanelDescriptor() rather than leaving descriptor unset or crashing …
- `boundary-values` MUST — detailMinimumThickness's 200 and contentSizedSidebar's true are fixed override values, not caller-supplied inputs, so …

## Edge Cases

- **Null/empty input**: `init(with: nil)` MUST use `SettingsPanelDescriptor()`
  rather than leaving `descriptor` unset or crashing
  (**defaults-descriptor-when-omitted**); that default descriptor's `title`
  is the empty string, so `sidebarTitle` is set to `""` — this file
  performs no validation that a title is non-empty.
- **Boundary values**: `detailMinimumThickness`'s `200` and
  `contentSizedSidebar`'s `true` are fixed override values, not
  caller-supplied inputs, so there is no boundary range to exercise on
  them directly; the only defined relationship is that `200` MUST stay
  below `SplitViewController.detailMinimumThickness`'s inherited `400`pt
  default (see Design Decisions).
- **Concurrent access**: Not applicable — the class is `@MainActor`, so
  the Swift compiler rejects construction or mutation from off the main
  actor; there is no concurrent-access surface for this file to define
  behavior for.
- **Error states**: Not applicable — every member in this file (the two
  initializers and the four computed properties) is synchronous and
  non-throwing; no dependency, network call, or fallible operation exists
  in this file.
- **Offline/disconnected state**: Not applicable — this file performs no
  networking and has no dependency on connectivity.
- **Help chain resolves to no help at all**: When there is no inner
  selection and no subclass override of `helpContent`,
  `effectiveHelpContent` evaluates `nil ?? nil` and returns `nil`
  (**surfaces-empty-help-when-chain-exhausted**, composing
  **falls-back-help-content-through-inner-selection**); per
  `ComposableSettingsPanel`'s own doc comment, this is a defined state —
  the outer split's help drawer shows its own empty state rather than
  hiding its help affordance.
- **`descriptor.isDisabled` and `descriptor.section` go unused by this
  file**: `SettingsPanelDescriptor` carries both fields, but neither is
  read anywhere in `SettingsPanelSplitViewController.swift`; this is not a
  gap in this file — both are consumed by the sidebar-row renderer
  (`PanelListViewController`) and by `SplitViewController.ordered(_:)`'s
  sort-by-section logic, outside this file. This file simply has no code
  path that reads either field.
