---
id: 0cbe1932-5c7e-4546-829d-0294708d499c
title: SliderView
domain: agentictoolkit://recipes/slider-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings-window row pairing a title label with an NSSlider bound to a RangeViewModel<Double>,
  syncing value and range from the view model.
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
related:
- agentictoolkit://recipes/captioned-slider-view
references: []
approved-by: ''
approved-date: ''
---

# SliderView

## Overview

`SliderView` is a macOS `ComposableSettings` row: a title label and an
`NSSlider` in one horizontal row, with no trailing caption (contrast with
the sibling `CaptionedSliderView`, which adds a formatter-derived value
label). The row is driven by a `RangeViewModel<Double>`: the view sets the
slider's range and value from the view model at construction, writes the
user's slider interactions back into the view model's `settingObserver`,
and re-synchronizes the label text and the slider's range and value
whenever the view model reports an external change — including the range,
which the sibling `CaptionedSliderView` does not re-apply after
construction.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label and the
  slider in a single horizontal row, and MUST pin that row to the edges of
  the view.
- **sets-slider-range**: Component MUST set the slider's `minValue` and
  `maxValue` from `viewModel.minValue` and `viewModel.maxValue` at
  initialization.
- **slider-hugs-loosely**: Component MUST set the slider's horizontal
  content-hugging priority to `1` — below the row spacer's `defaultLow`
  priority — so the slider, not the inter-item spacing, takes the width
  left over after the label.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title` and the
  slider's value to `viewModel.value`.
- **commits-slider-value**: Component MUST write the slider's new value
  into `viewModel.settingObserver.value` whenever the slider's action
  fires and the new value differs from the current
  `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the slider's new value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-synchronize the label's
  text and the slider's `minValue`, `maxValue`, and `doubleValue` —
  re-reading `viewModel.title`, `viewModel.minValue`, `viewModel.maxValue`,
  and `viewModel.value` — whenever `viewModel.onChange` fires.
- **exposes-constituent-views**: Component MUST expose `label` and
  `slider` as public, directly-accessible properties.
- **rejects-coder-initialization**: Component MUST NOT support
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
  between the label and the slider (`[label, spacer, slider]`) and sets
  the `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` =
  8pt; that 8pt gap applies between label→spacer, while `makeRow`
  explicitly zeroes the spacer→slider gap
  (`setCustomSpacing(0, after: spacer)`) so the spacer's own width is the
  only thing between the label and the slider. `pinToEdges` pins the
  row's top/leading/trailing/bottom directly to `SliderView`'s edges with
  no additional constant, so the component contributes 0pt of its own
  outer padding beyond that internal 8pt / 0pt spacing.
