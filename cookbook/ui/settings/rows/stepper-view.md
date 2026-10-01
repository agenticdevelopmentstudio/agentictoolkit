---
id: b02bf1ad-408a-4ebc-9e62-2ad5ae5220d2
title: Stepper View
domain: agentictoolkit://cookbook/ui/settings/rows/stepper-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a title label, a monospaced value label,
  and a stepper control bound to a bounded range view model.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
- numeric
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
- agentictoolkit://cookbook/ui/settings/rows/integer-field-view
- agentictoolkit://cookbook/ui/settings/rows/number-field-view
references: []
approved-by: ''
approved-date: ''
---

# Stepper View

## Overview

The Stepper View is a settings row: a title label leading, a monospaced
numeric value label, and a trailing stepper control, bound to a bounded
range view model. Per the source's own doc comment, it is for "small
bounded counts (recents, retry limits, etc.) where a slider's resolution
is wrong but a free text field is too unbounded." Unlike its sibling row
types (the checkbox row's switch, the integer field row's text field),
the stepper control draws no visible number of its own — only up/down
arrows — so this component pairs it with a separate value label that it
keeps in sync with the stepper's value on every change.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the label, the value
  label, and the stepper in that order in a single horizontal row and
  MUST pin that row to the edges of the view.
- **builds-label-from-view-model-title**: Component MUST build the label
  from the view model's title.
- **builds-value-label-monospaced**: Component MUST build the value
  label using a monospaced digit style.
- **resists-value-label-compression**: Component MUST set the value
  label's horizontal content compression resistance priority to
  required.
- **configures-stepper-bounds**: Component MUST set the stepper's
  minimum and maximum from the view model's minValue and maxValue.
- **fixes-stepper-increment**: Component MUST fix the stepper's
  increment at `1`, independent of the view model's range.
- **disables-stepper-wraparound**: Component MUST disable wraparound on
  the stepper.
- **initializes-stepper-value**: Component MUST set the stepper's value
  to the view model's value on construction.
- **initializes-value-label-text**: Component MUST set the value
  label's text to the string form of the view model's value on
  construction.
- **updates-value-label-on-change**: Whenever the stepper reports a
  change, component MUST set the value label's text to the string form
  of the stepper's new value, regardless of whether that value is
  committed.
- **commits-stepper-value**: Whenever the stepper reports a change and
  its new value differs from the view model's current value, component
  MUST write the new value into the view model's value.
- **skips-redundant-commits**: Component MUST NOT write to the view
  model's value when the stepper's new value equals its current value.
- **replaces-view-model-onchange**: Component's initializer MUST assign
  its own handler to the view model's change-notification callback,
  unconditionally replacing whatever handler (if any) was previously
  registered on that view model instance.
- **syncs-on-external-change**: Whenever the view model reports a
  change, component MUST re-set the label, the stepper's
  minimum/maximum, the stepper's value, and the value label's text from
  the view model.
- **exposes-constituent-views**: Component MUST expose the label, the
  stepper, and the value label as public, directly-accessible
  properties.
- **confines-to-ui-thread**: Component MUST be usable only on the UI
  thread; construction and mutation are confined to it.

Wiring the stepper's own change notification to the component, and
construction requiring a view model, are
platform-specific mechanics recorded under Platform Notes rather than as
normative requirements here — see wires-stepper-action,
rejects-coder-initialization, and rejects-frame-only-initialization.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes two text labels and a stepper
  control into a row.
- **Padding**: The row layout, given three elements (label, value label,
  stepper), inserts its flexible spacer after the first — between the
  label and the value label, not between the value label and the
  stepper (arranged order becomes label, spacer, value label, stepper).
  The row's default spacing is 8pt, applied between every adjacent pair;
  the spacer's own gap to the value label is zeroed, leaving the
  value-label-to-stepper gap at the unmodified default 8pt. The visible
  effect is the label pinned to the row's leading edge, all of the row's
  leftover width absorbed in the flexible gap right after it, and the
  value label/stepper sitting together, 8pt apart, at the trailing edge.
  The row is pinned to the component's edges with 0pt of additional
  outer padding beyond that.
