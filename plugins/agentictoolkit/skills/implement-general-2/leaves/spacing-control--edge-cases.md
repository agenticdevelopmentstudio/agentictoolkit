<!-- leaf: implement-general-2/spacing-control--edge-cases · source: spacing-control.md -->

# SpacingControl

**Rules** (cite as `implement-general-2/spacing-control--edge-cases#<slug>`):

- `boundary-values-value-at-the-range-s-floor-or-ceiling` MUST — An arrow, stepper, drag, or committed field write MUST NOT move a value past range.lowerBound or range.upperBound; …
- `boundary-values-zero-width-gutter` MUST — At betweenColumns == 0 or betweenRows == 0 on .paneDividers, the diagram MUST still draw a 1pt hairline gutter …
- `boundary-values-value-assigned-outside-range` MUST — Assigning value directly to a number outside range MUST NOT be rejected or re-clamped by the control itself — value's …

## Edge Cases

- **Null/empty input**: `style` and `range` are non-optional typed
  initializer parameters; Swift's type system rules out `nil` for either,
  so the component needs no nil-handling path for them. `value` defaults to
  `Spacing()` (all-zero) when omitted.
- **Boundary values — value at the range's floor or ceiling**: An arrow,
  stepper, drag, or committed field write MUST NOT move a value past
  `range.lowerBound` or `range.upperBound`; every write path clamps through
  `Spacing.adjusting`/`Spacing.setting` (`Int.clamped(to:)`).
- **Boundary values — zero-width gutter**: At `betweenColumns == 0` or
  `betweenRows == 0` on `.paneDividers`, the diagram MUST still draw a
  `1pt` hairline gutter (`minimumDisplayedGutter`) rather than a zero-width
  one, so the four-pane picture stays legible at the floor of the range.
- **Boundary values — `value` assigned outside `range`**: Assigning `value`
  directly to a number outside `range` MUST NOT be rejected or re-clamped by
  the control itself — `value`'s `didSet` only compares for equality and
  redraws; only *user-driven* edits are clamped. The diagram's **displayed**
  extent for that number is still capped at `maximumDisplayedInset` (see
  caps-displayed-inset-at-maximum); the stepper showing that number is
  clamped to its own `minValue`/`maxValue` by `NSStepper` itself, which are
  set from `range` at construction.
- **Concurrent access**: Not applicable — `SpacingControl` is
  `@MainActor`-isolated; Swift's concurrency checker serializes all access
  to the main actor, and the drag-tracking loop (`SpacingHandle.track`) runs
  synchronously to completion on that same actor before returning.
- **Error states**: Not applicable — every operation in source (formatting,
  clamping, layout, drawing) is synchronous and non-throwing; no `try`,
  `Result`, or error-producing API appears anywhere in this file.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking of its own.
- **A still trackpad press is not silence**: `SpacingHandle.claimsPress`
  watches a press for `grace` (`0.12`s) of stillness before handing it back
  to the arrow underneath, but a resting trackpad delivers a steady trickle
  of sub-`slop` (`3pt`) jitter events, each of which would otherwise restart
  that wait forever. Source bounds the whole decision at `patience`
  (`0.3`s) regardless of how many such events arrive, so a held-still press
  on a trackpad still resolves and reaches the arrow's own repeat behavior,
  the same as a mouse's genuinely-silent hold does after `grace` alone. This
  is a documented, source-traceable fix for a real platform difference, not
  a hypothetical.
- **A field's mid-edit text is not clobbered by a sibling's change**: A
  field currently being edited keeps its field editor's uncommitted text
  when a *different* field's value changes and triggers `sync()`; only the
  field whose own number moved, or the field just committed (`forcing:`),
  has its text rewritten (`show(_:in:force:)`).
