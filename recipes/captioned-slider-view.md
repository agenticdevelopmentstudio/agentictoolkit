---
id: 64825f85-8b4d-4406-befc-aa08ce55cc8b
title: CaptionedSliderView
domain: agentictoolkit://recipes/captioned-slider-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings-window row pairing an NSSlider with a title label and a live,
  formatter-derived trailing caption showing the current value.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# CaptionedSliderView

## Overview

`CaptionedSliderView` is a macOS `ComposableSettings` row: a title label, an
`NSSlider`, and a trailing caption label in one horizontal row. The caption
shows the slider's current value rendered through a caller-supplied
formatter (e.g. `{ "\(Int($0 * 100))%" }` or `{ "\(Int($0))s" }`), for use
when the slider's handle position alone doesn't identify the current value.
The row is driven by a `RangeViewModel<Double>`: the view reflects the view
model's title/min/max/value on construction and whenever the view model
reports an external change, and it writes the user's slider interactions
back into the view model's `settingObserver`.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, the
  slider, and the caption label in a single horizontal row, and MUST pin
  that row to the edges of the view.
- **sets-slider-range**: Component MUST set the slider's `minValue` and
  `maxValue` from `viewModel.minValue` and `viewModel.maxValue` at
  initialization.
- **slider-hugs-loosely**: Component MUST set the slider's horizontal
  content-hugging priority to `1` — below the row spacer's `defaultLow`
  priority — so the slider, not the inter-item spacing, takes the width
  left over after the label and caption are laid out.
- **caption-resists-compression**: Component MUST set the caption label's
  horizontal compression-resistance priority to `.required` so the caption
  is never compressed.
- **caption-uses-monospaced-digits**: Component MUST render the caption
  label with monospaced digit glyphs (built via
  `ComposableSettings.makeValueLabel(monospacedDigits: true)`).
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the title label's text to `viewModel.title`, the
  slider's value to `viewModel.value`, and the caption label's text to
  `formatter(viewModel.value)`.
- **updates-caption-live**: Component MUST update the caption label's text
  to `formatter(newValue)` immediately whenever the slider's action fires
  with a new value, independent of any round trip through the view model.
- **commits-slider-value**: Component MUST write the slider's new value
  into `viewModel.settingObserver.value` whenever the slider's action
  fires and the new value differs from the current
  `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the slider's new value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-synchronize the title
  label's text, the slider's value, and the caption label's text —
  re-reading `viewModel.title` and `viewModel.value` — whenever
  `viewModel.onChange` fires.
- **exposes-constituent-views**: Component MUST expose `label`, `slider`,
  and `captionLabel` as public, directly-accessible properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes stock `NSTextField`/`NSSlider`
  instances into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer
  between the label and the remaining views (`[label, spacer, slider,
  captionLabel]`) and sets the `NSStackView`'s `spacing` to
  `SettingsLayout.default[.rowSpacing]` = 8pt; that 8pt gap applies
  between label→spacer and slider→captionLabel, while `makeRow`
  explicitly zeroes the spacer→slider gap
  (`setCustomSpacing(0, after: spacer)`) so the spacer's own width is the
  only thing between the label and the slider. `pinToEdges` pins the
  row's top/leading/trailing/bottom directly to `CaptionedSliderView`'s
  edges with no additional constant, so the component contributes 0pt of
  its own outer padding beyond that internal 8pt / 0pt / 8pt spacing.
- **Font**: Title label (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight,
  proportional system font. Caption label
  (`makeValueLabel(monospacedDigits: true)`, `textRole: .code`) resolves
  to `ThemeTypography.defaultStyle(.code)`: 12pt, regular weight,
  monospaced. Both sizes scale with the active theme's `sizeScale`
  (`1.0` by default) and both labels repaint automatically on a theme
  change via `ThemePaletteObserver`.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled =
  false` on both the title and caption labels, and neither
  `CaptionedSliderView` nor the row `NSStackView` sets `wantsLayer` or a
  background color of its own.
- **Foreground/Text**: Title label (`role: .primaryText`) resolves to
  the active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged). Caption label (`role: .secondaryText`) resolves to that
  same foreground dimmed 32% toward the background color, with a
  minimum contrast ratio of 3.0 enforced
  (`foreground.dimmed(towards: background, by: 0.32, minContrast:
  3.0)`). Both recompute live on a theme change via
  `ThemePaletteObserver`.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in `CaptionedSliderView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `CaptionedSliderView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `CaptionedSliderView.swift`; sizing is governed
  entirely by the content-hugging (`1`, slider) and
  compression-resistance (`.required`, caption) priorities set on the
  row's constituent views.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; slider is at `viewModel.value`; caption shows `formatter(viewModel.value)`. |