- **Font**: The label (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography`'s `.button` style: 13pt, medium weight, proportional
  system font (`ThemeTypography.swift`: `case .button: return
  FontStyle(size: 13, weight: .medium)`). The size scales with the active
  theme's `sizeScale` and the label repaints automatically on a theme
  change via `ThemePaletteObserver` (`ThemedLabel.applyTheme` re-reads
  `palette.font(textRole)` on every palette update).
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false`
  on the label, and neither `SliderView` nor the row `NSStackView` sets
  `wantsLayer` or a background color of its own. The slider is a plain,
  unconfigured `NSSlider()` using AppKit's default rendering.
- **Foreground/Text**: The label (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength
  (`SemanticPalette.color(.primaryText)`, exposed as
  `SemanticPalette.primaryText`), recomputed live on a theme change via
  `ThemePaletteObserver`.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in `SliderView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `SliderView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `SliderView.swift`; the slider's width is governed
  entirely by the horizontal content-hugging priority (`1`) set in
  `init`, with no compression-resistance override on either subview.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; slider is at `viewModel.value` with its range set to `viewModel.minValue`/`viewModel.maxValue`. |
| Dragging | No custom dragging visual: the slider's `NSSlider` default `isContinuous` behavior is left unmodified in source, so the action fires on every drag tick (not only on release), each tick invoking commits-slider-value/skips-redundant-commits; there is no caption or other view state to update, so the only visible motion is the slider's own native thumb tracking. |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are `NSSlider`'s default AppKit rendering, not custom to this file. |
| Disabled | Not applicable: `isEnabled` is never set on the slider or text field in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and label use AppKit's default `NSControl` focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call
  appears in source. `NSSlider` and `NSTextField` each carry AppKit's
  built-in accessibility role (slider, static text) automatically.
- **Label requirements**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. The label and the slider are laid out as sibling
  views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on
  the slider linking it to the label text — confirmed by comparison with
  sibling row views in the same directory: `CheckboxView.swift`,
  `NumberFieldView.swift`, and `PopupMenuChoiceView.swift` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their
  control, but `SliderView.swift` does not do so for `slider`. What is
  missing: whether VoiceOver announces the row's title when focus lands
  on the slider, or only "slider" with no further context. What would
  settle it: a VoiceOver pass over an instantiated row, or an explicit
  decision to call `slider.setAccessibilityTitleUIElement(label)` in
  `init` and in the `onChange` re-sync closure.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.
- **Minimum contrast ratio**: NEEDS REVIEW: Not implemented in source. The
  the leading label's text text color resolves from the active theme's primaryText role against
  the hosting background at runtime; the component performs no contrast
  check, so whether a given theme's resolved pair meets 4.5:1 cannot be
  determined from this file. This would be settled by a theme-level
  contrast audit of primaryText against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| slider-view-001 | arranges-row-layout | Construct `SliderView` with any `viewModel` | The row `NSStackView`'s arranged subviews are exactly `[label, <row-spacer inserted by makeRow>, slider]` in that order; that stack view is `SliderView`'s only subview and is pinned to its edges; no other layout container appears |
| slider-view-002 | sets-slider-range | `viewModel.minValue = 0`, `viewModel.maxValue = 1` | After init, `slider.minValue == 0` and `slider.maxValue == 1` |
| slider-view-003 | slider-hugs-loosely | Construct the component | After init, `slider.contentHuggingPriority(for: .horizontal).rawValue == 1` |
| slider-view-004 | initializes-from-view-model | `viewModel.title = "Volume"`, `viewModel.value = 42` | After init, `label.stringValue == "Volume"` and `slider.doubleValue == 42` |
| slider-view-005 | commits-slider-value | `viewModel.settingObserver.value = 10`; set `slider.doubleValue = 30` and invoke `sliderChanged(slider)` (the slider's target-action) | `viewModel.settingObserver.value == 30` after the call |
| slider-view-006 | skips-redundant-commits | Substitute a counting `settingObserver` test double whose `value` setter increments a write counter; set its `value = 50`, reset the counter to 0, then set `slider.doubleValue = 50` (same value) and invoke `sliderChanged(slider)` | The counting `settingObserver`'s write counter stays at 0 after the call |
| slider-view-007 | syncs-on-external-change | After construction, externally change `viewModel.title`, `viewModel.minValue`, `viewModel.maxValue`, and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `slider.minValue`, `slider.maxValue`, and `slider.doubleValue` all update to reflect the new `viewModel` state |
| slider-view-008 | exposes-constituent-views | Construct the component, then access `.label` and `.slider` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSSlider` instances built during init |
| slider-view-009 | rejects-coder-initialization | Attempt `SliderView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| slider-view-010 | rejects-frame-only-initialization | Attempt `SliderView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| slider-view-011 | syncs-on-external-change | Change the value on the backing `UserSetting` that `viewModel.settingObserver` observes (not by calling `viewModel.onChange` directly), then await one main-queue turn (the `.dropFirst().receive(on: DispatchQueue.main)` Combine hop in `UserSettingObserver`) | `label.stringValue`, `slider.minValue`, `slider.maxValue`, and `slider.doubleValue` are unchanged immediately after the setting write, and only update to reflect the new state after that main-queue turn elapses |
| slider-view-012 | sets-slider-range | Construct `SliderView` with `viewModel.minValue = 10`, `viewModel.maxValue = 0` (an inverted range; a zero-width case such as `minValue = maxValue = 5` is equivalent) | `slider.minValue == 10` and `slider.maxValue == 0` — assigned unchanged from `viewModel`, with no clamping, swapping, or correction |

## Edge Cases

- Null/empty input: `viewModel` (`RangeViewModel<Double>`) is a
  non-optional, non-escaping-typed constructor parameter, so Swift's type
  system rules out `nil` at the call site — this is a property of the
  parameter's type, not a behavior the component implements, so the
  component provides, and needs, no nil-handling path of its own for its
  one initializer parameter.
- Boundary values — inverted/zero-width range: source performs no
  `minValue < maxValue` validation before assigning `slider.minValue`/
  `slider.maxValue` from `viewModel`, either at init or in the `onChange`
  re-sync (see slider-view-012). If `viewModel.minValue >= viewModel.maxValue`,
  `SliderView` adds no guard of its own; the resulting slider behavior is
  whatever `NSSlider` does for an equal-or-inverted range. This is an
  absence rather than an enforced rule: nothing in source validates or
  corrects `viewModel`'s bounds.
- Concurrent access: Not applicable — the class and its `onChange` closure
  are both `@MainActor`-isolated, so Swift's concurrency checker
  serializes all access to the main actor; there is no code path by which
  two threads can mutate the view simultaneously.
- Error states: Not applicable — every operation in this file (the
  slider's target-action and the `settingObserver.value` write) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing
  API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `RangeViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property, and `SliderView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in ... }`. See the one-observer-
  per-view-model Design Decision for the resulting contract and its
  rationale.
- Asynchronous re-sync timing: `viewModel.onChange` is driven through
  `ComposableSettings.UserSettingObserver`
  (`packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift`),
  whose `onChange` is delivered from a Combine pipeline that does
  `.dropFirst().receive(on: DispatchQueue.main).sink { ... }` on the
  setting's `$currentValue` publisher. A commit made inside
  `sliderChanged(_:)` therefore does not call this view's `onChange`
  re-sync back synchronously within the same call; the label/range/value
  re-sync in syncs-on-external-change happens on a later turn of the main
  dispatch queue, not inline with the triggering slider action. This is a
  SHOULD-level implementor note: the range and value re-sync SHOULD be
  expected to lag one dispatch-queue turn behind a commit made by this
  same view.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `RangeViewModel<Double>` | — (required) | Supplies the row's title and min/max/current value; receives committed slider changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own re-sync handler (see Edge Cases). |

## Deep Linking

Not applicable: `SliderView` is a row inside a composable settings window,
not a navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `SliderView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes from `viewModel.title`, a `String` value the
caller provides through the view model, not a literal set on
`label.stringValue` in this file; there is nothing for this component to
localize itself.

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext` call; every state change is an
  instantaneous property assignment.
- **Increase Contrast**: Not applicable — `SliderView.swift` sets no
  custom `NSColor` anywhere; whatever coloring the row has comes entirely
  from `ThemedLabel`'s palette-driven text color and `NSSlider`'s default
  AppKit rendering, both of which follow system Increase Contrast
  automatically.
- **Differentiate Without Color**: Not applicable — the current value is
  communicated only through the slider's thumb position; there is no
  caption or other color-coded signal in source to differentiate.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in `SliderView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `SliderView.swift` contains no analytics or telemetry
call.

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
  and its reference to `viewModel` for its own lifetime; it persists
  nothing beyond that.

## Logging

Not applicable: `SliderView.swift` contains no logging call (no `print`,
`os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)` and a
  `Slider(value:in:)` bound to the current value and range. SwiftUI has no
  direct analog to `contentHuggingPriority` as a raw number; give the
  `Slider` no fixed frame — it already expands to fill the `HStack`'s
  remaining space, mirroring slider-hugs-loosely. Drive the `Slider`'s
  `in:` bounds from `@State`/`@ObservedObject` properties fed by the view
  model, updating them (not just the value) whenever the view model
  publishes a change, to mirror syncs-on-external-change's re-application
  of range as well as value.
- **Compose**: Use a `Row` with a leading `Text(title)` and a `Slider`
  given `Modifier.weight(1f)` (the Compose analog of the low hugging
  priority) whose `valueRange` is bound to the view model's min/max.
  Commit to the backing state/view-model from the `Slider`'s
  `onValueChange` callback with an equality check before writing,
  mirroring skips-redundant-commits, and re-read both the value and the
  `valueRange` whenever the backing view model changes, mirroring
  syncs-on-external-change.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<span>` for the title and an `<input type="range" min max
  value>` given `flex: 1` (mirroring slider-hugs-loosely). Commit the
  value upward via a controlled `value`/`onChange` prop pair, comparing
  against the previous value before calling the parent's setter to mirror
  skips-redundant-commits; re-render the input's `min`/`max`/`value`
  attributes together whenever the parent's bound range or value props
  change, to mirror syncs-on-external-change.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SliderView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside
  the `ComposableSettings` namespace, conforming to `SettingsViewProtocol`.
  It composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and a plain `NSSlider()` — into one row
  via `ComposableSettings.makeRow` and `pinToEdges`, with the slider's
  horizontal content-hugging priority set to `1`. There is no UIKit code
  path in source; a UIKit port would replace `NSSlider`/`NSTextField` with
  `UISlider`/`UILabel` and the `target`/`action` pattern with
  `.addTarget(_:action:for: .valueChanged)` — `UIView` has the same
  `init(coder:)`/`init(frame:)` split as `NSView`, so a UIKit port would
  fatal-error on both initializers the way rejects-coder-initialization
  and rejects-frame-only-initialization do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*`: a `TextBlock` for the title in column
  0, and a `Slider Minimum="{x:Bind Min, Mode=OneWay}"
  Maximum="{x:Bind Max, Mode=OneWay}" Value="{x:Bind Value, Mode=TwoWay}"
  HorizontalAlignment="Stretch"` in column 1 (the `*` column is the WinUI
  analog of the `1`-priority hugging — it lets the `Slider` claim the
  width left over after the `Auto`-sized title column). Bind `Minimum`/
  `Maximum` with `Mode=OneWay` from the same view-model properties as
  `Value`, so a change pushed from the view model updates the slider's
  range as well as its position, mirroring syncs-on-external-change (a
  plain `Value`-only `x:Bind` would miss the range re-application this
  component performs that its sibling `CaptionedSliderView` does not).
  Write the committed value through a property setter that skips the
  assignment (and so skips raising `INotifyPropertyChanged`) when the
  incoming value already equals the current value, mirroring
  skips-redundant-commits.

## Design Decisions

- Decision: Re-apply `slider.minValue` and `slider.maxValue` (in addition
  to the label text and the slider's value) inside the `onChange` handler,
  not just at initialization — unlike the sibling `CaptionedSliderView`,
  whose `sync()` leaves the slider's range untouched after construction.
  Rationale: Lets a caller mutate the view model's range after the row is
  built and have the slider reflect the new bounds without recreating the
  view.
  Approved: pending
- Decision: Set the slider's horizontal content-hugging priority to `1`.
  Rationale: The source comment states this priority is "below the row
  spacer's `defaultLow` so the slider, not the gap, takes the width left
  over after the label" — this makes the slider, rather than inter-item
  spacing, absorb any extra row width.
  Approved: pending
- Decision: Guard `viewModel.settingObserver.value`'s assignment with
  `if viewModel.settingObserver.value != newValue` before writing.
  Rationale: Avoids redundant writes to the observer (and any
  observer-driven feedback loop) when the slider reports a value that
  hasn't actually changed.
  Approved: pending
- Decision: Force a fatal error from both `init(coder:)` and the
  frame-only `init(frame:)`, leaving `init(viewModel:)` as the only usable
  initializer.
  Rationale: The view has no meaningful default state — it cannot render
  a title or range without a `viewModel` — so both inherited `NSView`
  initializers that could construct it without one are intentionally
  disabled rather than left to produce a half-configured row.
  Approved: pending
- Decision: Assign `viewModel.onChange` unconditionally in `init`, without
  preserving or chaining any handler already registered on the same
  `RangeViewModel` instance — constructing a second `SliderView` (or any
  other observer) against the same view model silently drops the earlier
  handler.
  Rationale: `SliderView` owns its view model's re-sync handler for the
  view's lifetime; supporting more than one simultaneous observer on a
  single `RangeViewModel` would need a multicast mechanism the source
  does not implement, so one view per view model is the stated limit
  rather than an unstated side effect.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`keyboard-navigable` and `screen-reader-support` rest on `NSSlider`/`NSTextField`'s
default AppKit accessibility and focus behavior; `screen-reader-support` is
`partial` because source sets no `accessibilityLabel`/`accessibilityTitleUIElement`
linking the slider to the label (see Accessibility, the open question on label
requirements). The other rows rest on source composing only stock
`NSView`/`NSControl` instances with no custom drawing, network, or persistence
code of its own.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for SliderView, covering row layout/priority behavior, value-and-range sync on external change, and one open accessibility question (slider/title label association) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: add `related` link to CaptionedSliderView; rename requirement to rejects-coder-initialization and its citations; fix the AppKit/UIKit platform note's wrong claim about UIKit's initializer split; name the row's exact arranged subviews and require a counting settingObserver test double in the affected test vectors; add test vectors for the async re-sync path and the inverted/zero-width range; drop RFC 2119 wording from two purely observational edge cases; move the overwritten-observer edge case into a Design Decision; remap the Compliance table's semantic-markup row to screen-reader-support and add the statuses' source rationale; records the unverified theme-token contrast as an open question. |
