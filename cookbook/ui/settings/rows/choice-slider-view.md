---
id: aebda2fe-b953-4b3c-a65a-93d92c059fe1
title: Choice Slider View
domain: agentictoolkit://cookbook/ui/settings/rows/choice-slider-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a discrete, tick-snapped slider with a trailing
  label showing the current choice's name, bound to a choice view model.
platforms:
- swift
- macos
tags:
- settings
- form-control
- choice
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/captioned-slider-view
- agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view
references: []
approved-by: ''
approved-date: ''
---

# Choice Slider View

## Overview

The Choice Slider View is a settings row: a title label, a discrete slider
whose ticks each correspond to one entry in a choice view model's ordered
list of choices, and a trailing label showing the current choice's name.
The slider snaps to ticks only — it never represents a value between two
choices. The row is driven by the choice view model: the view reflects the
view model's title/value on construction and whenever the view model reports
an external change, and it writes the user's slider interactions back into
the view model's setting observer. A choice also carries an optional image
identifier, but this component never reads that field — only a sibling row
over the same view model renders it.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, the
  slider, and the value label in a single horizontal row, and MUST pin that
  row to the edges of the view.
- **builds-tick-marks-from-choices**: Component MUST, at initialization, set
  the slider's minimum to 0, its maximum to one less than the number of
  choices (floored at 0), its tick count to the number of choices, and MUST
  restrict the slider to landing only on those ticks.
- **flanking-labels-hug-tightly**: Component MUST prevent both the title
  label and the value label from expanding to absorb extra row width.
- **slider-expands-to-fill-remaining-width**: Component MUST expand the
  slider to absorb the row's leftover width, rather than the title label or
  the value label.
- **fixes-value-label-width**: Component MUST size the value label's width to
  a fixed constant equal to the ceiling of the widest rendered width, among
  the view model's choice-label strings, measured in the value label's own
  font (falling back to the current theme palette's caption font when the
  value label's font is unset).
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the title label's text to the view model's title, and
  — when the view model's value matches a choice's value — set the slider
  to that choice's index and the value label's text to that choice's name.
- **claims-onchange-observer**: Component MUST assign its own handler to the
  view model's external-change notification during initialization, replacing
  any handler already registered there.
- **commits-slider-value**: Component MUST write the matching choice's value
  into the view model's setting observer when the slider is moved (see
  ignores-out-of-range-tick and skips-redundant-commits for the guard
  conditions).
- **ignores-out-of-range-tick**: Component MUST NOT write to the setting
  observer when the slider's rounded index falls outside the choice list's
  bounds.
- **skips-redundant-commits**: Component MUST NOT write to the setting
  observer when the resolved choice's value equals the current
  setting-observer value.
- **syncs-on-external-change**: Component MUST re-set the title label's text
  from the view model's title, and — when the view model's value matches a
  choice — re-set the slider and the value label's text, whenever the view
  model reports an external change.
- **leaves-display-unchanged-for-unmatched-value**: Component MUST NOT alter
  the slider's position or the value label's text when the view model's
  value does not match any choice's value, whether at initialization or on
  a later external-change notification.
- **exposes-constituent-views**: Component MUST expose the title label, the
  slider, and the value label as public, directly-accessible properties.
- **requires-view-model-at-construction**: Component MUST be constructible
  only with a view model supplied at construction time; construction paths
  that could produce an instance without one (e.g. a bare/default
  construction path or a serialization/decoding-based construction path)
  MUST be rejected (see Platform Notes for the mechanism the source uses).
- **stretches-to-superview-width**: Component MUST, once it is added to a
  container, activate a width constraint pinning itself to that container's
  full width, at a priority just below the strictest available.
- **confines-to-ui-thread**: Component MUST be usable only on the UI
  thread.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes stock label and slider instances into a
  row.
- **Padding**: The row inserts a flexible spacer between the title label and
  the remaining elements and sets the row's spacing to 8pt, which applies to
  the label-to-spacer and slider-to-value-label gaps; the spacer-to-slider
  gap is explicitly zeroed, so the spacer's own width is the only thing
  between the title label and the slider. The row is pinned directly to the
  component's edges with no additional constant, so the component
  contributes 0pt of its own outer padding beyond that internal spacing.
- **Font**: Title label (button text role) resolves to 13pt, medium weight,
  proportional system font. Value label (caption text role — the default,
  since this component requests no monospaced digits) resolves to 11pt,
  regular weight, proportional system font. Both sizes scale with the
  active theme's size scale (1.0 by default) and both labels repaint
  automatically on a theme change.