| Dragging | Caption updates live to `formatter(newValue)` as the slider's action fires, ahead of any view-model round trip (see updates-caption-live). |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are NSSlider's default AppKit rendering, not custom to this file. |
| Disabled | Not applicable: `isEnabled` is never set on the slider or text fields in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and labels use AppKit's default `NSControl` focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call
  appears in source. `NSSlider` and `NSTextField` each carry AppKit's
  built-in accessibility role (slider, static text) automatically.
- **Label requirements**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. The title label (`label`) and the slider are laid
  out as sibling views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on
  the slider linking it to the title text — confirmed by comparison with
  sibling row views in the same directory: `CheckboxView`,
  `NumberFieldView`, and `PopupMenuChoiceView` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their
  control, but neither `CaptionedSliderView` nor the plain `SliderView`
  it's modeled on does so for `slider`. What is missing: whether
  VoiceOver announces the row's title when focus lands on the slider, or
  only "slider" with no further context. What would settle it: a
  VoiceOver pass over an instantiated row, or an explicit decision to
  call `slider.setAccessibilityTitleUIElement(label)` in `init`/`sync()`,
  matching the pattern the other control-with-label rows already use.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path
  in source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| captioned-slider-view-001 | arranges-row-layout | Construct `CaptionedSliderView` with any `viewModel`/`formatter` | `label`, `slider`, and `captionLabel` are all subviews of a single row view that is pinned to the component's edges; no other layout container appears |
