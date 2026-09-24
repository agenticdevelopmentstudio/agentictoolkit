---
id: b02bf1ad-408a-4ebc-9e62-2ad5ae5220d2
title: StepperView
domain: agentictoolkit://recipes/stepper-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row pairing a title label, a monospaced value
  label, and an NSStepper bound to a bounded RangeViewModel<Int>.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
- numeric
- macos
depends-on: []
related:
- agentictoolkit://recipes/checkbox-view
- agentictoolkit://recipes/integer-field-view
- agentictoolkit://recipes/number-field-view
references: []
approved-by: ''
approved-date: ''
---

# StepperView

## Overview

`StepperView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/StepperView.swift`):
a title label leading, a monospaced numeric value label, and a trailing
`NSStepper`, bound to a `RangeViewModel<Int>`. Per the source's own doc
comment, it is for "small bounded counts (recents, retry limits, etc.) where
a slider's resolution is wrong but a free text field is too unbounded."
Unlike its sibling row types (`CheckboxView`'s `NSSwitch`, `IntegerFieldView`'s
text field), `NSStepper` draws no visible number of its own — only up/down
arrows — so `StepperView` pairs it with a separate `valueLabel` that the
component keeps in sync with the stepper's value on every change.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange `label`, `valueLabel`, and
  `stepper` in that order in a single horizontal row and MUST pin that row to
  the edges of the view.
- **builds-label-from-view-model-title**: `label` MUST be built via
  `ComposableSettings.makeRowLabel(viewModel.title)`.
- **builds-value-label-monospaced**: `valueLabel` MUST be built via
  `ComposableSettings.makeValueLabel(monospacedDigits: true)`.
- **resists-value-label-compression**: Component MUST set `valueLabel`'s
  horizontal content compression resistance priority to `.required`.
- **configures-stepper-bounds**: Component MUST set `stepper.minValue` to
  `Double(viewModel.minValue)` and `stepper.maxValue` to
  `Double(viewModel.maxValue)`.
- **fixes-stepper-increment**: Component MUST set `stepper.increment` to `1`,
  independent of the view model's range.
- **disables-stepper-wraparound**: Component MUST set `stepper.valueWraps` to
  `false`.
- **initializes-stepper-value**: Component MUST set `stepper.integerValue` to
  `viewModel.value` on construction.
- **wires-stepper-action**: Component MUST set `stepper.target` to itself and
  `stepper.action` to its `stepperChanged(_:)` selector.
- **initializes-value-label-text**: Component MUST set `valueLabel.stringValue`
  to the string form of `viewModel.value` on construction.
- **updates-value-label-on-change**: Whenever `stepperChanged(_:)` fires,
  component MUST set `valueLabel.stringValue` to the string form of the
  stepper's new `integerValue`, regardless of whether that value is committed.