- **Background**: None (transparent) — neither label draws a background,
  border, or bezel of its own, and neither the component nor the row
  container sets a background color of its own.
- **Foreground/Text**: Title label (primaryText color role) resolves to the
  active theme's foreground color at full strength. Value label
  (secondaryText color role) resolves to that same foreground dimmed 32%
  toward the background color, with a minimum contrast ratio of 3.0
  enforced. Both recompute live on a theme change.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: The value label carries a fixed width constraint equal
  to the ceiling of the longest label width, computed once at
  initialization from the view model's choice labels (see
  fixes-value-label-width); no other element in the row has an explicit
  min/max constraint. Separately, once the component is added to a
  container, it activates a width constraint equal to that container's full
  width, at a priority just below the strictest available (see
  stretches-to-superview-width).

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; when the view model's value matches a choice, the slider sits at that choice's tick and the value label shows that choice's name. |
| Dragging | The slider's on-screen thumb snaps to the nearest tick continuously as it is dragged. The value label's text, however, updates only once the committed value round-trips through the view model's external-change notification — the setting observer delivers that callback on a *later* turn of the UI event loop, not synchronously inside the slider's action — so the value label can lag one turn behind the slider's visible tick position. |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are the platform's default rendering, not custom to this file. |
| Disabled | Not applicable: an enabled flag is never set on the slider or text fields in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and labels use the platform's default focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults — no
  custom accessibility-role or accessibility-element call appears in
  source. The slider and text elements each carry the platform's built-in
  accessibility role (slider, static text) automatically.
- **Label requirements**: The title label and the slider are laid out as
  sibling elements in the same row, but source sets no accessible-name link
  (or equivalent) on the slider linking it to the title text — unlike a
  sibling row over the same view model, which links its control's
  accessible name to its title. Assistive-technology focus on the slider is
  therefore not programmatically tied to the row's title text.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself (see States);
  there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-driven
  composition (no touch input path in source); a touch-target minimum is
  touch-interface guidance, not a pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| choice-slider-view-001 | arranges-row-layout | Construct the component with any view model | The title label, slider, and value label are all part of a single row that is pinned to the component's edges; no other layout container appears |
| choice-slider-view-002 | builds-tick-marks-from-choices | View model has 4 choices | After init, the slider's minimum is 0, its maximum is 3, its tick count is 4, and it is restricted to landing only on those ticks |
| choice-slider-view-003 | flanking-labels-hug-tightly | Construct the component | After init, neither the title label nor the value label expands to absorb extra row width |
| choice-slider-view-004 | slider-expands-to-fill-remaining-width | Construct the component | After init, the slider is the element that absorbs the row's leftover width |
| choice-slider-view-005 | fixes-value-label-width | Choice labels are "Small" and "Extra Small" | After init, the value label's width constraint constant equals the ceiling of "Extra Small"'s rendered width in the value label's font, the widest of the two |
| choice-slider-view-006 | initializes-from-view-model | View model title = "Size", choices = [(label: "Small", value: small), (label: "Large", value: large)], value = large | After init, the label reads "Size", the slider sits at index 1, and the value label reads "Large" |
| choice-slider-view-007 | commits-slider-value | Setting-observer value = choices[0]'s value; move the slider to index 1 and activate it | The setting-observer value equals choices[1]'s value after the call |
| choice-slider-view-008 | ignores-out-of-range-tick | Trigger the slider's action directly with a stub reporting a rounded index equal to the choice count (outside bounds) — a real, bound slider restricted to its own ticks clamps its value into range and can never report an out-of-range value | The setting-observer value is unchanged; no crash occurs |
| choice-slider-view-009 | skips-redundant-commits | Setting-observer value = choices[0]'s value; move the slider to index 0 (same index) and activate it | The setting-observer value's setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| choice-slider-view-010 | syncs-on-external-change | After construction, externally change the view model's title and set its value to a value present in the choices, then trigger an external-change notification | The title label, slider position, and value label all update to reflect the new view-model state |
| choice-slider-view-011 | leaves-display-unchanged-for-unmatched-value | After construction, trigger an external-change notification with a value that matches no choice | The slider position and value label remain at whatever they were before the call |
| choice-slider-view-012 | exposes-constituent-views | Construct the component, then access its title-label, slider, and value-label properties from outside the type | All three properties are accessible and return the same instances built during init |
| choice-slider-view-013 | requires-view-model-at-construction | Attempt construction via a bare/default construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| choice-slider-view-014 | requires-view-model-at-construction | Attempt construction via a serialization/decoding-based construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| choice-slider-view-015 | stretches-to-superview-width | Add an initialized component as a subview of a parent container | Once the component is attached to its container, a width constraint equal to the parent's width, at a priority just below the strictest available, is active on the component |
| choice-slider-view-016 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking such as Swift's `@MainActor`, runtime-checked otherwise) |
| choice-slider-view-017 | claims-onchange-observer | Register a handler on the view model's external-change notification, then construct the component against that same view model | Triggering the notification afterward no longer calls the previously registered handler; only the component's own handler runs |

