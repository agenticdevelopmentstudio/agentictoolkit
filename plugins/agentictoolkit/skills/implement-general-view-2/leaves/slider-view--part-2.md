<!-- leaf: implement-general-view-2/slider-view--part-2 · source: slider-view.md -->

# SliderView — continued (part 2)

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