- **Font**: The label resolves to the theme's button text role: 13pt,
  medium weight, proportional system font, scaled by the active theme's
  size scale. The value label resolves to the theme's code text role:
  12pt, regular weight, the system monospaced font, also scaled by the
  size scale — chosen so a value that changes on every click doesn't
  reflow the row. Both repaint automatically on a theme change. The
  stepper draws no text of its own.
- **Background**: The label/value label — none (transparent); neither
  draws a background, border, or bezel. The stepper — no background is
  set in source; it keeps the platform's default up/down control
  appearance.
- **Foreground/Text**: The label resolves to the active theme's
  primary-text role at full strength. The value label resolves to the
  theme's secondary-text role, a lower-emphasis color than the label.
  Both are recomputed live on a theme change. The stepper's arrow tint
  is the platform's own system rendering; the source sets no color on
  it.
- **Border**: Not applicable — the label/value label draw no border; the
  stepper keeps the platform's default bezel, drawn by the system
  rather than configured in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in source.
- **Min/Max size**: Not applicable — no explicit width/height constraint
  is set on the label, value label, or stepper beyond the value label's
  compression-resistance priority (not a size constraint); sizing
  follows each control's own intrinsic content size, the row's spacing
  math, and the row-pinning.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; value label shows the current integer value as plain digits; the stepper's value matches. |
| At minimum value | The stepper's value equals its minimum; because wraparound is disabled, further decrements are absorbed by the stepper's own bounds enforcement rather than wrapping to the maximum. This is the stepper's native behavior given the minimum/wraparound configuration the component sets (see disables-stepper-wraparound), not custom drawing in this file. |
| At maximum value | Symmetric to the minimum case: the stepper's value equals its maximum, further increments are absorbed rather than wrapping to the minimum. |
| Pressed | Not applicable: the component renders no button of its own; the stepper's own arrow-press highlight while clicked is the platform's default rendering, not custom to this file. |
| Disabled | Not implemented in the component; the enabled state is never read or set on the label, value label, or stepper in source. A caller may set the stepper's enabled state directly through the public stepper property, at which point the platform's native disabled dimming applies. |
| Focused | Not styled by the component; any focus ring when the stepper is tabbed to is the platform's own native focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized in source — no explicit
  accessibility-role call appears anywhere in source. The stepper keeps
  the platform's built-in accessibility role for a stepper control; the
  label and value label keep the platform's default for a non-editable
  field — static-text elements.
- **Label requirements**: Not implemented in source. The stepper has no
  accessible name linked to the label — no accessibility-title linkage
  call appears anywhere in source. Every sibling row that pairs a label
  with an interactive control does link them — the checkbox row and the
  integer field row (via its wrapped number field row) both do the same
  — so the omission here is a plain gap against the row's own family
  pattern, not a documented design choice. A screen reader announces the
  stepper as an unlabeled control, and the value label's current number
  is a separate static text element rather than the stepper's own
  spoken value.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller
  (see States); a value change updates the stepper's value directly,
  which the platform's own native accessibility value reporting picks
  up, with no explicit announcement call in source. The value label's
  parallel text update is not itself linked to the stepper's
  accessibility value (see Label requirements, above).
- **Minimum tap target**: Not applicable — this is a pointer/
  keyboard-driven control composition with no touch input path in
  source; the 44×44pt guidance is touch-specific. No control-size
  override is set on the stepper, so it keeps the platform's regular
  system metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source.
  The label and value-label text color resolves from the active theme's
  primaryText/secondaryText role against the hosting background at
  runtime; the component performs no contrast check, so whether a given
  theme's resolved pair meets 4.5:1 cannot be determined from this file.
  This would be settled by a theme-level contrast audit of
  primaryText/secondaryText against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| stepper-view-001 | arranges-row-layout | Construct the component with any view model | The label, the value label, and the stepper are subviews of a single row view, arranged left-to-right as label, spacer, value label, stepper (see Appearance/Padding), that is pinned to the component's edges; no other subview sits outside that row |
