<!-- leaf: implement-general-view-1/captioned-slider-view--part-2 · source: captioned-slider-view.md -->

# CaptionedSliderView — continued (part 2)

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)`, a
  `Slider(value:in:)` bound to the current value, and a trailing
  `Text(formatter(value)).monospacedDigit()`. SwiftUI has no direct
  analog to `contentHuggingPriority`/`contentCompressionResistancePriority`
  as raw numbers; give the `Slider` no fixed frame (it already expands to
  fill the `HStack`'s remaining space, mirroring slider-hugs-loosely) and
  apply `.fixedSize()` (or `.layoutPriority(1)`) to the caption `Text` to
  mirror caption-resists-compression. Drive the caption from the
  `Binding`'s setter — called on every drag tick as the `Slider` writes
  through it — to mirror updates-caption-live; `onEditingChanged` fires
  only at the start and end of a drag, so it is the analog of the commit
  step (mirroring commits-slider-value/skips-redundant-commits), not of
  the live update.
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
- **WinUI 3**: Build the row as a `Grid`
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

- **Decision**: Update the caption label from the slider's raw `newValue`
  inside `sliderChanged(_:)`, ahead of writing to
  `viewModel.settingObserver.value`, rather than waiting for `sync()` to
  run off the round-tripped `viewModel.value`.
  **Rationale**: This gives the caption an immediate, per-tick update
  while dragging instead of a value that lags one `onChange` cycle behind
  the slider's own position.
  **Approved**: pending
- **Decision**: Set the slider's horizontal content-hugging priority to
  `1` and the caption label's horizontal compression-resistance priority
  to `.required`.
  **Rationale**: The source comment states this priority is "below the
  row spacer's `defaultLow` so the slider, not the gap, takes the width
  left over after the label and caption" — this makes the slider, rather
  than inter-item spacing or the caption, absorb any extra row width,
  while guaranteeing the caption is never truncated.
  **Approved**: pending
- **Decision**: Guard `viewModel.settingObserver.value`'s assignment with
  `if viewModel.settingObserver.value != newValue` before writing.
  **Rationale**: Avoids redundant writes to the observer (and any
  observer-driven feedback loop) when the slider reports a value that
  hasn't actually changed.
  **Approved**: pending
- **Decision**: Force a fatal error from both `init(coder:)` and the
  frame-only `init(frame:)`, leaving `init(viewModel:formatter:)` as the
  only usable initializer.
  **Rationale**: The view has no meaningful default state — it cannot
  render a title, range, or caption without a `viewModel` and a
  `formatter` — so both inherited `NSView` initializers that could
  construct it without those are intentionally disabled rather than left
  to produce a half-configured row.
  **Approved**: pending
- **Decision**: Overwrite `viewModel.onChange` unconditionally in `init`,
  rather than composing with or preserving any handler already registered
  on that view model.
  **Rationale**: `RangeViewModel.onChange` is a single closure property;
  giving the row exclusive ownership of it avoids ambiguity about
  ordering multiple observers, at the cost of silently dropping any
  handler registered before construction (see
  **overwrites-view-model-onchange**).
  **Approved**: pending
- **Decision**: Assign `viewModel.minValue`/`viewModel.maxValue` straight
  to the slider's `minValue`/`maxValue` with no `minValue < maxValue`
  check.
  **Rationale**: Bounds validation is the view model's responsibility, if
  anywhere; adding a second check in the view would duplicate that
  concern and could silently mask a caller bug instead of surfacing it
  (see **does-not-validate-range**).
  **Approved**: pending
