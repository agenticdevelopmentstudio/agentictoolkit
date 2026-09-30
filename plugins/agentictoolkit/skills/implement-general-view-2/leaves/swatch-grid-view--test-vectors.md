<!-- leaf: implement-general-view-2/swatch-grid-view--test-vectors · source: swatch-grid-view.md -->

# SwatchGridView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| swatch-grid-view-001 | clamps-column-count | Construct with `columns: 0` | The component lays out swatches into rows of at most 1 swatch each (columns treated as 1) |
| swatch-grid-view-002 | clamps-column-count | Construct with `columns: -3` | The component lays out swatches into rows of at most 1 swatch each (columns treated as 1) |
| swatch-grid-view-003 | arranges-swatches-in-rows | Construct with 10 colors and `columns: 4` | 3 rows are produced: 4, 4, and 2 swatches, in the same order as the input array |
| swatch-grid-view-004 | builds-hierarchy-on-init | Construct with 3 colors and `columns: 8` | Immediately after `init` returns, the view's row/swatch hierarchy contains exactly 1 row with exactly 3 swatches |
| swatch-grid-view-005 | replaces-colors-and-rebuilds | Construct with 5 colors, then call `setColors([])` | The view's row/swatch hierarchy is empty (0 rows, 0 swatches) after the call; none of the original 5 swatch views remain anywhere in it |
| swatch-grid-view-006 | replaces-colors-and-rebuilds | Construct with 2 colors, then call `setColors(_:)` with 6 new colors and `columns` unchanged at 8 | The view's row/swatch hierarchy contains exactly 1 row with exactly 6 swatches, none of which are the original 2 swatch view instances |
| swatch-grid-view-007 | pins-container-to-edges | Construct the component and inspect its internal stack view's constraints (found among `self.subviews`) | That stack view's top/leading/trailing/bottom anchors are each constrained equal to the corresponding anchor of `self`, with no constant offset |
| swatch-grid-view-008 | uses-uniform-spacing | Construct with `spacing: 10` | The internal stack view's spacing and every row's spacing each equal 10 |
| swatch-grid-view-009 | sizes-swatch-fixed | Construct with `swatchSize: CGSize(width: 40, height: 16)` and 1 color | The resulting swatch view has an active width constraint of 40 and an active height constraint of 16 |
| swatch-grid-view-010 | renders-swatch-style | Construct with 1 color and inspect the resulting swatch's layer | `wantsLayer == true`, `layer.cornerRadius == 3`, `layer.backgroundColor == color.cgColor`, `layer.borderWidth == 0.5` |
| swatch-grid-view-011 | renders-swatch-style | Construct with 1 color, then call `ThemeManager.selectTheme(id:)` to switch the shared `ThemeManager` from one built-in theme (e.g. `solarizedDark`) to another (e.g. `dracula`) | The swatch's `layer.borderColor` changes from the old theme's `.border` role color to the new theme's `.border` role color; `layer.backgroundColor` (the fill) is unaffected |
| swatch-grid-view-012 | traps-on-coder-init | Attempt `SwatchGridView(coder: someCoder)` | The call traps with a fatal error; no instance is returned. AppKit-specific: a fatal trap cannot be caught inside the normal test process, so this requires a subprocess/death-test harness, and has no analogue on platforms without a coder-based initializer. |
| swatch-grid-view-013 | renders-empty-grid | Construct with `colors: []` | The view has zero rows and zero swatches immediately after `init` returns |
| swatch-grid-view-014 | shortens-final-row | Construct with 10 colors and `columns: 4` | The final row contains exactly 2 swatches (`10 % 4`), fewer than a full row of 4 |
| swatch-grid-view-015 | single-row-when-columns-exceeds-count | Construct with 3 colors and `columns: 8` | Exactly 1 row is produced, containing all 3 swatches, fewer than `columns` |
