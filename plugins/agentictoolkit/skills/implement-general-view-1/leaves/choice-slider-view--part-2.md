<!-- leaf: implement-general-view-1/choice-slider-view--part-2 · source: choice-slider-view.md -->

# ChoiceSliderView — continued (part 2)

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