| captioned-slider-view-002 | sets-slider-range | `viewModel.minValue = 0`, `viewModel.maxValue = 1` | After init, `slider.minValue == 0` and `slider.maxValue == 1` |
| captioned-slider-view-003 | slider-hugs-loosely | Construct the component | After init, `slider.contentHuggingPriority(for: .horizontal).rawValue == 1` |
| captioned-slider-view-004 | caption-resists-compression | Construct the component | After init, `captionLabel.contentCompressionResistancePriority(for: .horizontal) == .required` |
| captioned-slider-view-005 | caption-uses-monospaced-digits | Construct the component | `captionLabel`'s font descriptor includes the monospaced-digit font-feature trait |
| captioned-slider-view-006 | initializes-from-view-model | `viewModel.title = "Volume"`, `viewModel.value = 42`, `formatter = { "\(Int($0))" }` | After init, `label.stringValue == "Volume"`, `slider.doubleValue == 42`, `captionLabel.stringValue == "42"` |
| captioned-slider-view-007 | updates-caption-live | Set `slider.doubleValue = 75` and invoke `sliderChanged(slider)` (the slider's target-action), with `formatter = { "\(Int($0))%" }` | `captionLabel.stringValue` becomes `"75%"` immediately, without any `viewModel.onChange` firing |
| captioned-slider-view-008 | commits-slider-value | `viewModel.settingObserver.value = 10`; set `slider.doubleValue = 30` and invoke `sliderChanged(slider)` | `viewModel.settingObserver.value == 30` after the call |
| captioned-slider-view-009 | skips-redundant-commits | `viewModel.settingObserver.value = 50`; set `slider.doubleValue = 50` (same value) and invoke `sliderChanged(slider)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| captioned-slider-view-010 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `slider.doubleValue`, and `captionLabel.stringValue` all update to reflect the new `viewModel` state |
| captioned-slider-view-011 | exposes-constituent-views | Construct the component, then access `.label`, `.slider`, `.captionLabel` from outside the type | All three properties are accessible and return the same `NSTextField`/`NSSlider`/`NSTextField` instances built during init |
| captioned-slider-view-012 | requires-designated-initializer | Attempt `CaptionedSliderView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| captioned-slider-view-013 | rejects-frame-only-initialization | Attempt `CaptionedSliderView(frame: .zero)` | The call traps with a fatal error; no instance is returned |

## Edge Cases

- Null/empty input: `viewModel` (`RangeViewModel<Double>`) and `formatter`
  are non-optional, non-escaping-typed constructor parameters; Swift's
  type system rules out `nil` for either. This is a MUST: the component
  provides, and needs, no nil-handling path for its two initializer
  parameters.
- Boundary values — inverted/zero-width range: source performs no
  `minValue < maxValue` validation before assigning `slider.minValue`/
  `slider.maxValue` from `viewModel`. If `viewModel.minValue >=
  viewModel.maxValue`, `CaptionedSliderView` adds no guard of its own; the
  resulting slider behavior is whatever `NSSlider` does for an
  equal-or-inverted range. This is a MUST: the component MUST NOT
  validate or correct `viewModel`'s bounds itself.
- Concurrent access: Not applicable — the class and the `formatter`
  closure are both `@MainActor`-isolated, so Swift's concurrency checker
  serializes all access to the main actor; there is no code path by which
  two threads can mutate the view simultaneously.
- Error states: Not applicable — every operation in this file (the
  slider's target-action, the formatter call, and the
  `settingObserver.value` write) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `RangeViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `CaptionedSliderView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.sync() }`, replacing
  whatever handler (if any) was previously registered on that
  `viewModel`. This is a MUST-level, source-traceable consequence of
  plain closure-property assignment: the component MUST NOT be assumed to
  coexist with another `onChange` observer already registered on the
  same `RangeViewModel` instance — constructing a second
  `CaptionedSliderView` (or any other observer) against the same view
  model silently drops the earlier handler.
- Caption can change a second time after release: `sliderChanged(_:)`
  sets the caption optimistically from `newValue` before writing to
  `settingObserver.value`. If that write causes `settingObserver` to
  clamp or otherwise transform the value and re-fire `viewModel.onChange`,
  `sync()` then overwrites the caption with `formatter(viewModel.value)`
  — the view model's actual accepted value, not the optimistic
  `newValue`. This is inferred from the interaction between
  `sliderChanged(_:)` and `sync()` rather than stated as a single line in
  source; it is a SHOULD-level note for implementors: the caption SHOULD
  be expected to update a second time, after slider release, without
  further user action, whenever the view model does not accept a value
  as-given.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `RangeViewModel<Double>` | — (required) | Supplies the row's title and min/max/current value; receives committed slider changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). |
| `formatter` | `@MainActor (Double) -> String` | — (required) | Maps the current or in-progress slider value to the caption text shown at the trailing edge of the row (e.g. a percentage or seconds string). |

## Deep Linking

Not applicable: `CaptionedSliderView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `CaptionedSliderView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes from `viewModel.title` and its caption text
comes from the caller-supplied `formatter`; both are values the caller
provides, so there is nothing for this component to localize itself.

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext` call; every state change is an
  instantaneous property assignment.
- **Increase Contrast**: Not applicable — `CaptionedSliderView.swift` sets
  no custom `NSColor` anywhere; whatever coloring the row has comes
  entirely from AppKit's default control rendering, which follows system
  Increase Contrast automatically.
- **Differentiate Without Color**: Not applicable — the current value is
  communicated through the slider's thumb position and the caption's
  text, not through any color-only signal; no color-coded state exists in
  source.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in `CaptionedSliderView.swift`; the row always renders once
constructed.

## Analytics