- **commits-stepper-value**: Whenever `stepperChanged(_:)` fires and the
  stepper's new `integerValue` differs from `viewModel.settingObserver.value`,
  component MUST write the new value into `viewModel.settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the stepper's new value equals the
  current `settingObserver.value`.
- **replaces-view-model-onchange**: Component's initializer MUST assign its
  own closure to `viewModel.onChange`, unconditionally replacing whatever
  handler (if any) was previously registered on that view model instance.
- **syncs-on-external-change**: Whenever `viewModel.onChange` fires, component
  MUST re-set `label.stringValue`, `stepper.minValue`/`stepper.maxValue`,
  `stepper.integerValue`, and `valueLabel.stringValue` from `viewModel`.
- **exposes-constituent-views**: Component MUST expose `label`, `stepper`, and
  `valueLabel` as public, directly-accessible properties.
- **rejects-coder-initialization**: Component MUST NOT support construction
  via `init(coder:)`; that initializer MUST trigger a fatal error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main actor;
  the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes two stock `NSTextField`s and a stock
  `NSStepper` into a row.
- **Padding**: `ComposableSettings.makeRow([label, valueLabel, stepper])`
  passes three views, so `makeRow` inserts its flexible spacer at index 1 —
  between `label` and `valueLabel`, not between `valueLabel` and `stepper`
  (arranged order becomes `[label, spacer, valueLabel, stepper]`). The
  `NSStackView`'s `spacing` is `SettingsLayout.default[.rowSpacing]` = 8pt,
  applied by default between every adjacent pair; `makeRow` then zeroes only
  the spacer→`valueLabel` gap (`setCustomSpacing(0, after: spacer)`), leaving
  the `valueLabel`→`stepper` gap at the unmodified default 8pt. The visible
  effect is `label` pinned to the row's leading edge, all of the row's
  leftover width absorbed in the flexible gap right after it, and
  `valueLabel`/`stepper` sitting together, 8pt apart, at the trailing edge.
  `pinToEdges(row, of: self)` adds 0pt of outer padding beyond that.
- **Font**: `label` (`ComposableSettings.makeRowLabel`, `textRole: .button`)
  resolves to `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight,
  proportional system font, scaled by the active theme's `sizeScale`.
  `valueLabel` (`ComposableSettings.makeValueLabel(monospacedDigits: true)`,
  `textRole: .code`) resolves to `ThemeTypography.defaultStyle(.code)`: 12pt,
  regular weight, the system monospaced font, also scaled by `sizeScale` —
  chosen so a value that changes on every click doesn't reflow the row. Both
  repaint automatically on a theme change via `ThemePaletteObserver`.
  `NSStepper` draws no text of its own.
- **Background**: `label`/`valueLabel` — none (transparent); `ThemedLabel.init`
  sets `drawsBackground = false`, `isBordered = false`, `isBezeled = false`.
  `stepper` — no background is set in source; it keeps `NSStepper`'s default
  AppKit up/down bezel appearance.
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the active
  theme's foreground color at full strength. `valueLabel`
  (`role: .secondaryText`) resolves to a lower-emphasis theme color than
  `label`. Both are recomputed live on a theme change. `stepper`'s arrow tint
  is AppKit's own system rendering; the source sets no color on it.
