---
id: aebda2fe-b953-4b3c-a65a-93d92c059fe1
title: ChoiceSliderView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/choice-slider-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row pairing a discrete, tick-snapped NSSlider
  with a trailing label showing the current choice's name, bound to a ChoiceViewModel.
platforms:
- swift
- macos
tags:
- settings
- form-control
- choice
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/captioned-slider-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/popup-menu-choice-view
references: []
approved-by: ''
approved-date: ''
---

# ChoiceSliderView

## Overview

`ChoiceSliderView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ChoiceSliderView.swift`):
a title label, a discrete `NSSlider` whose ticks each correspond to one entry
in a `ChoiceViewModel<Value>`'s `choices` array, and a trailing label showing
the current choice's `label` text. Per the source's own doc comment, the
slider "snaps to ticks only" — it never represents a value between two
choices. The row is driven by `ChoiceViewModel<Value>`: the view reflects the
view model's title/value on construction and whenever the view model reports
an external change, and it writes the user's slider interactions back into
the view model's `settingObserver`. `ChoiceViewModel.Choice` also carries an
optional `imageSystemName`, but `ChoiceSliderView` never reads that field —
only `PopupMenuChoiceView`, a sibling row over the same view model, renders
it.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, the
  slider, and the value label in a single horizontal row, and MUST pin that
  row to the edges of the view.
- **builds-tick-marks-from-choices**: Component MUST, at initialization, set
  the slider's `minValue` to `0`, its `maxValue` to
  `Double(max(viewModel.choices.count - 1, 0))`, its `numberOfTickMarks` to
  `viewModel.choices.count`, and its `allowsTickMarkValuesOnly` to `true`.
- **flanking-labels-hug-tightly**: Component MUST set both the title label's
  and the value label's horizontal content-hugging priority to `.required`.
- **slider-hugs-loosely**: Component MUST set the slider's horizontal
  content-hugging priority to `1` — below the row spacer's `defaultLow`
  priority — so the slider, not the title label or the value label, takes
  the width left over after the row is laid out.
