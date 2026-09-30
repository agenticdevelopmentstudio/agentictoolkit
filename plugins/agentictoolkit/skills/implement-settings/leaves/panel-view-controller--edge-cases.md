<!-- leaf: implement-settings/panel-view-controller--edge-cases · source: settings-panel-view-controller.md -->

# SettingsPanelViewController

**Rules** (cite as `implement-settings/panel-view-controller--edge-cases#<slug>`):

- `default-omitted-init-construct-default-settingspaneldescriptor-turn` MUST — Null/empty input: see default-descriptor (#requirements/default-descriptor) — init(with:)'s descriptor parameter is …
- `so-swift-compiler-serialize-construction-read-mutation` MUST — Concurrent access: see main-actor-isolation (#requirements/main-actor-isolation) — the class and every member on it are …

## Edge Cases

- Null/empty input: see **default-descriptor** (#requirements/default-descriptor)
  — `init(with:)`'s `descriptor` parameter is `SettingsPanelDescriptor?`, and
  when it is `nil` (its default) or omitted, `init(with:)` MUST construct a
  default `SettingsPanelDescriptor()`, which in turn defaults `title` to
  `""` (`SettingsPanelDescriptor`'s own `convenience init()`). This is a
  well-defined path, not an unhandled gap.
- Boundary values: Not applicable — this file takes no numeric or
  range-constrained input; `descriptor` is a reference type with no bounds.
- Concurrent access: see **main-actor-isolation** (#requirements/main-actor-isolation)
  — the class and every member on it are `@MainActor`-confined, so the
  Swift compiler MUST serialize every construction, read, and mutation to
  the main actor; this file itself has no concurrency hazard.
- Error states: Not applicable — every call in this file (`loadView()`,
  both initializers, `addGroup(_:)`, `hostingView(for:)`) is synchronous and
  non-throwing; no `try`, `Result`, or completion-with-error API appears
  anywhere in source.
- Offline/disconnected: Not applicable — this file performs no networking;
  it touches only in-process AppKit/SwiftUI state.
- Oversized hosted SwiftUI content: see **#design-decisions** for why
  `hostingView(for:)` preserves only `.intrinsicContentSize` on the returned
  `NSHostingView`. Content taller than the detail pane is not clipped or
  resized by this file; `PanelScrollView`'s document (outside this file)
  reads that preference to decide whether to scroll. This file's own
  guarantee is limited to advertising a sizing preference, not a hard
  constraint — it does not itself scroll or clip oversized content.
