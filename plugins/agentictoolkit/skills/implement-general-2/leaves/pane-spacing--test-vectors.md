<!-- leaf: implement-general-2/pane-spacing--test-vectors · source: pane-spacing.md -->

# PaneSpacing

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pane-spacing-001 | edge-inset-default-zero | Fresh store, no `pane_spacing_top` value ever set | `UserSettings.paneSpacingTop.value == 0` |
| pane-spacing-002 | gutter-default-one-point | Fresh store, no `pane_spacing_between_columns` value ever set | `UserSettings.paneSpacingBetweenColumns.value == 1` |
| pane-spacing-003 | settings-not-secure | Inspect `isSecure` on each of the six `UserSettings.paneSpacing*` settings | Every one reports `isSecure == false` |
| pane-spacing-004 | current-reads-live-value-per-field | Set `UserSettings.paneSpacingLeading.value = 12`, then read `PaneSpacing.current` | `PaneSpacing.current.leading == 12` |
| pane-spacing-005 | current-populates-all-six-fields | Set all six settings to distinct nonzero values, then read `PaneSpacing.current` | `top`, `leading`, `bottom`, `trailing`, `betweenColumns`, and `betweenRows` each equal the value set for that field |
| pane-spacing-006 | content-insets-maps-fields-to-nsedgeinsets | Set edges to `top: 1, leading: 2, bottom: 3, trailing: 4` | `PaneSpacing.contentInsets == NSEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)` |
| pane-spacing-007 | minimum-divider-grab-fixed | Set `betweenColumns` to `0`, then to `50` | `PaneSpacing.minimumDividerGrab == 6` in both cases |
| pane-spacing-008 | divider-thickness-selects-axis-gutter | `PaneSplitView.isVertical = true`, `betweenColumns = 8` | `dividerThickness == 8` |
| pane-spacing-009 | divider-thickness-selects-axis-gutter | `PaneSplitView.isVertical = false`, `betweenRows = 2` | `dividerThickness == 2` |
| pane-spacing-010 | divider-paint-defers-when-hairline | Gutter at its `1`pt default; a test subclass overrides `drawDivider(in:)` to record whether its `super` implementation ran, then calls `drawDivider(in:)` | The recorded `super.drawDivider(in:)` call happened, and sampling a pixel inside the divider rect after the call does not show `currentPalette.projectPaneBackdrop` |
| pane-spacing-011 | divider-paint-fills-with-pane-backdrop | `isVertical = true`, `betweenColumns = 10`; a test subclass overrides `drawDivider(in:)` to record whether its `super` implementation ran, then calls `drawDivider(in:)` and renders into a bitmap context | The recorded `super.drawDivider(in:)` call did not happen, and sampling pixels across the full divider rect in the rendered bitmap shows `NSColor(currentPalette.projectPaneBackdrop)` |
| pane-spacing-012 | spacing-change-toggles-divider-style | `dividerStyle == .thin`; a test subclass or KVO observer records every value assigned to `dividerStyle`, then calls `spacingDidChange()` | The recorded assignments show `dividerStyle` set to a value other than `.thin` and then back to `.thin`, in that order (any other-than-original intermediate value satisfies the requirement, not only `.paneSplitter`); alternatively, an `NSSplitViewController` observably re-reads `dividerThickness` after the call |
| pane-spacing-013 | spacing-change-marks-needs-display | `needsDisplay == false`, call `spacingDidChange()` | `needsDisplay == true` |
| pane-spacing-014 | spacing-shared-across-windows | Two `PaneSplitView` instances, each vertical, in two different windows; change `UserSettings.paneSpacingBetweenColumns.value` once | Both instances' `dividerThickness` reflect the new value |
| pane-spacing-015 | setting-changes-persist-via-shared-store | Set `UserSettings.paneSpacingTop.value = 5`, then read `UserSettings.shared.get(UserSettings.paneSpacingTop)` directly | Returns `5`, showing the write reached the shared store rather than only the setting object's cached `currentValue` |
