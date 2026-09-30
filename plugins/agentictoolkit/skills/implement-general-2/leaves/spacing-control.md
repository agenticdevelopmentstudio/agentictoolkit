<!-- leaf: implement-general-2/spacing-control · source: spacing-control.md -->

**Rules** (cite as `implement-general-2/spacing-control#<slug>`):

- `renders-diagram-for-style` MUST
- `fires-onchange-only-on-user-edit` MUST
- `skips-redundant-onchange` MUST
- `clamps-user-edits-to-range` MUST
- `commits-field-on-editing-end` MUST
- `recovers-unparseable-field-text` MUST
- `repeats-held-arrow` MUST
- `freezes-pressed-arrow-pair` MUST
- `drags-edge-one-to-one` MUST
- `drags-gutter-two-to-one-outward` MUST
- `arrow-points-in-line-travel-direction` MUST
- `resets-only-visible-numbers` MUST
- `tab-order-is-picture-order` MUST
- `arrow-keys-adjust-focused-field` MUST
- `preserves-other-fields-mid-edit` MUST
- `reflects-forced-field-after-commit` MUST
- `group-accessibility-container` MUST
- `rejects-coder-initialization` MUST
- `reports-fixed-intrinsic-size` MUST
- `clips-below-minimum-size` MUST
- `repaints-on-theme-change` MUST
- `caps-displayed-inset-at-maximum` MUST

# SpacingControl

## Overview