Vector choice-slider-view-016 is a static, code-inspection check
(a compile-/runtime-enforced thread confinement), not a vector observed by
running the program; a port lacking equivalent enforcement should document
the gap rather than fabricate a runtime trap.

## Edge Cases

- Null/empty input: the view model is a non-optional, typed constructor
  parameter, ruled out from being missing by the platform's type system, so
  the component provides, and needs, no nil-handling path for its one
  initializer parameter.
- Boundary values — empty choices: when the view model's choice list is
  empty, the slider's maximum becomes 0 and its tick count becomes 0; the
  longest-label-width computation reduces to 0, so the value label's fixed
  width constraint is 0. The selection-sync logic's index search never
  matches, so the slider and value label are left at their
  construction-time defaults; source performs no guard against, or
  special-casing for, an empty choice list.
- Boundary values — single choice: when the view model has exactly one
  choice, the slider's maximum becomes 0, producing a single,
  non-interactive tick at position 0; source performs no minimum-count
  check.
- Boundary values — view model's value absent from choices: source performs
  no fallback to a default index; see leaves-display-unchanged-for-
  unmatched-value. For implementors: a view model whose current value has
  drifted out of its own choice list (e.g. after a choice list is changed
  elsewhere) leaves the row showing stale slider position and text rather
  than an explicit "no selection" state.
- Concurrent access: Not applicable — the component is confined to the UI
  thread and its value type is constrained to be safely shareable across
  threads, so all construction and mutation is serialized to that thread
  (see confines-to-ui-thread).