- **fixes-value-label-width**: Component MUST size the value label's width to
  a fixed constant equal to the ceiling of the widest rendered width, among
  `viewModel.choices`' `label` strings, measured in the value label's own
  font (falling back to the current theme palette's caption font when the
  value label's font is `nil`).
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the title label's text to `viewModel.title`, and —
  when `viewModel.value` matches a choice's `value` — set the slider's
  `doubleValue` to that choice's index and the value label's text to that
  choice's `label`.
- **claims-onchange-observer**: Component MUST assign its own handler to
  `viewModel.onChange` during initialization, replacing any handler already
  registered there.
- **commits-slider-value**: Component MUST write the matching choice's
  `value` into `viewModel.settingObserver.value` when the slider's action
  fires (see ignores-out-of-range-tick and skips-redundant-commits for the
  guard conditions).
- **ignores-out-of-range-tick**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the slider action's rounded index
  falls outside `viewModel.choices.indices`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the resolved choice's value equals
  the current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-set the title label's text
  from `viewModel.title`, and — when `viewModel.value` matches a choice —
  re-set the slider's `doubleValue` and the value label's text, whenever
  `viewModel.onChange` fires.
- **leaves-display-unchanged-for-unmatched-value**: Component MUST NOT alter
  the slider's `doubleValue` or the value label's text when
  `viewModel.value` does not match any choice's `value`, whether at
  initialization or on a later `viewModel.onChange` call.
- **exposes-constituent-views**: Component MUST expose `label`, `slider`, and
  `valueLabel` as public, directly-accessible properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **stretches-to-superview-width**: Component MUST, once it is added to a
  superview, activate a width constraint pinning itself to that superview's
  full width, at a priority one step below `.required`.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes stock `NSTextField`/`NSSlider` instances
  into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer between
  the title label and the remaining views (`[label, spacer, slider,
  valueLabel]`) and sets the `NSStackView`'s `spacing` to
  `SettingsLayout.default[.rowSpacing]` = 8pt, which applies to the
  label→spacer and slider→valueLabel gaps; `makeRow` explicitly zeroes the
  spacer→slider gap (`setCustomSpacing(0, after: spacer)`), so the spacer's
  own width is the only thing between the title label and the slider.
  `pinToEdges` pins the row's top/leading/trailing/bottom directly to
  `ChoiceSliderView`'s edges with no additional constant, so the component
  contributes 0pt of its own outer padding beyond that internal spacing.
- **Font**: Title label (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight, proportional
  system font. Value label (`makeValueLabel()`, `textRole: .caption` — the
  default, since `ChoiceSliderView` passes no `monospacedDigits: true`)
  resolves to `ThemeTypography.defaultStyle(.caption)`: 11pt, regular
  weight, proportional system font. Both sizes scale with the active
  theme's `sizeScale` (`1.0` by default) and both labels repaint
  automatically on a theme change via `ThemePaletteObserver`.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false`
  on both labels, and neither `ChoiceSliderView` nor the row `NSStackView`
  sets `wantsLayer` or a background color of its own.
- **Foreground/Text**: Title label (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength. Value label (`role:
  .secondaryText`) resolves to that same foreground dimmed 32% toward the
  background color, with a minimum contrast ratio of 3.0 enforced
  (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`).
  Both recompute live on a theme change via `ThemePaletteObserver`.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `ChoiceSliderView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `ChoiceSliderView.swift`.
- **Min/Max size**: The value label carries a fixed `widthAnchor` constraint
  equal to `ceil(longestLabelWidth)`, computed once at initialization from
  `viewModel.choices.map(\.label)` (see fixes-value-label-width); no other
  view in the row has an explicit min/max constraint. Separately, once the
  component is added to a superview, it activates a width constraint equal
  to that superview's full width, at priority `.required - 1` (see
  stretches-to-superview-width).

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; when `viewModel.value` matches a choice, the slider sits at that choice's tick and the value label shows that choice's `label`. |
| Dragging | The slider's on-screen thumb snaps to the nearest tick continuously as it is dragged (`allowsTickMarkValuesOnly`). The value label's text, however, updates only once the committed value round-trips through `viewModel.onChange` — `UserSettingObserver` delivers that callback on a *later* main-queue turn (`.receive(on: DispatchQueue.main)`), not synchronously inside the slider's action — so the value label can lag one main-queue turn behind the slider's visible tick position. |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are `NSSlider`'s default AppKit rendering, not custom to this file. |
| Disabled | Not applicable: `isEnabled` is never set on the slider or text fields in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and labels use AppKit's default `NSControl` focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call appears
  in source. `NSSlider` and `NSTextField` each carry AppKit's built-in
  accessibility role (slider, static text) automatically.
- **Label requirements**: The title label (`label`) and the slider are laid
  out as sibling views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on the
  slider linking it to the title text — unlike `PopupMenuChoiceView`, the
  sibling row over the same `ChoiceViewModel<Value>`, which calls
  `self.popUpButton.setAccessibilityTitleUIElement(self.label)` on its
  control. VoiceOver focus on the slider is therefore not programmatically
  tied to the row's title text.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself (see States);
  there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| choice-slider-view-001 | arranges-row-layout | Construct `ChoiceSliderView` with any `viewModel` | `label`, `slider`, and `valueLabel` are all subviews of a single row view that is pinned to the component's edges; no other layout container appears |
| choice-slider-view-002 | builds-tick-marks-from-choices | `viewModel.choices` has 4 entries | After init, `slider.minValue == 0`, `slider.maxValue == 3`, `slider.numberOfTickMarks == 4`, `slider.allowsTickMarkValuesOnly == true` |
| choice-slider-view-003 | flanking-labels-hug-tightly | Construct the component | After init, `label.contentHuggingPriority(for: .horizontal) == .required` and `valueLabel.contentHuggingPriority(for: .horizontal) == .required` |
| choice-slider-view-004 | slider-hugs-loosely | Construct the component | After init, `slider.contentHuggingPriority(for: .horizontal).rawValue == 1` |
| choice-slider-view-005 | fixes-value-label-width | `viewModel.choices` labels are `"Small"` and `"Extra Small"` | After init, `valueLabel`'s width constraint constant equals `ceil("Extra Small".renderedWidth(usingFont: valueLabel.font))`, the widest of the two |
| choice-slider-view-006 | initializes-from-view-model | `viewModel.title = "Size"`, `viewModel.choices = [(label: "Small", value: .small), (label: "Large", value: .large)]`, `viewModel.value = .large` | After init, `label.stringValue == "Size"`, `slider.doubleValue == 1`, `valueLabel.stringValue == "Large"` |
| choice-slider-view-007 | commits-slider-value | `viewModel.settingObserver.value == choices[0].value`; set `slider.doubleValue = 1` and invoke `sliderChanged(slider)` | `viewModel.settingObserver.value == choices[1].value` after the call |
| choice-slider-view-008 | ignores-out-of-range-tick | Invoke `sliderChanged(_:)` directly with a stub `NSSlider` (or subclass override) whose `doubleValue` reports a rounded index of `viewModel.choices.count` (outside bounds) — a real, bound `NSSlider` with `allowsTickMarkValuesOnly` clamps `doubleValue` into `[minValue, maxValue]` and can never report an out-of-range value | `viewModel.settingObserver.value` is unchanged; no crash occurs |
| choice-slider-view-009 | skips-redundant-commits | `viewModel.settingObserver.value == choices[0].value`; set `slider.doubleValue = 0` (same index) and invoke `sliderChanged(slider)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| choice-slider-view-010 | syncs-on-external-change | After construction, externally change `viewModel.title` and set `viewModel.value` to a value present in `choices`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `slider.doubleValue`, and `valueLabel.stringValue` all update to reflect the new `viewModel` state |
| choice-slider-view-011 | leaves-display-unchanged-for-unmatched-value | After construction, invoke `viewModel.onChange(newValue)` where `newValue` matches no `choices[].value` | `slider.doubleValue` and `valueLabel.stringValue` remain at whatever they were before the call |
| choice-slider-view-012 | exposes-constituent-views | Construct the component, then access `.label`, `.slider`, `.valueLabel` from outside the type | All three properties are accessible and return the same `NSTextField`/`NSSlider`/`NSTextField` instances built during init |
| choice-slider-view-013 | requires-designated-initializer | Attempt `ChoiceSliderView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| choice-slider-view-014 | rejects-frame-only-initialization | Attempt `ChoiceSliderView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| choice-slider-view-015 | stretches-to-superview-width | Add an initialized `ChoiceSliderView` as a subview of a parent `NSView` | After `viewDidMoveToSuperview` runs, a width constraint equal to the parent's `widthAnchor`, at priority `.required - 1`, is active on the component |
| choice-slider-view-016 | confines-to-main-actor | Attempt to construct or mutate a `ChoiceSliderView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| choice-slider-view-017 | claims-onchange-observer | Register a closure on `viewModel.onChange`, then construct `ChoiceSliderView(viewModel:)` | Invoking `viewModel.onChange(newValue)` afterward no longer calls the previously registered closure; only the component's own handler runs |

## Edge Cases

- Null/empty input: `viewModel` (`ChoiceViewModel<Value>`) is a non-optional,
  typed constructor parameter; Swift's type system rules out `nil`, so the
  component provides, and needs, no nil-handling path for its one
  initializer parameter.
- Boundary values — empty `choices`: when `viewModel.choices.isEmpty`,
  `slider.maxValue` becomes `Double(max(-1, 0)) == 0` and
  `numberOfTickMarks` becomes `0`; `maxLabelWidth` reduces to `[].max() ?? 0`,
  so the value label's fixed width constraint is `0`. `syncSelection()`'s
  `firstIndex` search never matches, so the slider and value label are left
  at their construction-time defaults; source performs no guard against, or
  special-casing for, an empty `choices` array.
- Boundary values — single choice: when `viewModel.choices.count == 1`,
  `slider.maxValue` becomes `Double(max(0, 0)) == 0`, producing a single,
  non-interactive tick at position 0; source performs no minimum-count
  check.
- Boundary values — `viewModel.value` absent from `choices`: source performs
  no fallback to a default index; see leaves-display-unchanged-for-
  unmatched-value. For implementors: a view model whose current value has
  drifted out of its own `choices` list (e.g. after a choices list is
  changed elsewhere) leaves the row showing stale slider position and text
  rather than an explicit "no selection" state.
- Concurrent access: Not applicable — the class is `@MainActor` and `Value`
  is constrained to `Sendable`, so all construction and mutation is
  serialized to the main actor (see confines-to-main-actor).
- Error states: Not applicable — every operation in this file (the slider's
  target-action and the `settingObserver.value` write) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ChoiceViewModel`.
- Overwritten external observer: see **claims-onchange-observer**.
  `viewModel.onChange` is a single closure property, and
  `ChoiceSliderView`'s initializer unconditionally assigns it, replacing
  whatever handler (if any) was previously registered on that `viewModel`.
  A caller should not rely on its own `onChange` handler surviving once a
  `ChoiceSliderView` is constructed over the same `ChoiceViewModel`
  instance, since construction silently discards it.
- Value-label text lags the visible tick during a drag: `sliderChanged(_:)`
  writes the resolved choice's value into `settingObserver.value` but never
  writes `valueLabel.stringValue` itself; the label is only ever updated by
  `syncSelection()`, called from `viewModel.onChange`. Because
  `UserSettingObserver` delivers that callback via
  `.receive(on: DispatchQueue.main)` — a later run-loop turn, not the same
  call stack — the value label can visibly trail the slider's snapped tick
  position while dragging. This is inferred from the interaction between
  `ChoiceSliderView.swift` and `UserSetting.swift` rather than stated in a
  single line of either file; it is an observed, source-traceable
  consequence of how the two files are wired together, not an
  implementation choice `ChoiceSliderView` itself makes.
- Frame-only initializer's fatal-error message text: the string passed to
  `fatalError` in `init(frame:)` is the identical, truncated
  `"init(frame frameRect: NSRect"` literal used by this file's sibling row
  views, missing the closing signature text. It has no effect on behavior —
  the call still traps unconditionally either way — and reads as a
  copy-paste artifact carried over from an earlier row view rather than
  authored fresh for this file; it is reproduced here as written, matching
  source.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ChoiceViewModel<Value>` | — (required) | Supplies the row's title, the ordered `choices` list, and the current value; receives committed slider changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `syncSelection` handler (see Edge Cases). `Choice.imageSystemName` is accepted by the type but never read by `ChoiceSliderView` (see Overview). |

## Deep Linking

Not applicable: `ChoiceSliderView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `ChoiceSliderView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its own.
The row's title comes from `viewModel.title` and its value text comes from
the matching `Choice.label`; both are values the caller provides, so there
is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment. |
| Increase Contrast | Partial — the title label uses the theme's foreground color at full strength, which tracks system Increase Contrast normally, but the value label's color is theme-computed as `foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)` (see Foreground/Text): it enforces its own fixed 3.0 minimum contrast ratio rather than responding to the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable — the current choice is communicated through the slider's tick position and the value label's text, not through any color-only signal; no color-coded state exists in source. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `ChoiceSliderView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `ChoiceSliderView.swift` contains no analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only displays a value supplied by `viewModel` and reports slider
  changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `ChoiceViewModel`/`settingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews and
  its reference to `viewModel` for its own lifetime; it persists nothing
  beyond that.

## Logging

Not applicable: `ChoiceSliderView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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
  remaining space, mirroring slider-hugs-loosely) and give the trailing
  `Text` a `.frame(minWidth:)` computed once from the widest choice label's
  rendered size, mirroring fixes-value-label-width. Commit the index to the
  backing view model from the `Binding`'s setter with an equality guard,
  mirroring skips-redundant-commits.
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
  `@MainActor`, inside the `ComposableSettings` namespace, conforming to
  `SettingsViewProtocol`. It composes three subviews — an `NSTextField`
  label from `ComposableSettings.makeRowLabel`, a tick-mark-only
  `NSSlider`, and a width-pinned `NSTextField` value label from
  `ComposableSettings.makeValueLabel` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`, with the slider's
  horizontal content-hugging priority set to `1` and the flanking labels'
  set to `.required`. There is no UIKit code path in source; a UIKit port
  would replace `NSSlider`/`NSTextField` with `UISlider`/`UILabel` and the
  `target`/`action` pattern with `.addTarget(_:action:for: .valueChanged)`
  — `UISlider` has no native tick-mark/snap-to-discrete-value mode, so a
  port must reimplement `allowsTickMarkValuesOnly` by rounding
  `sender.value` to the nearest whole step inside the `.valueChanged`
  handler.
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

- Decision: Fix the value label's width to a single constant, computed once
  at init from the widest choice label rendered in the label's own font,
  rather than letting the label's intrinsic width vary per choice.
  Rationale: Per the source's own comment, this keeps "the slider's width
  from oscillating as the user drags through shorter/longer choice labels
  (e.g. \"Small\" → \"Extra Small\")."
  Approved: pending
- Decision: Force the title label's and value label's horizontal
  content-hugging priority to `.required` and the slider's to `1`, rather
  than leaving the flanking labels at AppKit's default hugging priority.
  Rationale: Per the source's own comment, below the row spacer's own
  `defaultLow` priority "the two tie and the free width is split between
  them" — forcing `.required` on the flanking labels guarantees the slider
  alone absorbs the row's extra width.
  Approved: pending
- Decision: Update the value label's text only through `syncSelection()`,
  called from `viewModel.onChange`, rather than writing it directly inside
  `sliderChanged(_:)`.
  Rationale: Unlike a sibling row that accepts a caller-supplied formatter
  and updates its caption optimistically inside its own slider handler,
  `ChoiceSliderView`'s value text always comes from re-searching
  `viewModel.choices` for the matching entry — the component performs that
  lookup in exactly one place (`syncSelection()`) rather than duplicating it
  inside the action handler, at the cost of the one-turn display lag
  documented in Edge Cases.
  Approved: pending
- Decision: Leave `slider.doubleValue` and `valueLabel.stringValue`
  untouched when `viewModel.value` matches no `Choice.value`, rather than
  falling back to a default index or clearing either label.
  Rationale: `syncSelection()`'s `if let index = ...` guard has no `else`
  branch in source; the component makes no attempt to represent an
  unrepresentable value, leaving whatever the views last displayed.
  Approved: pending
- Decision: Measure the WinUI value column's width once, in code-behind
  after `Loaded`, from the longest label string, rather than re-measuring it
  if the control's `FontSize` or the active theme changes later.
  Rationale: Mirrors the source's own one-time `ceil(longestLabelWidth)`
  computation (see fixes-value-label-width); this recipe does not introduce
  WinUI-specific staleness handling beyond matching that choice.
  Approved: pending
- Decision: Both `init(coder:)` and the frame-only `init(frame:)` trigger a
  fatal error, leaving `init(viewModel:)` as the only usable initializer.
  Rationale: The view has no meaningful default state — it cannot render a
  title, tick range, or value without a `viewModel` — so both inherited
  `NSView` initializers that could construct it without one are
  intentionally disabled. (The frame-only override's fatal-error message
  text is a separate, unrelated observation — see Edge Cases.)
  Approved: pending

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