- **Border**: Not applicable — `label`/`valueLabel` have `isBordered = false`
  (`ThemedLabel`); `stepper` keeps `NSStepper`'s default bezel, drawn by
  AppKit rather than configured in `StepperView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `StepperView.swift`.
- **Min/Max size**: Not applicable — no explicit width/height constraint is
  set on `label`, `valueLabel`, or `stepper` beyond `valueLabel`'s
  compression-resistance priority (not a size constraint); sizing follows
  each control's own intrinsic content size, the row's spacing math, and
  `pinToEdges`.

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `valueLabel` shows the current integer value as plain digits; `stepper.integerValue` matches. |
| At minimum value | `stepper.integerValue == stepper.minValue`; because `valueWraps == false`, further decrements are absorbed by `NSStepper`'s own bounds enforcement rather than wrapping to `maxValue`. This is `NSStepper`'s native behavior given the `minValue`/`valueWraps` configuration `StepperView` sets (see disables-stepper-wraparound), not custom drawing in this file. |
| At maximum value | Symmetric to the minimum case: `stepper.integerValue == stepper.maxValue`, further increments are absorbed rather than wrapping to `minValue`. |
| Pressed | Not applicable: the component renders no button of its own; `stepper`'s own arrow-press highlight while clicked is `NSStepper`'s default AppKit rendering, not custom to this file. |
| Disabled | Not implemented in `StepperView`; `isEnabled` is never read or set on `label`, `valueLabel`, or `stepper` in source. A caller may set `stepper.isEnabled` directly through the public `stepper` property, at which point `NSStepper`'s native disabled dimming applies. |
| Focused | Not styled by `StepperView`; any focus ring when `stepper` is tabbed to is `NSStepper`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized in source — no `setAccessibilityRole` call
  appears anywhere in `StepperView.swift`. `stepper` keeps `NSStepper`'s
  built-in AppKit accessibility role for a stepper control; `label` and
  `valueLabel` keep AppKit's default for a non-editable field (`ThemedLabel`
  sets `isEditable = false`) — static-text elements.
- **Label requirements**: Not implemented in source. `stepper` has no
  accessibility title/label linkage — no `setAccessibilityTitleUIElement`,
  `accessibilityLabel`, or `accessibilityTitle` call appears anywhere in
  `StepperView.swift`. Every sibling `ComposableSettings` row that pairs a
  label with an interactive control does link them —
  `CheckboxView.toggle.setAccessibilityTitleUIElement(label)` and
  `IntegerFieldView`'s wrapped `NumberFieldView.textField` do the same — so
  the omission here is a plain gap against the row's own family pattern, not
  a documented design choice. VoiceOver announces `stepper` as an unlabeled
  control, and `valueLabel`'s current number is a separate static text
  element rather than the stepper's own spoken value.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller (see
  States); a value change updates `stepper.integerValue` directly, which
  `NSStepper`'s own native accessibility value reporting picks up, with no
  explicit announcement call in source. `valueLabel`'s parallel text update is
  not itself linked to `stepper`'s accessibility value (see Label
  requirements, above).
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/keyboard-driven `NSView`/`NSControl` composition with no touch input
  path in source; the 44×44pt guidance is iOS/touch-specific. No
  `controlSize` is set on `stepper`, so it keeps `NSStepper`'s regular system
  metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The label and value-label text color resolves from the active theme's primaryText/secondaryText role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file. This would be settled by a theme-level contrast audit of primaryText/secondaryText against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| stepper-view-001 | arranges-row-layout | Construct `StepperView` with any `viewModel` | `label`, `valueLabel`, and `stepper` are subviews of a single row view, arranged left-to-right as `[label, spacer, valueLabel, stepper]` (see Appearance/Padding), that is pinned to the component's edges; no other subview sits outside that row |
| stepper-view-002 | builds-label-from-view-model-title | `viewModel.title = "Recent Files"` | `label.stringValue == "Recent Files"` after construction |
| stepper-view-003 | builds-value-label-monospaced | Construct with any `viewModel` | `valueLabel.font` is the system monospaced font (fixed-pitch), matching `ThemeTypography.defaultStyle(.code)` |
| stepper-view-004 | resists-value-label-compression | Construct with any `viewModel` | `valueLabel`'s horizontal content compression resistance priority is `.required` |
| stepper-view-005 | configures-stepper-bounds | `viewModel.minValue = 1`, `viewModel.maxValue = 20` | `stepper.minValue == 1.0` and `stepper.maxValue == 20.0` after construction |
| stepper-view-006 | fixes-stepper-increment | Construct with any `viewModel` | `stepper.increment == 1` |
| stepper-view-007 | disables-stepper-wraparound | Construct with any `viewModel` | `stepper.valueWraps == false` |
| stepper-view-008 | initializes-stepper-value | `viewModel.value = 5` | `stepper.integerValue == 5` after construction |
| stepper-view-009 | wires-stepper-action | Any initialized `StepperView` | `stepper.target === view`; `stepper.action == Selector("stepperChanged:")` |
| stepper-view-010 | initializes-value-label-text | `viewModel.value = 5` | `valueLabel.stringValue == "5"` after construction |
| stepper-view-011 | updates-value-label-on-change | Set `stepper.integerValue = 7` and invoke `stepperChanged(stepper)` | `valueLabel.stringValue == "7"` immediately after the call |
| stepper-view-012 | commits-stepper-value | `viewModel.settingObserver.value = 3`; set `stepper.integerValue = 4` and invoke `stepperChanged(stepper)` | `viewModel.settingObserver.value == 4` after the call |
| stepper-view-013 | skips-redundant-commits | `viewModel.settingObserver.value = 4`; set `stepper.integerValue = 4` (same value) and invoke `stepperChanged(stepper)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| stepper-view-014 | syncs-on-external-change | After construction, externally change `viewModel.title`, `viewModel.minValue`, `viewModel.maxValue`, and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `stepper.minValue`/`stepper.maxValue`, `stepper.integerValue`, and `valueLabel.stringValue` all update to reflect the new view-model state |
| stepper-view-015 | exposes-constituent-views | Construct the component, then access `.label`, `.stepper`, and `.valueLabel` from outside the type | All three properties are accessible and return the same instances built during init |
| stepper-view-016 | rejects-coder-initialization | Attempt `StepperView(coder: someCoder)` | The call traps with a fatal error; no instance is returned (requires a death/exit test harness, or a compile-time API-surface check that the initializer is unavailable — not a normal in-process XCTest assertion) |
| stepper-view-017 | rejects-frame-only-initialization | Attempt `StepperView(frame: .zero)` | The call traps with a fatal error; no instance is returned (same death/exit-test or API-surface caveat as stepper-view-016) |
| stepper-view-018 | confines-to-main-actor | Attempt to construct or mutate a `StepperView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| stepper-view-019 | replaces-view-model-onchange | Assign a spy closure to `viewModel.onChange`, then construct `StepperView(viewModel:)` | Invoking `viewModel.onChange(_:)` after construction runs `StepperView`'s own sync handler; the spy closure is not invoked |

## Edge Cases

- **Null/empty input**: `viewModel` (`RangeViewModel<Int>`) is a non-optional,
  typed constructor parameter; Swift's type system rules out `nil`. An empty
  `viewModel.title` produces a `label` with an empty string and no crash. The
  component provides, and needs, no nil-handling path for its one initializer
  parameter.
- **Boundary values**: At `stepper.integerValue == minValue` or `== maxValue`,
  `NSStepper`'s own bounds enforcement (given `valueWraps == false`) stops
  further movement in that direction rather than wrapping to the opposite
  bound; because `Int` bounds and a fixed `increment` of `1` always land
  exactly on both ends, every value in `[minValue, maxValue]` is reachable.
- **Contradictory bounds (`minValue > maxValue`)**: `StepperView.swift`
  forwards `viewModel.minValue`/`viewModel.maxValue` to
  `stepper.minValue`/`stepper.maxValue` with no validation or reordering — see
  the Design Decision on inverted-bounds handling.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see confines-to-main-actor).
- **Error states**: Not applicable — every operation in this file (the
  stepper's target-action, the label/value-label text updates, and the
  `settingObserver.value` write) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- **Offline/disconnected state**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `RangeViewModel<Int>`.
- **Overwritten external observer**: `viewModel.onChange` is a single closure
  property; per replaces-view-model-onchange, `StepperView`'s initializer
  unconditionally overwrites it, replacing whatever handler (if any) was
  previously registered — the same closure-overwrite behavior `CheckboxView`
  and `IntegerFieldView` document. The component MUST NOT be assumed to
  coexist with another `onChange` observer already registered on the same
  view model instance.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.RangeViewModel<Int>` | — (required) | Supplies the row's title, min/max bounds, and current integer value; receives committed stepper changes via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the component's own `sync` handler (see Edge Cases). |