- Error states: Not applicable — every operation in this file (the
  slider's activation and the setting-observer write) is a synchronous,
  non-throwing call; no error-producing path appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- Overwritten external observer: see **claims-onchange-observer**. The
  view model's external-change handler is a single property, and the
  component's initializer unconditionally assigns it, replacing whatever
  handler (if any) was previously registered on that view model. A caller
  should not rely on its own external-change handler surviving once an
  instance of this component is constructed over the same view model
  instance, since construction silently discards it.
- Value-label text lags the visible tick during a drag: the slider's action
  handler writes the resolved choice's value into the setting observer but
  never writes the value label's text itself; the label is only ever
  updated by the selection-sync logic, called from the view model's
  external-change notification. Because the setting observer delivers that
  callback via a later turn of the UI event loop — not the same call
  stack — the value label can visibly trail the slider's snapped tick
  position while dragging. This is inferred from the interaction between
  the component and the setting-observer mechanism rather than stated in a
  single line of either, it is an observed, source-traceable consequence of
  how the two are wired together, not an implementation choice this
  component itself makes.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | choice view model object | — (required) | Supplies the row's title, the ordered choice list, and the current value; receives committed slider changes via its setting observer. The initializer also overwrites this view model's external-change handler with the component's own selection-sync handler (see Edge Cases). Each choice's optional image identifier is accepted by the type but never read by this component (see Overview). |

## Deep Linking

Not applicable: the component is a row inside a composable settings window,
not a navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in source.

## Localization

Not applicable: the file contains no user-facing string literals of its own.
The row's title comes from the view model's title and its value text comes
from the matching choice's name; both are values the caller provides, so
there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — source contains no animation or transition call; every state change is an instantaneous property assignment. |
| Increase Contrast | Partial — the title label uses the theme's foreground color at full strength, which tracks system Increase Contrast normally, but the value label's color is theme-computed as the foreground dimmed toward the background (see Foreground/Text): it enforces its own fixed 3.0 minimum contrast ratio rather than responding to the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable — the current choice is communicated through the slider's tick position and the value label's text, not through any color-only signal; no color-coded state exists in source. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in source; the row always renders once constructed.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only displays a value supplied by the view model and reports
  slider changes back through the view model's setting observer.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store; persistence, if any, is owned by the view model and its
  setting observer, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the component retains only its own
  constituent elements and its reference to the view model for its own
  lifetime; it persists nothing beyond that.

## Logging

Not applicable: the source contains no logging call.

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)`, a
  `Slider(value: $index, in: 0...Double(max(choices.count - 1, 0)), step: 1)`
  bound to the selected index — the `max(choices.count - 1, 0)` guard
  mirrors the source's own guard so an empty `choices` array produces a
  `0...0` range instead of trapping (see builds-tick-marks-from-choices)
  (SwiftUI's `step:` parameter is the direct analog of
  `allowsTickMarkValuesOnly` + `numberOfTickMarks` — it snaps the value to
  whole steps natively), and a trailing `Text(choices[index].label)`. Give
  the `Slider` no fixed frame (it already expands to fill the `HStack`'s
  remaining space, mirroring slider-expands-to-fill-remaining-width) and
  give the trailing `Text` a `.frame(minWidth:)` computed once from the
  widest choice label's rendered size, mirroring fixes-value-label-width.
  Commit the index to the backing view model from the `Binding`'s setter
  with an equality guard, mirroring skips-redundant-commits.
- **Compose**: Use a `Row` with a leading `Text(title)`, a
  `Slider(value = index.toFloat(), valueRange = 0f..(choices.size - 1)
  .toFloat(), steps = max(choices.size - 2, 0))` given `Modifier.weight(1f)`
  (the Compose analog of the low hugging priority — `steps` is the count of
  discrete stops between the two ends, mirroring
  builds-tick-marks-from-choices), and a trailing `Text(choices[index]
  .label)` sized with `Modifier.width(with(density) {
  measuredMaxWidth.toDp() })`, where `measuredMaxWidth` comes from a
  `TextMeasurer` pass over the choice labels ahead of composition, mirroring
  fixes-value-label-width. Round
  the reported float to the nearest index, guard it against
  `choices.indices` before writing (mirroring ignores-out-of-range-tick),
  and skip the write when the resolved value already equals the current one
  (mirroring skips-redundant-commits).
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<span>` for the title, an `<input type="range" min="0"
  max={Math.max(choices.length - 1, 0)} step="1">` given `flex: 1` (guarding
  `max` with the same `max(count - 1, 0)` floor as the source keeps an empty
  `choices` array from producing a negative `max`; the native `step`
  attribute is the direct analog of `allowsTickMarkValuesOnly`, mirroring
  slider-hugs-loosely for the flex sizing), and a trailing `<span>` given a
  fixed `min-width` computed once from the widest choice label's measured
  text width (mirroring fixes-value-label-width) plus `flex: 0 0 auto;
  white-space: nowrap`. Unlike a sibling recipe's live-captioned slider,
  mirror this component's actual behavior: update the trailing `<span>`
  from the committed index on `onChange`, not from every intermediate
  `onInput` tick, since source never writes the value label outside the
  `viewModel.onChange` round trip (see Edge Cases).
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ChoiceSliderView.swift`.
  A macOS-only (`import AppKit`), generic-over-`Value` `NSView` subclass,
  `@MainActor`-isolated (the mechanism behind confines-to-ui-thread),
  inside the `ComposableSettings` namespace, conforming to
  `SettingsViewProtocol`. It composes three subviews — an `NSTextField`
  label from `ComposableSettings.makeRowLabel`, a tick-mark-only
  `NSSlider`, and a width-pinned `NSTextField` value label from
  `ComposableSettings.makeValueLabel` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`, with the slider's
  horizontal content-hugging priority set to `1` (the mechanism behind
  slider-expands-to-fill-remaining-width) and the flanking labels' set to
  `.required` (the mechanism behind flanking-labels-hug-tightly). Both
  inherited `NSView` initializers that could construct the view without a
  `viewModel` — `init(coder:)` and the frame-only `init(frame:)` — are
  forced to fatal-error, leaving `init(viewModel:)` as the only usable
  initializer; this is the mechanism behind
  requires-view-model-at-construction. There is no UIKit code path in
  source; a UIKit port would replace `NSSlider`/`NSTextField` with
  `UISlider`/`UILabel` and the `target`/`action` pattern with
  `.addTarget(_:action:for: .valueChanged)` — `UISlider` has no native
  tick-mark/snap-to-discrete-value mode, so a port must reimplement
  `allowsTickMarkValuesOnly` by rounding `sender.value` to the nearest
  whole step inside the `.valueChanged` handler. The string passed to the
  fatal-error call in the frame-only initializer is the identical,
  truncated `"init(frame frameRect: NSRect"` literal used by this file's
  sibling row views, missing the closing signature text; it has no effect
  on behavior — the call still traps unconditionally either way — and
  reads as a copy-paste artifact carried over from an earlier row view
  rather than authored fresh for this file.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*,Auto`: a `TextBlock` for the title in
  column 0; a `Slider Minimum="0" Maximum="{choices.Count - 1}"
  StepFrequency="1" IsSnapToTickEnabled="True" TickFrequency="1"
  HorizontalAlignment="Stretch"` in column 1 — `IsSnapToTickEnabled`
  combined with `TickFrequency="1"` is the direct WinUI analog of
  `allowsTickMarkValuesOnly` + `numberOfTickMarks`, and the `*` column is
  the WinUI analog of the `1`-priority hugging that lets the `Slider` claim
  the width left over after the two `Auto`-sized labels (mirroring
  slider-hugs-loosely); a trailing `TextBlock` bound through an
  `IValueConverter` that maps the rounded index to `choices[index].Label`
  in column 2, whose `Width` is set once, in code-behind after `Loaded`, to
  the `Auto`-measured width of the longest label string via a hidden
  measuring `TextBlock` — the WinUI analog of fixes-value-label-width's
  one-time `ceil(longestLabelWidth)` constant (like the source, do not
  re-measure it on a later `FontSize` or theme change — see Design
  Decisions). Use the
  `Slider`'s `ValueChanged` event handler to round and guard the index
  against `choices.Count` before writing back (mirroring
  ignores-out-of-range-tick), and skip the write — and so skip raising
  `INotifyPropertyChanged` — when the resolved value already equals the
  current one (mirroring skips-redundant-commits).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ChoiceSliderView.swift` |