Not applicable: `CaptionedSliderView.swift` contains no analytics or
telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by `viewModel` and reports
  slider changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `RangeViewModel`/`settingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own subviews
  and its reference to `viewModel`/`formatter` for its own lifetime; it
  persists nothing beyond that.

## Logging

Not applicable: `CaptionedSliderView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)`, a
  `Slider(value:in:)` bound to the current value, and a trailing
  `Text(formatter(value)).monospacedDigit()`. SwiftUI has no direct
  analog to `contentHuggingPriority`/`contentCompressionResistancePriority`
  as raw numbers; give the `Slider` no fixed frame (it already expands to
  fill the `HStack`'s remaining space, mirroring slider-hugs-loosely) and
  apply `.fixedSize()` (or `.layoutPriority(1)`) to the caption `Text` to
  mirror caption-resists-compression. Update the caption's bound value on
  the `Slider`'s live drag (`onEditingChanged`/a `Binding` setter) rather
  than only on commit, to mirror updates-caption-live.
- **Compose**: Use a `Row` with `Modifier.weight(1f)` on the `Slider` (the
  Compose analog of the low hugging priority) between a leading
  `Text(title)` and a trailing `Text(formatter(value))` styled with a
  tabular/monospace-figure font feature. Drive the trailing caption from
  the `Slider`'s `onValueChange` callback immediately (mirroring
  updates-caption-live), and commit to the backing state/view-model from
  the same callback with an equality check before writing, mirroring
  skips-redundant-commits.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<span>` for the title, an `<input type="range" min max
  value>` given `flex: 1` (mirroring slider-hugs-loosely), and a trailing
  `<span>` for the caption given `flex: 0 0 auto; white-space: nowrap`
  plus a tabular-nums font (mirroring caption-resists-compression and
  caption-uses-monospaced-digits). Update the caption text on the range
  input's `onInput` handler immediately, and commit the value upward via
  a controlled `value`/`onChange` prop pair, comparing against the
  previous value before calling the parent's setter to mirror
  skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CaptionedSliderView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside
  the `ComposableSettings` namespace, conforming to `SettingsViewProtocol`.
  It composes three subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel`, an `NSSlider`, and a monospaced-digit
  `NSTextField` caption from `ComposableSettings.makeValueLabel
  (monospacedDigits: true)` — into one row via `ComposableSettings.makeRow`
  and `pinToEdges`, with the slider's horizontal content-hugging priority
  set to `1` and the caption's horizontal compression resistance set to
  `.required`. There is no UIKit code path in source; a UIKit port would
  replace `NSSlider`/`NSTextField` with `UISlider`/`UILabel` and the
  `target`/`action` pattern with `.addTarget(_:action:for: .valueChanged)`
  — UIKit has no `NSCoder`-vs-frame initializer split to fatal-error on
  both the way `requires-designated-initializer` and
  `rejects-frame-only-initialization` do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*,Auto`: a `TextBlock` for the title in
  column 0; a `Slider Minimum="{min}" Maximum="{max}"
  Value="{x:Bind Value, Mode=TwoWay}" HorizontalAlignment="Stretch"` in
  column 1 (the `*` column is the WinUI analog of the `1`-priority
  hugging — it lets the `Slider` claim the width left over after the
  `Auto`-sized title and caption columns); a trailing `TextBlock` bound to
  a formatted string (via an `IValueConverter` mirroring `formatter`) in
  column 2, whose `Auto` column width is the WinUI analog of
  caption-resists-compression (the column, and so the `TextBlock`, is
  never compressed below its content). Use the `Slider`'s `ValueChanged`
  event handler — not only the two-way `x:Bind` — to update the caption
  `TextBlock` immediately on every drag tick, mirroring
  updates-caption-live; write the committed value through a property
  setter that skips the assignment (and so skips raising
  `INotifyPropertyChanged`) when the incoming value already equals the
  current value, mirroring skips-redundant-commits.

## Design Decisions

- Decision: Update the caption label from the slider's raw `newValue`
  inside `sliderChanged(_:)`, ahead of writing to
  `viewModel.settingObserver.value`, rather than waiting for `sync()` to
  run off the round-tripped `viewModel.value`.
  Rationale: This gives the caption an immediate, per-tick update while
  dragging instead of a value that lags one `onChange` cycle behind the
  slider's own position.
  Approved: pending
- Decision: Set the slider's horizontal content-hugging priority to `1`
  and the caption label's horizontal compression-resistance priority to
  `.required`.
  Rationale: The source comment states this priority is "below the row
  spacer's `defaultLow` so the slider, not the gap, takes the width left
  over after the label and caption" — this makes the slider, rather than
  inter-item spacing or the caption, absorb any extra row width, while
  guaranteeing the caption is never truncated.
  Approved: pending
- Decision: Guard `viewModel.settingObserver.value`'s assignment with
  `if viewModel.settingObserver.value != newValue` before writing.
  Rationale: Avoids redundant writes to the observer (and any
  observer-driven feedback loop) when the slider reports a value that
  hasn't actually changed.
  Approved: pending
- Decision: Force a fatal error from both `init(coder:)` and the
  frame-only `init(frame:)`, leaving `init(viewModel:formatter:)` as the
  only usable initializer.
  Rationale: The view has no meaningful default state — it cannot render
  a title, range, or caption without a `viewModel` and a `formatter` — so
  both inherited `NSView` initializers that could construct it without
  those are intentionally disabled rather than left to produce a
  half-configured row.
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
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for CaptionedSliderView, covering row layout/priority behavior, live-versus-committed value sync, and one open accessibility question (slider/title label association) for review. |