| stepper-view-002 | builds-label-from-view-model-title | The view model's title = "Recent Files" | The label reads "Recent Files" after construction |
| stepper-view-003 | builds-value-label-monospaced | Construct with any view model | The value label's font is the system monospaced font (fixed-pitch) |
| stepper-view-004 | resists-value-label-compression | Construct with any view model | The value label's horizontal content compression resistance priority is required |
| stepper-view-005 | configures-stepper-bounds | The view model's minValue = 1, maxValue = 20 | The stepper's minimum is 1.0 and its maximum is 20.0 after construction |
| stepper-view-006 | fixes-stepper-increment | Construct with any view model | The stepper's increment is 1 |
| stepper-view-007 | disables-stepper-wraparound | Construct with any view model | The stepper's wraparound is disabled |
| stepper-view-008 | initializes-stepper-value | The view model's value = 5 | The stepper's value is 5 after construction |
| stepper-view-010 | initializes-value-label-text | The view model's value = 5 | The value label reads "5" after construction |
| stepper-view-011 | updates-value-label-on-change | Set the stepper's value to 7 and trigger its change notification | The value label reads "7" immediately after the call |
| stepper-view-012 | commits-stepper-value | The view model's value = 3; set the stepper's value to 4 and trigger its change notification | The view model's value is 4 after the call |
| stepper-view-013 | skips-redundant-commits | The view model's value = 4; set the stepper's value to 4 (same value) and trigger its change notification | The view model's value setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| stepper-view-014 | syncs-on-external-change | After construction, externally change the view model's title, minValue, maxValue, and value, then trigger the view model's change notification | The label, the stepper's minimum/maximum, the stepper's value, and the value label all update to reflect the new view-model state |
| stepper-view-015 | exposes-constituent-views | Construct the component, then access its label, stepper, and value label from outside the type | All three properties are accessible and return the same instances built during construction |
| stepper-view-018 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | The compiler rejects the call at compile time under the platform's UI-thread isolation checking |
| stepper-view-019 | replaces-view-model-onchange | Assign a spy handler to the view model's change-notification callback, then construct the component | Triggering the view model's change notification after construction runs the component's own sync handler; the spy handler is not invoked |

## Edge Cases

- **Null/empty input**: the view model is a non-optional, typed
  constructor parameter; the type system rules out a missing value. An
  empty title on the view model produces a label with an empty string
  and no crash. The component provides, and needs, no nil-handling path
  for its one initializer parameter.
- **Boundary values**: At the stepper's value equal to its minimum or
  maximum, the stepper's own bounds enforcement (given wraparound
  disabled) stops further movement in that direction rather than
  wrapping to the opposite bound; because integer bounds and a fixed
  increment of 1 always land exactly on both ends, every value in the
  range is reachable.
- **Contradictory bounds (minValue > maxValue)**: source forwards the
  view model's minValue/maxValue to the stepper's minimum/maximum with
  no validation or reordering — see the Design Decision on
  inverted-bounds handling.
- **Concurrent access**: Not applicable — the component is confined to
  the UI thread, so all construction and mutation is serialized by the
  platform's concurrency checker (see confines-to-ui-thread).
