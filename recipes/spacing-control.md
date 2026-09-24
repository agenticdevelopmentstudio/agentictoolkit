---
id: f064de5a-b117-4147-96a9-c1ed11d5c976
title: SpacingControl
domain: agentictoolkit://recipes/spacing-control
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS control that draws a small picture of a view's insets or a pane grid's
  gutters, and lets the user edit those numbers by typing, by stepper, by clicking
  an arrow, or by dragging the line the arrow stands on.
platforms:
- swift
- macos
tags:
- spacing
- settings
- form-control
- range
- appkit
depends-on: []
related:
- agentictoolkit://recipes/pane-spacing
- agentictoolkit://recipes/composable-tabs-settings-view-controller
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
- agentictoolkit://recipes/captioned-slider-view
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

- **Corner radius**: None. The outer frame and every pane are drawn as plain
  rectangles (`NSBezierPath(rect:)`); no rounded-rect path or `cornerRadius`
  appears anywhere in source.
- **Padding**: Not a single vertical × horizontal pair — the whole control
  *is* a spacing editor, and its own outer padding is the fixed chrome
  reserved around the diagram for what hangs off it: `Metrics.chrome`
  (`SpacingControlLayout.swift`) = arrow length (`18pt`) + arrow gap (`2pt`)
  + one field group's width/height (`40 + 2 + 13 = 55pt` wide, `21pt` tall),
  i.e. `75×41pt` on each side of the diagram (`diagramInset`). Within that,
  an arrow's box sits `9pt` (half an arrow length, `attachment`) from the
  line it moves, and a divider's two arrow pairs stand `8pt`
  (`pairOffset` = half arrow breadth + half arrow gap) either side of the
  divider's own centre line.
- **Font**: Number fields use the palette's `.code` text style
  (`palette.font(.code)`) via `observeTheme`; the Reset button uses the
  palette's `.body` text style (`palette.font(.body)`). Neither font size is
  a literal in this file — both are theme tokens resolved by
  `SemanticPalette`, out of this file's scope, and both repaint on a theme
  change.
- **Background**: The outer frame is filled with `palette.projectPaneBackdrop`
  (converted via `NSColor(_:)`); each pane (one for `.frame`, four for
  `.paneDividers`) is filled with `palette.nsColor(.windowBackground)`. Both
  are theme tokens, not literal colors.
- **Foreground/Text**: Number field text uses `palette.nsColor(.primaryText)`.
  Arrow glyphs are tinted with `palette.nsColor(.accent)`
  (`contentTintColor`). Neither is a literal color.
- **Border**: The outer frame is stroked `1pt` with `palette.nsColor(.border)`;
  each pane is stroked `1pt` with `NSColor(palette.projectPaneOutline)`. Both
  paths are inset `0.5pt` on each side (`insetBy(dx: 0.5, dy: 0.5)`) so a
  `1pt` stroke draws crisply on a non-Retina-scaled edge.
- **Shadow**: None. No `NSShadow` or layer shadow appears anywhere in
  source.
- **Min/Max size**: Fixed intrinsic size `420×250pt`
  (`controlSize`/`intrinsicContentSize`); minimum size is the larger of two
  floors — three field groups across/down
  (`fieldGroupSize` `55×21pt` × 3, plus chrome), or the diagram's own floor
  for drawing the full range (`minimumDiagramSize`, tied to
  `maximumDisplayedInset` = `40pt` per side, plus chrome). The diagram
  expands to fill `bounds` above the minimum; no maximum is enforced, since
  `diagramRect` is measured from `bounds` on every layout pass.

## States