## Design Decisions

- **Decision**: Fix the value label's width to a single constant, computed
  once at init from the widest choice label rendered in the label's own
  font, rather than letting the label's intrinsic width vary per choice.
  **Rationale**: Per the source's own comment, this keeps "the slider's
  width from oscillating as the user drags through shorter/longer choice
  labels (e.g. \"Small\" → \"Extra Small\")."
  **Approved**: pending
- **Decision** (AppKit): Force the title label's and value label's
  horizontal content-hugging priority to `.required` and the slider's to
  `1`, rather than leaving the flanking labels at AppKit's default hugging
  priority.
  **Rationale**: Per the source's own comment, below the row spacer's own
  `defaultLow` priority "the two tie and the free width is split between
  them" — forcing `.required` on the flanking labels guarantees the slider
  alone absorbs the row's extra width.
  **Approved**: pending
- **Decision**: Update the value label's text only through the
  selection-sync logic, called from the view model's external-change
  notification, rather than writing it directly inside the slider's action
  handler.
  **Rationale**: Unlike a sibling row that accepts a caller-supplied
  formatter and updates its caption optimistically inside its own slider
  handler, this component's value text always comes from re-searching the
  view model's choices for the matching entry — the component performs
  that lookup in exactly one place (the selection-sync logic) rather than
  duplicating it inside the action handler, at the cost of the one-turn
  display lag documented in Edge Cases.
  **Approved**: pending
- **Decision**: Leave the slider's position and the value label's text
  untouched when the view model's value matches no choice's value, rather
  than falling back to a default index or clearing either label.
  **Rationale**: The selection-sync logic's index-match guard has no
  fallback branch in source; the component makes no attempt to represent
  an unrepresentable value, leaving whatever the elements last displayed.
  **Approved**: pending
- **Decision** (WinUI): Measure the value column's width once, in
  code-behind after `Loaded`, from the longest label string, rather than
  re-measuring it if the control's `FontSize` or the active theme changes
  later.
  **Rationale**: Mirrors the source's own one-time `ceil(longestLabelWidth)`
  computation (see fixes-value-label-width); this recipe does not introduce
  WinUI-specific staleness handling beyond matching that choice.
  **Approved**: pending
- **Decision** (AppKit): Both `init(coder:)` and the frame-only
  `init(frame:)` trigger a fatal error, leaving `init(viewModel:)` as the
  only usable initializer.
  **Rationale**: The view has no meaningful default state — it cannot
  render a title, tick range, or value without a view model — so both
  inherited `NSView` initializers that could construct it without one are
  intentionally disabled. (The frame-only override's fatal-error message
  text is a separate, unrelated observation — see Platform Notes.)
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: added missing initial Change History row; added claims-onchange-observer requirement and test vector for the onChange-overwrite behavior; trimmed commits-slider-value to the positive write, letting ignores-out-of-range-tick and skips-redundant-commits own the guards; removed RFC 2119 keywords from Edge Cases and reframed several as plain observations; separated the frame-only initializer's copied fatal-error message text from the initializer-disabling Design Decision; added PopupMenuChoiceView to related; fixed the Increase Contrast/Appearance contradiction; fixed test vector 008 to use a stub sender instead of an unreachable real-slider state; guarded the SwiftUI and React empty-choices ranges; corrected the Compose value-label measurement approach; added a pending Design Decision for the WinUI value-label re-measurement staleness |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
