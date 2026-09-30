<!-- leaf: implement-general-view-1/choice-slider-view--edge-cases · source: choice-slider-view.md -->

# ChoiceSliderView

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