- **Error states**: Not applicable — every operation in this component
  (the stepper's change notification, the label/value-label text
  updates, and the write to the view model's value) is a synchronous,
  non-throwing call; no error-producing API appears in source.
- **Offline/disconnected state**: Not applicable — the component
  performs no networking of its own; it only reads from and writes to
  an in-process view model.
- **Overwritten external observer**: the view model's change-
  notification callback is a single closure property; per
  replaces-view-model-onchange, the component's initializer
  unconditionally overwrites it, replacing whatever handler (if any) was
  previously registered — the same closure-overwrite behavior the
  checkbox row and the integer field row document. The component MUST
  NOT be assumed to coexist with another change-notification observer
  already registered on the same view model instance.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | bounded range view model (integer-valued) | — (required) | Supplies the row's title, min/max bounds, and current integer value; receives committed stepper changes via its value. The initializer overwrites this view model's change-notification callback with the component's own sync handler (see Edge Cases). |

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in source.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes entirely from the view model's title, a value
the caller provides, and the displayed value is a plain integer-to-
string conversion of the view model's/stepper's value, not a
localizable phrase — so there is nothing for this component to localize
itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation or transition call appears in source; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: source sets no custom color on the stepper; the labels' colors come from the theme's primaryText/secondaryText roles, and the stepper's own bezel rendering follows the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — the current value is shown as digits in the value label. Reaching a bound stops further movement (see disables-stepper-wraparound) rather than wrapping, but nothing in source shows the stepper rendering an arrow as disabled at the minimum/maximum; it only absorbs the click. The component introduces no color-only cue of its own either way. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in source; the row always renders once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by the view model and
  reports stepper changes back through the view model's value.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store directly; persistence is owned by the view model and
  its underlying observer, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own
  subviews (label, value label, stepper) and its reference to the view
  model for its own lifetime; it persists nothing itself beyond that.

## Logging

Not applicable: source contains no logging call (no print, log, or
logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: `HStack { Text(viewModel.title); Spacer();
  Text("\(value)").monospacedDigit(); Stepper("", value: $value, in:
  minValue...maxValue) }`, with `.labelsHidden()` on the `Stepper` since
  the leading `Text` already carries the title. Give the value `Text` an
  `.accessibilityHidden(true)` and instead attach
  `.accessibilityValue("\(value)")` to the `Stepper` itself, and
  `.accessibilityLabel(viewModel.title)` — closing the gap flagged in
  Label requirements, rather than reproducing it. Write to the bound
  state's setter with an equality guard before committing, mirroring
  skips-redundant-commits.
- **Compose**: A `Row` with `Text(title)` leading, then a monospaced
  `Text(value.toString())`, then two small `IconButton`s
  (`Icons.Default.KeyboardArrowUp`/`Down`) in place of a bare stepper —
  Compose has no built-in stepper control. Fix the step to `1`
  (mirroring fixes-stepper-increment), clamp against `minValue`/
  `maxValue` with no wraparound (mirroring disables-stepper-wraparound),
  and give the button pair a `Modifier.semantics { contentDescription =
  title }` and `stateDescription = value.toString()` — the Compose
  analog of the flagged missing accessibility link.
- **React/Web**: A flex row with a `<span>` title, a monospaced `<span>`
  showing the value, and a `<button>` pair (`aria-label="Decrease"`/
  `"Increase"`) or a native `<input type="number">` restricted to
  integer steps. Whichever control is used, wire `aria-labelledby` from
  the increment/decrement controls back to the title, and set
  `aria-valuenow`/`aria-valuemin`/`aria-valuemax` on a
  `role="spinbutton"` wrapper — the web analog of the accessibility link
  this source omits. Clamp at the bounds with no wraparound, mirroring
  disables-stepper-wraparound.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/StepperView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside
  the `ComposableSettings` namespace, conforming to
  `SettingsViewProtocol`. It composes a label, a monospaced value label,
  and an `NSStepper` into one row via `ComposableSettings.makeRow`/
  `pinToEdges`, wires the stepper's target/action to `stepperChanged(_:)`
  (wires-stepper-action), and keeps all three subviews synced to
  `RangeViewModel<Int>` on init and on `onChange`. It supports
  construction only through the view-model-taking initializer: both
  `init(coder:)` and the frame-only `init(frame:)` trigger a fatal error
  rather than producing an instance (rejects-coder-initialization,
  rejects-frame-only-initialization) — verifying this requires a
  death/exit test harness, or a compile-time API-surface check that the
  initializer is unavailable, not a normal in-process test assertion.
  There is no UIKit code path in source; a UIKit port would replace
  `NSStepper` with `UIStepper` (UIKit's direct analog — also arrows-only,
  no built-in value display) and the `target`/`action` pattern with
  `.addTarget(_:action:for: .valueChanged)`, still pairing it with a
  separate `UILabel` for the value the way this source pairs `NSStepper`
  with the value label. (Note: the frame-only initializer's fatal-error
  message string, `"init(frame frameRect: NSRect"`, is missing its
  closing parenthesis in source — a copy-paste artifact of the
  initializer's own signature, not a design choice; a port should write
  its own clear message rather than carry the typo forward.)
- **WinUI 3** (the reason this recipe exists): WinUI ships no bare,
  arrows-only stepper control equivalent to `NSStepper`/`UIStepper`. The
  closest concrete option is a `NumberBox` with
  `SpinButtonPlacementMode="Inline"`, `Minimum="{x:Bind MinValue}"`,
  `Maximum="{x:Bind MaxValue}"`, and `SmallChange="1"` (the direct
  analog of fixes-stepper-increment), laid out as a `Grid` with columns
  `*,Auto` — a `TextBlock` for the title in column 0, the `NumberBox` in
  column 1. Note the divergence from source: `NumberBox` always exposes
  an editable text field, unlike this source's read-only value label; if
  a non-editable value display is required instead, compose the row
  from a `TextBlock` (monospaced, via `FontFamily="Cascadia Mono"`) plus
  a vertical pair of small `RepeatButton`s (chevron-up/chevron-down
  glyphs) rather than `NumberBox`. Either way, set
  `AutomationProperties.Name`/`LabeledBy` on the interactive control(s)
  to the title `TextBlock` — the WinUI analog of the accessibility-title
  link this source's sibling rows have but this component itself is
  missing (see Label requirements); porting this component to WinUI is
  the moment to add it rather than carry the gap forward. Handle
  `NumberBox.ValueChanged` (or the `RepeatButton`s' `Click` events) to
  write the already-bounded, committed value with an equality guard
  before writing, mirroring skips-redundant-commits.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/StepperView.swift` |

## Design Decisions

**Decision**: Show the current value in a separate, monospaced value
label rather than relying on the stepper to display it.
**Rationale**: The stepper renders only its up/down arrow control and
carries no visible number of its own; pairing it with a dedicated value
label, kept in sync on every change, makes the current count visible
without requiring a user to press or focus the stepper.
**Approved**: pending

**Decision**: Fix the stepper's increment at `1` regardless of the view
model's range.
**Rationale**: Per the source's own doc comment, this component targets
"small bounded counts (recents, retry limits, etc.)" where each click
should move by the smallest meaningful unit; the type is generic only
over the bound, not the step size, so a caller with a wide range gets
the same one-at-a-time increments as a caller with a narrow one.
**Approved**: pending

**Decision**: Set the value label's horizontal content compression
resistance to required while leaving the label and the stepper at their
default priorities.
**Rationale**: In a tight row, the row layout shrinks the
lowest-resistance view first; a required floor on the value label keeps
the numeric value — the one piece of information the row cannot afford
to truncate — from being the view that gives way before the title label
does.
**Approved**: pending

**Decision**: Disable wraparound on the stepper (AppKit/UIKit source:
`stepper.valueWraps = false`).
**Rationale**: For a bounded count like a retry limit, wrapping from the
maximum back to the minimum (or the reverse) on one more click would
silently jump the setting to the opposite end of its range; disabling
wrap keeps a repeated click at a bound a no-op instead.
**Approved**: pending

**Decision**: Forward the view model's minValue/maxValue straight to
the stepper's minimum/maximum with no validation, reordering, or
clamping when the range is inverted (minValue > maxValue).
**Rationale**: Callers MUST supply minValue <= maxValue; the range view
model is expected to guarantee an ordered range at construction, so this
component does not duplicate that check. An inverted range that reaches
this component falls through to the stepper's own unspecified handling
rather than being coerced or clamped here (contrast the integer field
row, which explicitly detects and skips clamping on this case).
**Approved**: pending

**Decision**: Unconditionally assign the component's own handler to the
view model's change-notification callback in the initializer, replacing
any handler already registered on that view model instance (see
replaces-view-model-onchange).
**Rationale**: The component owns keeping its three subviews in sync
with the view model's current state; a single-owner change-notification
handler is the simplest way to guarantee the sync runs on every external
change, at the cost of the component being incompatible with a caller
that also wants to observe the same view model instance directly — the
same trade-off the checkbox row and the integer field row make.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requires-designated-initializer to rejects-coder-initialization; added replaces-view-model-onchange requirement, test vector, and Design Decision; recorded inverted-bounds handling as a Design Decision instead of an edge-case aside; reformatted Design Decisions to bold three-line form; moved the init(frame:) message typo out of Design Decisions into a Platform Notes aside; dropped a tag to meet the 1-5 limit; populated related with sibling recipes; corrected test vectors 001, 003, 016, and 017; removed the unverified arrow-disable claim under Differentiate Without Color; fixed bare RFC 2119 usage in Edge Cases; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