## Deep Linking

Not applicable: `StepperView` is a row inside a composable settings window,
not a navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `StepperView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its own.
The row's title comes entirely from `viewModel.title`, a value the caller
provides, and the displayed value is a plain `Int`-to-`String` interpolation
of `viewModel.value`/`stepper.integerValue`, not a localizable phrase — so
there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears in source; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: `StepperView.swift` sets no custom `NSColor` on `stepper`; the labels' colors come from the theme's `.primaryText`/`.secondaryText` roles, and `NSStepper`'s own bezel rendering follows the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — the current value is shown as digits in `valueLabel`. Reaching a bound stops further movement (see disables-stepper-wraparound) rather than wrapping, but nothing in source shows `NSStepper` rendering an arrow as disabled at `minValue`/`maxValue`; it only absorbs the click. `StepperView` introduces no color-only cue of its own either way. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `StepperView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `StepperView.swift` contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only displays a value supplied by `viewModel` and reports stepper
  changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — `StepperView.swift` performs no read/write to
  disk, `UserDefaults`, or any other store directly; persistence is owned by
  `RangeViewModel<Int>`/`UserSettingObserver`/`UserSetting`, which are not
  part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `valueLabel`, `stepper`) and its reference to `viewModel` for its
  own lifetime; it persists nothing itself beyond that.