| State | Appearance change |
|-------|------------------|
| Default | Shows the current value's numbers in every field/stepper and the matching diagram (`sync()`); redraws and re-lays-out whenever `value` changes (`needsDisplay`/`needsLayout`). |
| Dragging | A grabbed `SpacingHandle` reports pointer travel on every mouse-dragged event (`onDrag`); the control applies the resulting value, then forces an immediate layout and display (`layoutSubtreeIfNeeded()`/`displayIfNeeded()`) so the diagram tracks the pointer within the same run-loop turn rather than waiting for AppKit's own next display cycle. |
| Pressed | A pressed arrow (`ArrowButton.isPressed`) repeats its one-point adjustment on a `0.45`s delay / `0.06`s interval (`setPeriodicDelay`), and its pair's handle is not re-seated while it is pressed (`seat(_:holding:)`'s `holdsPressedArrow` guard), so the button does not slide out from under a held-down pointer mid-repeat. |
| Disabled | Not applicable: `isEnabled` is never set on any subview in source; the control has no disabled appearance or behavior. |
| Focused | A focused number field keeps whatever the user has typed until editing ends (`controlTextDidEndEditing`); Tab/Shift-Tab (`insertTab`/`insertBacktab`) moves focus to the next/previous field in picture order rather than AppKit's inferred key-view loop, and Up/Down (`moveUp`/`moveDown`) adjusts that field's value by one point. |
| Loading | Not applicable: the component performs no asynchronous operation in source. |

## Accessibility

- **Role/trait**: The control sets `setAccessibilityElement(true)` and
  `setAccessibilityRole(.group)` on itself, so it is exposed to VoiceOver as
  one group rather than as four or two loose fields, depending on `style`,
  belonging to nothing (see the type-level doc comment). Every field,
  stepper, arrow button, reset button, and drag handle also carries an
  `accessibilityIdentifier` via the shared `accessibilityID(_:)` helper
  (e.g. `spacing.top`, `spacing.edge.top.more`,
  `spacing.gutter.betweenColumns.narrower.handle`) — these are UI-test
  identifiers (`setAccessibilityIdentifier`), not VoiceOver labels.
