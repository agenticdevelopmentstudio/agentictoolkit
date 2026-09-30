<!-- leaf: implement-general-controller/pane-view-controller--test-vectors-part-2 · source: pane-view-controller.md -->

# PaneViewController — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pvc-048 | zoom-persisted | `setZoomed(true)` against a store | The store's value for `PaneStateKey.zoomed` is `"1"` |
| pvc-049 | state-restored-on-load | Pre-populate a store with `minimize.edge = "trailing"` and `zoomed = "1"`; load a pane against it | `pane.minimizedEdge == .trailing`; `pane.isZoomed == true` |
| pvc-050 | unparseable-stored-edge-ignored | Pre-populate a store with `minimize.edge = "sideways"`; load a pane against it | `pane.persistedMinimizeEdge == nil`; `pane.minimizedEdge == nil`; no crash |
| pvc-051 | search-reaches-searchable-content-only | Content implementing `PaneSearchable`; call `search(for: "main")` | `isSearchable == true`; the content receives the query "main" |
| pvc-052 | selection-description-reported | Content implementing `PaneSelectionDescribing` with `paneSelectionDescription == "README.md"` | `pane.selectionDescription == "README.md"` |
| pvc-053 | selection-change-forwarded | Set `onSelectionChange`; change the content's `paneSelectionDescription` | `onSelectionChange` fires exactly once |
| pvc-054 | minimized-thickness-formula | `contentInset == 0`; call `minimizedThickness(for: .leading)` and `minimizedThickness(for: .top)` | Returns `28` for `.leading`; returns `26` for `.top` |
| pvc-055 | spacing-clamped-on-read | Pre-populate a store with a `spacing.override` JSON row encoding `top: 999` | The resolved spacing's `top` is `40` (clamped into `0...40`), not `999` |
| pvc-056 | spacing-decode-failure-is-absent | Pre-populate a store with `spacing.override = "not valid json"` | `spacingOverride.isOverridden == false`; the resolved spacing equals `inheritedPaneSpacing` |
| pvc-057 | search-reaches-searchable-content-only | Content not implementing `PaneSearchable`; call `search(for: "main")` | `isSearchable == false`; the call neither crashes nor has any observable effect on the content |
| pvc-058 | selection-description-reported | Content not implementing `PaneSelectionDescribing` | `pane.selectionDescription == nil` |
| pvc-059 | accessories-from-content | Content not implementing `PaneAccessoryProviding`; call `refreshAccessories()` | `titleBar.accessoryViews == []` |
| pvc-060 | rail-glyph-from-content | Content not implementing `PaneMinimizedRepresenting`; minimize to `.leading` | The rail's `symbolName == PaneMinimizedStripView.defaultSymbolName`; its `tooltip == resolvedTitle` |
| pvc-061 | clamped-pane-yields-width | Construct a pane and never set `clampsToContainer` to `true`, then set it to `false` | The title bar's horizontal content-compression-resistance priority is unchanged from its default — `yieldWidthToContainer()` is never called |
| pvc-062 | spacing-defaults-to-inherited | Content implementing `PaneContentSpacingConsuming` with `inheritedPaneSpacing == Spacing(top: 10, leading: 0, bottom: 0, trailing: 0)`, no stored override | `pane.inheritedPaneSpacing` equals exactly the content's value, `Spacing(top: 10, leading: 0, bottom: 0, trailing: 0)` |
