<!-- leaf: implement-general-view-1/color-picker-view--test-vectors · source: color-picker-view.md -->

# ColorPickerView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| color-picker-view-001 | arranges-row-layout | Construct `ColorPickerView` with any `viewModel` | `label` and `colorWell` are arranged (with an internal spacer) in a single row view that is pinned to the component's edges; no other layout container appears |
| color-picker-view-002 | initializes-from-view-model | `viewModel.title = "Accent"`, `viewModel.color = NSColor.red` | After init, `label.stringValue == "Accent"` and `colorWell.color == NSColor.red` |
| color-picker-view-003 | commits-color-value | Set `colorWell.color = NSColor.blue` and invoke `colorChanged(colorWell)` | `viewModel.color == NSColor.blue` after the call |
| color-picker-view-004 | commits-color-value | Construct with a counting/spy `ColorViewModel` stub whose `color` setter increments a call counter; set `colorWell.color = NSColor.blue` and invoke `colorChanged(colorWell)` twice in a row with the same color | The setter's call counter increments on both invocations (the second, redundant-value write is not skipped) |
| color-picker-view-005 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.color`, then invoke `viewModel.onChange(newColor)` | `label.stringValue` and `colorWell.color` both update to reflect the new `viewModel` state |
| color-picker-view-006 | exposes-constituent-views | Construct the component, then access `.label` and `.colorWell` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSColorWell` instances built during init (`label` is a `ThemedLabel` instance, declared as `NSTextField`) |
| color-picker-view-007 | rejects-coder-initialization | Attempt `ColorPickerView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| color-picker-view-008 | rejects-frame-only-initialization | Attempt `ColorPickerView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| color-picker-view-009 | owns-on-change | Construct two `ColorPickerView` instances in turn against the same `ColorViewModel` instance, then invoke `viewModel.onChange(someColor)` | Only the second view's `label`/`colorWell` update; the first view's handler was silently replaced and is never invoked |
| color-picker-view-010 | delegates-color-clamping | Set `colorWell.color` to an out-of-gamut `NSColor` and invoke `colorChanged(colorWell)` | `ColorPickerView` writes `sender.color` into `viewModel.color` unchanged — no clamping call appears in `ColorPickerView.swift`; any normalization happens inside `RGBAColor`'s initializer, one layer below |