- **Label requirements**: The four or two number fields
  (`edgeFields`/`gutterFields`, depending on `style`) and their steppers
  carry no `setAccessibilityLabel`/`setAccessibilityTitleUIElement` call
  anywhere in source — only a numeric value and a test identifier — so a
  VoiceOver user landing on one hears its number with no indication of
  which edge or gutter it belongs to. The arrow buttons are not part of
  this gap: each is built from an
  `NSImage(systemSymbolName:accessibilityDescription:)` whose
  `accessibilityDescription` is the same string as its tooltip (e.g. "More
  top space"), which VoiceOver reads as the button's label. This mirrors
  the same control-to-title linkage gap already noted on the sibling
  ingredient `CaptionedSliderView`
  (`agentictoolkit://recipes/captioned-slider-view#accessibility/label-requirements`).
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading or disabled state (see States) for a change to
  announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition with no touch input path
  in source; the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. Every color this file draws for text or a tint comes from a `SemanticPalette` role — field text (`palette.nsColor(.primaryText)`), arrow glyphs (`palette.nsColor(.accent)`), the outer frame's stroke (`palette.nsColor(.border)`) against `palette.projectPaneBackdrop`, and each pane's stroke (`palette.projectPaneOutline`) against `palette.nsColor(.windowBackground)`) — none of which carry a guaranteed contrast floor in `SemanticPalette.derive(_:theme:)` (`.primaryText` returns the theme's raw foreground, `.accent` returns a raw ANSI slot or the raw foreground, and `.border` blends foreground into background at a fixed 0.18 fraction, unlike `.secondaryText`'s `minContrast: 3.0`), and no check anywhere in `SpacingControl.swift` verifies any of those pairs against the 4.5:1 (text) / 3:1 (non-text) floor; settling it needs a theme-level contrast audit of `SemanticPalette`'s roles against real theme values (see also Accessibility Options: Increase Contrast).

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `style` | `SpacingDiagram` (`.frame` \| `.paneDividers`) | — (required) | Selects which subset of `Spacing` the control builds fields, steppers, arrows, and handles for, and which diagram it draws: the four edges (`.frame`) or the two gutters (`.paneDividers`). |
| `value` | `Spacing` | `Spacing()` (all zero) | The numbers currently shown. Assigning it redraws the control but does not invoke `onChange`. |
| `range` | `ClosedRange<Int>` | `0...40` | The floor and ceiling every user-driven edit is clamped to; also sets each stepper's `minValue`/`maxValue`. |
| `onChange` | `((Spacing) -> Void)?` | `nil` | Invoked once per user-driven edit that changes `value` (see fires-onchange-only-on-user-edit / skips-redundant-onchange). Not invoked by assigning `value` directly. |
| `SpacingControl.boundToSettings(style:edges:gutters:range:)` | static factory | — | Not a constructor parameter of `SpacingControl` itself, but the documented way every caller in this framework obtains one: builds a control, then attaches a `SpacingSettingsBinding` (a separate file, out of this recipe's scope) that seeds it from, and keeps it synced with, the given `UserSetting<Int>` values. `edges` (for `.frame`) or `gutters` (for `.paneDividers`) needs to be non-empty for the matching style; `SpacingSettingsBinding.swift`'s own `precondition` traps when it is empty. |

## Deep Linking

Not applicable: `SpacingControl` is an in-panel editing control, not a
navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `SpacingControl.swift`.

## Localization

Every user-facing string below is an AppKit `String` literal assigned to
`toolTip`, `title`, or an `NSImage`'s `accessibilityDescription` — never a
`LocalizedStringKey`, `NSLocalizedString`, or a String Catalog lookup — so
none of them can be localized without a source change; each would need a
localization key routed through this app's existing localization
mechanism, the same way any other user-facing AppKit string in the
framework is externalized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | "Top" / "Left" / "Bottom" / "Right" | `SpacingEdge.displayName`, used inside every edge's field/arrow tooltip |
| (none — literal) | "{Edge} — points between the edge and what is inside it" | Tooltip on an edge's number field and stepper |
| (none — literal) | "More {edge} space" / "Less {edge} space" | Tooltip, and the arrow image's accessibility description, on an edge's grow/shrink arrows |
| (none — literal) | "side-by-side panes" / "stacked panes" | `SpacingGutter.displayName`, used inside a gutter's arrow tooltip |
| (none — literal) | "Points between two panes side by side. The gap is shared, so this is the whole gap." / the row-stacked equivalent | Tooltip on a gutter's number field and stepper |
| (none — literal) | "Narrower gap between {panes}" / "Wider gap between {panes}" | Tooltip, and accessibility description, on a gutter's narrow/wide arrows |
| (none — literal) | "Reset" | Reset button title |
| (none — literal) | "Set every number here back to zero" | Reset button tooltip |

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext`/`animator()` call; every redraw and
  layout pass (`needsDisplay`, `needsLayout`) is an instantaneous property
  assignment applied on the next display cycle, so there is no motion for a
  Reduce Motion substitute to replace.
- **Increase Contrast**: See the open question on minimum-contrast-ratio —
  `SemanticPalette`
  (`external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/Sources/Theme/SemanticPalette.swift`)
  exposes no Increase-Contrast-aware variant of the tokens this file draws
  from, on top of the baseline contrast question raised there; extending
  `SemanticPalette` to derive a higher-contrast border/fill pair from
  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` would settle
  both.
- **Differentiate Without Color**: Not applicable — the only information
  this control conveys beyond its numbers (which way an arrow moves a line)
  is carried by arrow-glyph shape and screen position; every arrow shares
  the same accent tint (`contentTintColor`) regardless of direction, so
  there is no color-only signal to duplicate.

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears
anywhere in `SpacingControl.swift`.

## Analytics

Not applicable: no analytics or telemetry call appears anywhere in
`SpacingControl.swift`.

## Privacy

- **Data collected**: None beyond the spacing numbers themselves — window/
  pane layout preferences, not personal or sensitive data — and this file
  only holds them in memory as `value`.
- **Storage**: Not applicable to this file — `SpacingControl` performs no
  read or write to disk, `UserDefaults`, or any other store. Persistence,
  when the control is used via `SpacingControl.boundToSettings`, is owned
  by `SpacingSettingsBinding` writing to `UserSetting<Int>`, a separate
  type outside this recipe's scope (see `pane-spacing` for one such
  settings-backed store).
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: Not applicable within this file — the view retains only
  its own subviews, its `value`, and (when bound) its
  `retainedBinding`, for its own lifetime; it persists nothing beyond that
  itself.