## Logging

Not applicable: `StepperView.swift` contains no logging call (no `print`,
`os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: `HStack { Text(viewModel.title); Spacer(); Text("\(value)").monospacedDigit(); Stepper("", value: $value, in: minValue...maxValue) }`, with `.labelsHidden()` on the `Stepper` since the leading `Text` already carries the title. Give the value `Text` an `.accessibilityHidden(true)` and instead attach `.accessibilityValue("\(value)")` to the `Stepper` itself, and `.accessibilityLabel(viewModel.title)` — closing the gap flagged in Label requirements, rather than reproducing it. Write to the bound state's setter with an equality guard before committing, mirroring skips-redundant-commits.
- **Compose**: A `Row` with `Text(title)` leading, then a monospaced `Text(value.toString())`, then two small `IconButton`s (`Icons.Default.KeyboardArrowUp`/`Down`) in place of a bare stepper — Compose has no built-in stepper control. Fix the step to `1` (mirroring fixes-stepper-increment), clamp against `minValue`/`maxValue` with no wraparound (mirroring disables-stepper-wraparound), and give the button pair a `Modifier.semantics { contentDescription = title }` and `stateDescription = value.toString()` — the Compose analog of the flagged missing accessibility link.
- **React/Web**: A flex row with a `<span>` title, a monospaced `<span>` showing the value, and a `<button>` pair (`aria-label="Decrease"`/`"Increase"`) or a native `<input type="number">` restricted to integer steps. Whichever control is used, wire `aria-labelledby` from the increment/decrement controls back to the title, and set `aria-valuenow`/`aria-valuemin`/`aria-valuemax` on a `role="spinbutton"` wrapper — the web analog of the accessibility link this source omits. Clamp at the bounds with no wraparound, mirroring disables-stepper-wraparound.
- **AppKit/UIKit** (source platform): Source file `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/StepperView.swift`. A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside the `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It composes a label, a monospaced value label, and an `NSStepper` into one row via `ComposableSettings.makeRow`/`pinToEdges`, wires the stepper's target/action to `stepperChanged(_:)`, and keeps all three subviews synced to `RangeViewModel<Int>` on init and on `onChange`. There is no UIKit code path in source; a UIKit port would replace `NSStepper` with `UIStepper` (UIKit's direct analog — also arrows-only, no built-in value display) and the `target`/`action` pattern with `.addTarget(_:action:for: .valueChanged)`, still pairing it with a separate `UILabel` for the value the way this source pairs `NSStepper` with `valueLabel`. (Note: the frame-only initializer's fatal-error message string, `"init(frame frameRect: NSRect"`, is missing its closing parenthesis in source — a copy-paste artifact of the initializer's own signature, not a design choice; a port should write its own clear message rather than carry the typo forward.)
- **WinUI 3** (the reason this recipe exists): WinUI ships no bare, arrows-only stepper control equivalent to `NSStepper`/`UIStepper`. The closest concrete option is a `NumberBox` with `SpinButtonPlacementMode="Inline"`, `Minimum="{x:Bind MinValue}"`, `Maximum="{x:Bind MaxValue}"`, and `SmallChange="1"` (the direct analog of fixes-stepper-increment), laid out as a `Grid` with columns `*,Auto` — a `TextBlock` for the title in column 0, the `NumberBox` in column 1. Note the divergence from source: `NumberBox` always exposes an editable text field, unlike this source's read-only `valueLabel`; if a non-editable value display is required instead, compose the row from a `TextBlock` (monospaced, via `FontFamily="Cascadia Mono"`) plus a vertical pair of small `RepeatButton`s (chevron-up/chevron-down glyphs) rather than `NumberBox`. Either way, set `AutomationProperties.Name`/`LabeledBy` on the interactive control(s) to the title `TextBlock` — the WinUI analog of the `setAccessibilityTitleUIElement` link this source's sibling rows have but `StepperView` itself is missing (see Label requirements); porting this component to WinUI is the moment to add it rather than carry the gap forward. Handle `NumberBox.ValueChanged` (or the `RepeatButton`s' `Click` events) to write the already-bounded, committed value with an equality guard before writing, mirroring skips-redundant-commits.

## Design Decisions

**Decision**: Show the current value in a separate, monospaced `valueLabel`
rather than relying on `NSStepper` to display it.
**Rationale**: `NSStepper` renders only its up/down arrow control and carries
no visible number of its own; pairing it with a dedicated `valueLabel`,
kept in sync in `sync()` and `stepperChanged(_:)`, makes the current count
visible without requiring a user to press or focus the stepper.
**Approved**: pending

**Decision**: Fix `stepper.increment` at `1` regardless of the view model's
`minValue`/`maxValue` range.
**Rationale**: Per the source's own doc comment, `StepperView` targets "small
bounded counts (recents, retry limits, etc.)" where each click should move
by the smallest meaningful unit; the type is generic only over the bound
(`RangeViewModel<Int>`), not the step size, so a caller with a wide range
gets the same one-at-a-time increments as a caller with a narrow one.
**Approved**: pending

**Decision**: Set `valueLabel`'s horizontal content compression resistance to
`.required` while leaving `label` and `stepper` at their default priorities.
**Rationale**: In a tight row, `NSStackView` shrinks the lowest-resistance
view first; a `.required` floor on `valueLabel` keeps the numeric value —
the one piece of information the row cannot afford to truncate — from being
the view that gives way before the title label does.
**Approved**: pending

**Decision**: Disable wraparound (`stepper.valueWraps = false`).
**Rationale**: For a bounded count like a retry limit, wrapping from
`maxValue` back to `minValue` (or the reverse) on one more click would
silently jump the setting to the opposite end of its range; disabling wrap
keeps a repeated click at a bound a no-op instead.
**Approved**: pending

**Decision**: Forward `viewModel.minValue`/`viewModel.maxValue` straight to
`stepper.minValue`/`stepper.maxValue` with no validation, reordering, or
clamping when the range is inverted (`minValue > maxValue`).
**Rationale**: Callers MUST supply `minValue <= maxValue`; `RangeViewModel<Int>`
is expected to guarantee an ordered range at construction, so `StepperView`
does not duplicate that check. An inverted range that reaches this file falls
through to `NSStepper`'s own unspecified handling rather than being coerced
or clamped here (contrast `IntegerFieldView`, which explicitly detects and
skips clamping on this case).
**Approved**: pending

**Decision**: Unconditionally assign `viewModel.onChange = { [weak self] _ in
self?.sync() }` in the initializer, replacing any closure already registered
on that view model instance (see replaces-view-model-onchange).
**Rationale**: `StepperView` owns keeping its three subviews in sync with
`viewModel`'s current state; a single-owner `onChange` closure is the
simplest way to guarantee `sync()` runs on every external change, at the
cost of `StepperView` being incompatible with a caller that also wants to
observe the same view model instance directly — the same trade-off
`CheckboxView` and `IntegerFieldView` make.
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