`SpacingControl` (`packages/apple/AgenticToolkit/macOS/UI/Controls/Spacing/SpacingControl.swift`)
is an `NSView` that draws a small diagram of the thing being spaced and lets
the user edit the numbers that shape it. It has two flavors selected by
`style: SpacingDiagram`, same size, same chrome, same code: `.frame` draws one
view inside its container with the four edge insets (`top`, `leading`,
`bottom`, `trailing`) that separate them; `.paneDividers` draws four panes and
the two gutters between them (`betweenColumns`, `betweenRows`). Every number
carries a text field, a stepper, and a pair of arrow buttons standing on the
line they move — pointing the direction that line travels when pressed — plus
a draggable handle wrapping that pair so the same line can be dragged
directly. A "Reset" button zeroes only the numbers the current flavor shows.
The control knows nothing about settings or persistence: it holds a `Spacing`
value and reports user-driven changes through `onChange`; `SpacingSettingsBinding`
and the `SpacingControl.boundToSettings(style:edges:gutters:range:)` factory
(`SpacingSettingsBinding.swift`, a separate file, out of this recipe's scope)
are what tie a control to `UserSetting<Int>` values so it can be dropped into
a settings panel in one expression — `PaneSpacing`'s `edgeSettings`/
`gutterSettings` and `ComposableTabsSettingsViewController` are two concrete
callers, cited here for traceability.

Use this ingredient wherever a settings surface needs to let a user tune
one or more edge insets, or the gutters of a pane grid, with a control that
shows *which* number changes *which* edge without a separate diagram or a
column of unlabeled fields.

## Behavioral Requirements

- **renders-diagram-for-style**: Component MUST render a `.frame` diagram
  (one view inside its container, four edge insets) when constructed with
  `style: .frame`, and a `.paneDividers` diagram (four panes, two gutters)
  when constructed with `style: .paneDividers`.
- **fires-onchange-only-on-user-edit**: Component MUST invoke `onChange` when,
  and only when, `value` changes as the result of a user-initiated edit — an
  arrow click, a stepper change, a committed text field, an arrow-key press
  on a focused field, a drag, or Reset. Component MUST NOT invoke `onChange`
  when `value` is assigned directly.
- **skips-redundant-onchange**: Component MUST NOT invoke `onChange`, and
  MUST NOT redraw or re-lay-out, when a user interaction computes a value
  equal to the value already held (`apply(_:)`'s equality guard).
- **clamps-user-edits-to-range**: Every user-driven write — an arrow click,
  a stepper change, a committed or in-progress typed number, or a drag — MUST
  be clamped to `range` (default `0...40`) before it is applied.
- **commits-field-on-editing-end**: Component MUST commit a text field's
  typed number to the corresponding edge or gutter only when editing ends
  (Return, Tab, or clicking away), and MUST NOT commit on every keystroke.
- **recovers-unparseable-field-text**: When a field's typed text fails to
  parse as a whole number, Component MUST replace the field's displayed text
  with a valid number — the clamped typed number if any number could be
  parsed from it, otherwise the number already held for that field — so
  editing can always end.
- **repeats-held-arrow**: An arrow button MUST adjust its value once
  immediately on press, then MUST repeat that one-point adjustment starting
  `0.45` seconds after the button is pressed and every `0.06` seconds while
  it continues to be held.
- **freezes-pressed-arrow-pair**: Component MUST NOT re-seat (move) an
  arrow pair while one of its own arrows is pressed, even when a layout pass
  is triggered by some other number changing.
- **drags-edge-one-to-one**: Dragging an edge's handle MUST change that
  edge's value by one point per point the pointer has travelled along the
  edge's drag axis since the drag began, signed per that edge's `dragGain`
  (measured from the value at drag start, not accumulated step by step).
- **drags-gutter-two-to-one-outward**: Dragging a gutter's handle MUST
  change that gutter's value by two points per point the pointer has
  travelled along the divider's `dragAxis` since the drag began, measured
  from the value and pointer position at drag start. The sign is fixed once,
  by which side of the divider's centre the pointer's initial grab point
  fell on: if the drag began on the negative side of centre, travel further
  in the negative direction increases the value; if it began on the
  positive side, travel further in the positive direction increases the
  value. That sign does not flip if the pointer later crosses the centre —
  travel back past centre continues to decrease the value using the same
  fixed sign.
- **arrow-points-in-line-travel-direction**: Each arrow MUST point in the
  direction the line it controls travels when pressed — the edge/pane-edge's
  `growing` direction for the arrow that adds room, and the opposite
  direction for the arrow that removes it.
- **resets-only-visible-numbers**: The Reset control MUST, in a single value
  update, set to zero exactly the numbers the current `style` shows — the
  four edges for `.frame`, the two gutters for `.paneDividers` — and MUST NOT
  change any number the current style does not show.
- **tab-order-is-picture-order**: Tab and Shift-Tab MUST move focus only
  among the control's number fields, in the order top, leading, trailing,
  bottom for `.frame` or the gutter enumeration order for `.paneDividers`,
  and MUST NOT include a stepper or an arrow button in that order.
- **arrow-keys-adjust-focused-field**: With a number field focused, the Up
  arrow key MUST increase and the Down arrow key MUST decrease that field's
  value by one point (clamped to `range`); the Left and Right arrow keys
  MUST be left for caret movement within the field's text.
- **preserves-other-fields-mid-edit**: Component MUST NOT overwrite the
  on-screen text of a field that is currently being edited when any other
  field's number changes while this field is being edited.
- **reflects-forced-field-after-commit**: After a field's typed value is
  committed, Component MUST re-display that field's number even when the
  clamped result equals the number already held, so a typed out-of-range
  number is visibly shown snapping back.
- **group-accessibility-container**: Component MUST expose itself to
  accessibility as a single group element (`accessibilityElement == true`,
  role `.group`) rather than exposing its subviews directly to whatever
  container it is placed in.
- **rejects-coder-initialization**: Component MUST NOT support construction
  via `init(coder:)`; that initializer MUST trigger a fatal error.
- **reports-fixed-intrinsic-size**: `intrinsicContentSize` MUST report a
  fixed `420×250` point size regardless of `style` or the current value.
- **clips-below-minimum-size**: When given less room than `minimumSize`
  (derived from the chrome metrics and either three field groups across or
  the diagram's own floor, whichever is larger), Component MUST stop
  shrinking its diagram and subviews at that floor rather than continuing to
  compress them, even if that places some subviews outside `bounds`.
- **repaints-on-theme-change**: Component MUST re-fetch its drawn colors
  (frame fill, pane fill, borders) and its field/reset fonts from the active
  theme's palette, and redraw, whenever the active theme's palette changes —
  without being reconstructed.
- **caps-displayed-inset-at-maximum**: The diagram MUST draw any single
  edge's or gutter's extent no larger than `maximumDisplayedInset` (`40`
  points), even when `value` holds a larger number for it.

Per-edge drag axis, gain sign, and growing direction, so a port can implement
`drags-edge-one-to-one` and `arrow-points-in-line-travel-direction` without
reading `Spacing.swift`:

| Edge | Drag axis | Gain sign | `growing` direction |
|------|-----------|-----------|----------------------|
| `top` | vertical | `-1` (dragging down grows the inset) | `.down` |
| `bottom` | vertical | `+1` (dragging up grows the inset) | `.up` |
| `leading` | horizontal | `+1` (dragging right grows the inset) | `.right` |
| `trailing` | horizontal | `-1` (dragging left grows the inset) | `.left` |

Both gutters use a fixed gain of `2` (not signed per gutter — the sign for a
gutter drag instead comes from which side of the divider's centre the drag
began, per `drags-gutter-two-to-one-outward`).