## Logging

Not applicable: `SpacingControl.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Model `Spacing` as an `@Binding` (or an `ObservableObject`)
  and draw the diagram with a `Canvas`/layered `Rectangle` shapes inside a
  fixed `.frame(width: 420, height: 250)`, applying the same `minimumSize`
  floor via `.frame(minWidth:minHeight:)` to mirror
  clips-below-minimum-size. Represent each arrow as a borderless `Button`
  with an SF Symbol `Image` (`"arrow.up"`, etc.) tinted `.accentColor`;
  SwiftUI's `Button` has no built-in continuous/periodic action, so
  mirroring repeats-held-arrow needs a `DispatchSourceTimer` (or a
  `Timer`) started on `.onLongPressGesture(minimumDuration: 0,
  pressing:)`'s press phase, at the same `0.45`s delay / `0.06`s interval.
  Bind each number to a `TextField` with a numeric `Formatter`, committing
  on `.onSubmit` to mirror commits-field-on-editing-end, and drive each
  handle with a `DragGesture(minimumDistance: 0)` measuring `.translation`
  from the gesture's start, applying the same 1:1 (edge) / 2:1 (gutter)
  gains.
- **Compose**: Draw the diagram with `Canvas`, sized
  `Modifier.size(420.dp, 250.dp)` with a `Modifier.sizeIn(minWidth =,
  minHeight =)` floor mirroring clips-below-minimum-size. Use `IconButton`s
  with `Icons.Filled.ArrowUpward`/etc. tinted via `MaterialTheme
  .colorScheme.primary` (the accent-tint analog), driving repeats-held-arrow
  with `Modifier.pointerInput` detecting `awaitFirstDown()` followed by a
  coroutine `while (isPressed) { delay(...); adjust(); }` loop at the same
  `450`ms/`60`ms cadence. Use `BasicTextField` with numeric
  `KeyboardOptions`, committing on `ImeAction.Done` or focus loss to
  mirror commits-field-on-editing-end, and `Modifier.draggable` (per
  handle, `Orientation.Horizontal`/`Vertical`) recording the value at drag
  start and accumulating each `onDelta` into a running total displacement —
  never applying a delta straight to the value — then computing
  `value = startValue + gain × totalDisplacement` on every callback, to
  mirror "measured from the value at drag start, not accumulated step by
  step".
- **React/Web**: Render the diagram as absolutely-positioned elements (or
  inline SVG) inside a fixed `420×250px` container with a `min-width`/
  `min-height` floor mirroring clips-below-minimum-size. Represent each
  arrow as a `<button>` with an SVG chevron tinted via `currentColor`/an
  accent CSS variable, driving repeats-held-arrow with `setInterval`
  (`450`ms initial delay, then a `60`ms interval, cleared on
  `pointerup`/`pointerleave`). Use an `<input>` that commits on `blur`/
  `Enter` (mirroring commits-field-on-editing-end) rather than on every
  `input` event, and a `pointerdown`-installed/`pointerup`-removed
  `pointermove` listener per handle that records the pointer's client
  position and the value at `pointerdown`, then on each `pointermove`
  computes the total displacement from that start position — not
  accumulated `movementX`/`movementY` deltas — and applies the same
  1:1/2:1 gains to it, to mirror "measured from the value at drag start,
  not accumulated step by step".
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/UI/Controls/Spacing/SpacingControl.swift`,
  with two companions this recipe also draws from:
  `Spacing.swift` (the `Spacing` value type and the `SpacingEdge`/
  `SpacingGutter`/`SpacingArrow`/`SpacingAxis` enums it edits) and
  `SpacingControlLayout.swift` (the pure, view-independent geometry — chrome
  metrics, pane/gutter rects, arrow/field anchor points). macOS-only
  (`import AppKit`); there is no UIKit code path in source, and no
  touch-input handling to port. A UIKit/iOS port would need to redesign the
  hold-to-repeat arrows and the drag handles for touch
  (`UILongPressGestureRecognizer`/`UIPanGestureRecognizer`), since
  AppKit's `NSEvent`-loop-based tracking (`SpacingHandle.track(from:)`,
  `claimsPress`) has no UIKit equivalent.
