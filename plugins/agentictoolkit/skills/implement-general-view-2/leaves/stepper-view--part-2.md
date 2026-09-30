<!-- leaf: implement-general-view-2/stepper-view--part-2 · source: stepper-view.md -->

# StepperView — continued (part 2)

**Rules** (cite as `implement-general-view-2/stepper-view--part-2#<slug>`):

- `decision` MUST — Forward viewModel.minValue/viewModel.maxValue straight to stepper.minValue/stepper.maxValue with no validation, …

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
