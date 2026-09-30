<!-- leaf: implement-general-2/pane-spacing--edge-cases · source: pane-spacing.md -->

# PaneSpacing

## Edge Cases

- **Null/empty input**: Not applicable — `UserSetting<Int>`'s `default` guarantees a concrete `Int` is always returned even when nothing has been stored yet (see `edge-inset-default-zero`/`gutter-default-one-point`); there is no nil or missing-value case for any of the six settings.
- **Boundary values — zero-point gutter**: A `0`-point gutter is a legitimate, source-supported look. It is drawn via the `dividerThickness <= 1` branch (AppKit's own hairline paint) and stays draggable only because consumers widen the hit-test rect to `minimumDividerGrab`; this file itself does no widening.
- **Boundary values — exactly `1` point**: `drawDivider(in:)`'s own guard (`dividerThickness > 1`) treats `1` as the hairline case, not the filled case — the boundary is inclusive of `1` on the hairline side.
- **Boundary values — negative or unusually large stored settings**: `UserSetting<Int>` and `PaneSpacing.current` accept and pass through any stored `Int` — including a negative value or one set outside whatever range a settings UI would offer (for example via a direct write to the underlying store) — with no clamping or validation anywhere in this file before it reaches `NSEdgeInsets` or `dividerThickness`. This is by design (see Design Decisions: clamping ownership): `PaneSpacing` is a thin passthrough over `UserSetting<Int>`, and range validation on interactively-entered values is the settings-control layer's job, done through `Spacing.setting(_:to:in:)`/`Spacing.adjusting(_:by:in:)` and `Int.clamped(to:)` — mechanisms this file's `current` never calls.
- **Concurrent access**: Not applicable — `PaneSpacing`, `PaneSplitView`, and `UserSetting` are all `@MainActor`-isolated; every read and write of the six settings in this source is confined to the main actor.
- **Error states**: Not applicable — `UserSettings.shared.get`/`set` (reached through `StorableSetting.value`) return and accept concrete, non-optional, non-throwing values; this file exposes no failure path to handle.
- **Offline/disconnected state**: Not applicable — this component performs only local, synchronous settings storage; it makes no network call and has no dependency on connectivity.