- **WinUI 3**: Build the diagram as a
  `Canvas` (or a `Grid` of `Border` elements for the container/panes)
  inside a `UserControl` with `Width="420" Height="250"` and a `MinWidth`/
  `MinHeight` floor mirroring clips-below-minimum-size. Draw the outer
  frame and panes as `Border`/`Rectangle` elements whose `Background`/
  `BorderBrush` are bound to `ThemeResource` brushes mirroring
  `SemanticPalette`'s `.border`/`.windowBackground`/project-pane tokens —
  never a literal `Color`, matching this file's theme-token-only-colors
  discipline. Represent each arrow as a chrome-less `Button`
  (`Background="Transparent" BorderThickness="0"`) hosting a `FontIcon`/
  `PathIcon` glyph tinted with an accent `ThemeResource`; WinUI's
  `RepeatButton` (with its own `Delay`/`Interval` properties) is a closer
  built-in match for repeats-held-arrow than a plain `Button` plus a
  hand-rolled `DispatcherTimer`, and should replace it outright, configured
  to the same `450`ms delay / `60`ms interval. Bind each number to a
  `NumberBox` (`SpinButtonPlacementMode="Compact"` supplies the stepper for
  free) with `Minimum`/`Maximum` bound to `range`, committing via
  `ValueChanged` only after `LostFocus`/Enter to mirror
  commits-field-on-editing-end. `NumberBox`'s built-in
  `ValidationMode="InvalidInputOverwritten"` only reverts to the previous
  value on any unparseable text, which is not the full analog of
  recovers-unparseable-field-text: that requirement still wants the
  *clamped* typed number when one can be parsed — even from an out-of-range
  or partially-numeric string — and falls back to the held number only when
  nothing parses at all. Closing that gap needs a custom `TextSubmitted`
  handler that parses the typed text itself, clamps a successful parse to
  `range`, and reverts to the held number only when parsing fails outright.
  Implement the drag handles with `ManipulationMode="TranslateX,TranslateY"`
  and a `ManipulationDelta` handler computing the same 1:1 (edge) / 2:1
  (gutter) gains, and route `KeyDown` (`VirtualKey.Up`/`Down`) plus
  explicit `TabIndex` ordering (top/leading/trailing/bottom, or gutter
  order) across the `NumberBox`es to mirror tab-order-is-picture-order and
  arrow-keys-adjust-focused-field, since WinUI's default tab-index
  navigation cannot infer the picture's reading order from `Canvas`-based
  placement any more than AppKit's inferred key-view loop could from
  frame-based placement.

## Design Decisions

- **Decision**: Keep the range's floor and ceiling out of the fields'
  `NumberFormatter` and clamp only inside `Spacing.setting(_:in:)`/
  `Spacing.adjusting(_:by:in:)`.
  **Rationale**: the source comment on `makeField` explains that a
  `NumberFormatter` with a `maximum` refuses out-of-range text outright
  rather than clamping it, and AppKit answers that refusal by declining to
  end editing — trapping the caret in an emptied field. `Spacing` is the
  one place that can clamp instead of reject.
  **Approved**: pending
- **Decision**: Give arrow buttons and steppers `refusesFirstResponder = true`,
  keeping Tab limited to the four or two number fields, depending on
  `style`.
  **Rationale**: the source comments on `makeStepper`/`makeArrowButton` state
  that a stepper or an arrow in the tab loop would put extra stops between
  two number fields — Tab is for the numbers.
  **Approved**: pending
