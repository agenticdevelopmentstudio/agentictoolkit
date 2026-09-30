<!-- leaf: implement-general-2/spacing-control--test-vectors · source: spacing-control.md -->

# SpacingControl

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| spacing-control-001 | renders-diagram-for-style | Construct with `style: .frame` | The view builds edge fields/steppers/arrows/handles for all four `SpacingEdge` cases and no gutter controls |
| spacing-control-002 | renders-diagram-for-style | Construct with `style: .paneDividers` | The view builds gutter fields/steppers/arrows/handles for both `SpacingGutter` cases and no edge controls |
| spacing-control-003 | fires-onchange-only-on-user-edit | Click the "more" arrow for `.top` | `onChange` is invoked once, with `value.top` increased by 1 |
| spacing-control-004 | fires-onchange-only-on-user-edit | Assign `control.value = Spacing(top: 5)` directly | `onChange` is not invoked |
| spacing-control-005 | skips-redundant-onchange | `value.top == range.upperBound`; click the "more" arrow for `.top` again | `onChange` is not invoked; `value` is unchanged |
| spacing-control-006 | clamps-user-edits-to-range | `range = 0...40`, `value.top == 40`; click the "more" arrow for `.top` | `value.top` remains `40` |
| spacing-control-007 | clamps-user-edits-to-range | Type `"999"` into the top field and press Return | `value.top == 40` (clamped), and the field displays `40` |
| spacing-control-008 | commits-field-on-editing-end | Type `"7"` into the top field without pressing Return, Tab, or clicking away | `value.top` is unchanged |
| spacing-control-009 | commits-field-on-editing-end | Type `"7"` into the top field, then press Return | `value.top == 7` |
| spacing-control-010 | recovers-unparseable-field-text | Type `"abc"` into a field holding `5`, then attempt to end editing | `control(_:didFailToFormatString:errorDescription:)` returns `true`; the field's text becomes `"5"`; editing ends without a trap |
| spacing-control-011 | repeats-held-arrow | Press and hold the "more" arrow for `.top` for 1 second | The value increases once at press, not again until `0.45`s elapses, then once more every `0.06`s thereafter |
| spacing-control-012 | freezes-pressed-arrow-pair | Hold the "more" arrow for `.top` while a different field's value changes, triggering `sync()`/`needsLayout` | The held arrow's pair is not moved/re-seated while `isPressed == true` |
| spacing-control-013 | drags-edge-one-to-one | `style: .frame`; begin a drag on the `.top` handle, then move the pointer `10pt` along its drag axis | `value.top` changes by `10 * dragGain` points from its value at drag start |
| spacing-control-014 | drags-gutter-two-to-one-outward | `style: .paneDividers`; begin a drag on `.betweenColumns`'s handle from the near side of centre, then move the pointer `5pt` further from centre | `value.betweenColumns` increases by `10` points from its value at drag start |
| spacing-control-015 | arrow-points-in-line-travel-direction | Inspect the `.top` edge's two arrow buttons' `arrowDirections` | The "more" arrow is `.down` (`top.growing`) and the "less" arrow is `.up` (`top.shrinking`) |
| spacing-control-016 | resets-only-visible-numbers | `style: .frame`, all four edges and both gutters nonzero (gutters set directly on `value`); click Reset | All four edges become `0` in one `onChange`; `value.betweenColumns`/`betweenRows` are unchanged |
| spacing-control-017 | tab-order-is-picture-order | `style: .frame`; focus the top field, press Tab three times | Focus visits leading, then trailing, then bottom, in that order, never a stepper or arrow button |
| spacing-control-018 | arrow-keys-adjust-focused-field | Focus the top field (`value.top == 5`), press the Up arrow key | `value.top == 6`; the Left/Right arrow keys instead move the caret and do not change `value.top` |
| spacing-control-019 | preserves-other-fields-mid-edit | Begin typing `"1"` (uncommitted) into the leading field, then click the "more" arrow for `.top` | The leading field's on-screen, uncommitted text remains `"1"`; the top field's displayed number updates |
| spacing-control-020 | reflects-forced-field-after-commit | `value.top == 40`; type `"999"` into the top field (clamps to `40`, the value already held) and press Return | The field displays `40` immediately after commit, even though the clamped result equals the value already held |
| spacing-control-021 | group-accessibility-container | Inspect the constructed view's accessibility properties | `isAccessibilityElement() == true` and `accessibilityRole() == .group` |
| spacing-control-022 | rejects-coder-initialization | Call `SpacingControl(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| spacing-control-023 | reports-fixed-intrinsic-size | Construct with either `style` and any `value` | `intrinsicContentSize == NSSize(width: 420, height: 250)` |
| spacing-control-024 | clips-below-minimum-size | Constrain the view's `bounds` to `100×100pt`, well under `minimumSize` (`315×183pt`) | `diagramRect`'s size equals `minimumSize` minus `2 × diagramInset` (`315×183` − `2×(75×41)` = `165×101pt`), not `bounds`'s size (`100×100pt`); subviews are placed from that floor, not compressed further |
| spacing-control-025 | repaints-on-theme-change | Change the active theme's palette after construction | The frame/pane fill and border colors, and the field/reset fonts, update to the new palette's values without reconstructing the view |
| spacing-control-026 | caps-displayed-inset-at-maximum | `range = 0...100` (custom), `value.top = 100` | The diagram draws the top inset at the same displayed extent as `value.top = 40` |
| spacing-control-027 | drags-gutter-two-to-one-outward | `style: .paneDividers`; begin a drag on `.betweenColumns`'s handle from the near side of centre, then move the pointer `20pt` toward and past the centre (a net displacement of `-20pt` along `dragAxis` from the grab point) | `value.betweenColumns` decreases by `40` points from its value at drag start — the sign stays fixed by the near-side start and does not flip when the pointer crosses the centre |
