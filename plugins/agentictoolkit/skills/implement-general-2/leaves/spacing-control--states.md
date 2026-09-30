<!-- leaf: implement-general-2/spacing-control--states · source: spacing-control.md -->

# SpacingControl

## States

| State | Appearance change |
|-------|------------------|
| Default | Shows the current value's numbers in every field/stepper and the matching diagram (`sync()`); redraws and re-lays-out whenever `value` changes (`needsDisplay`/`needsLayout`). |
| Dragging | A grabbed `SpacingHandle` reports pointer travel on every mouse-dragged event (`onDrag`); the control applies the resulting value, then forces an immediate layout and display (`layoutSubtreeIfNeeded()`/`displayIfNeeded()`) so the diagram tracks the pointer within the same run-loop turn rather than waiting for AppKit's own next display cycle. |
| Pressed | A pressed arrow (`ArrowButton.isPressed`) repeats its one-point adjustment on a `0.45`s delay / `0.06`s interval (`setPeriodicDelay`), and its pair's handle is not re-seated while it is pressed (`seat(_:holding:)`'s `holdsPressedArrow` guard), so the button does not slide out from under a held-down pointer mid-repeat. |
| Disabled | Not applicable: `isEnabled` is never set on any subview in source; the control has no disabled appearance or behavior. |
| Focused | A focused number field keeps whatever the user has typed until editing ends (`controlTextDidEndEditing`); Tab/Shift-Tab (`insertTab`/`insertBacktab`) moves focus to the next/previous field in picture order rather than AppKit's inferred key-view loop, and Up/Down (`moveUp`/`moveDown`) adjusts that field's value by one point. |
| Loading | Not applicable: the component performs no asynchronous operation in source. |