- **Decision**: Intercept Tab explicitly inside `control(_:textView:doCommandBy:)`
  rather than relying on AppKit's inferred key-view loop, and only within
  the control — at either end, focus is handed back to whatever
  `nextKeyView` the panel wired up.
  **Rationale**: the source comment explains that this control's subviews are
  frame-placed, not constraint-placed, so AppKit's inferred loop would
  thread the control's numbers in among whatever else the panel shows; a
  closed ring was considered and rejected as a focus trap.
  **Approved**: pending
- **Decision**: Bound `SpacingHandle.claimsPress`'s wait at `patience` (`0.3`s)
  in addition to the per-event `grace` (`0.12`s).
  **Rationale**: the source comment explains a resting trackpad delivers a
  steady trickle of sub-`slop` jitter events that each restart an unbounded
  `grace` timer, making a held-still arrow's repeat unreachable on a
  trackpad (though reachable on a mouse, which is genuinely silent);
  bounding the total wait fixes the trackpad case without shortening the
  mouse case.
  **Approved**: pending
- **Decision**: Scale the diagram 1:1 with the value, capped at
  `maximumDisplayedInset` (`40pt`), rather than compressing the whole range
  into a smaller diagram.
  **Rationale**: the source comment on `maximumDisplayedInset` explains that an
  arrow standing against the edge it moves travels with that edge; at a
  smaller display scale, a pressed arrow could slide most of its own length
  out from under a held pointer and stop repeating before the range ended.
  The 1:1 cap, paired with freezing a pressed pair's seat
  (freezes-pressed-arrow-pair), is what keeps a full-range hold under the
  pointer.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | platform-compliance |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

Separation-of-concerns passes because the control holds only a `Spacing`
value and an `onChange` closure, with all settings/persistence concerns
pushed to `SpacingSettingsBinding`, a separate type (per the type's own doc
comment). Platform-theming passes because every color this file paints
comes from `SemanticPalette` tokens, never a raw literal.
Native-controls-preference and platform-design-language pass because number
entry uses stock `NSTextField`/`NSStepper`, and Reset uses a stock
`NSButton` with the standard rounded/small bezel. Keyboard-navigable passes
because every number is reachable and editable by Tab plus the arrow keys
(tab-order-is-picture-order, arrow-keys-adjust-focused-field).
Screen-reader-support is partial because the arrow buttons carry an
accessible description but the number fields and steppers do not (see
Accessibility: Label requirements). Contrast-ratio is partial because the
diagram's borders and fills are theme-token-driven but have no verified or
Increase-Contrast-aware path (see the open question on
minimum-contrast-ratio). String-externalization fails because every
user-facing string in this file is a hardcoded literal with no
localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `SpacingControl.swift` (with `Spacing.swift` and `SpacingControlLayout.swift` consulted for the value type, enums, and layout metrics it uses): behavioral requirements for both diagram styles, drag/keyboard/arrow-repeat interaction, appearance and states, and two open questions (number-field VoiceOver labeling, Increase Contrast support) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: added a per-edge drag axis/gain/growing-direction table; cited the CaptionedSliderView accessibility fragment in `related`; reworded the `boundToSettings` Configuration row to drop its unscoped MUST; trimmed `tags` to five and moved `references` into `related`; reformatted Design Decisions to bold labels; cleaned up the Compliance table to real catalog checks, remapping `theme-token-only-colors` to `platform-theming` and renaming `meaningful-labels`/`non-text-contrast` to their catalog names; removed commentary from the WinUI Platform Notes bullet; fixed the `style` row's backwards field-count description and the eight-field miscount throughout; rewrote Conformance Test Vectors 020 and 024 for validity and added vector 027 for a gutter drag crossing centre; tightened `repeats-held-arrow`, `preserves-other-fields-mid-edit`, and `drags-gutter-two-to-one-outward` for precision; corrected the React and Compose Platform Notes to record drag-start position/value instead of accumulating deltas, and noted the WinUI NumberBox revert gap; clarified the diagram's min/max Appearance note and the Null/empty input Edge Case; and added an open question on minimum contrast ratio for the theme-token colors this control draws. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
