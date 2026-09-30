<!-- leaf: implement-general-view-1/color-picker-view--edge-cases · source: color-picker-view.md -->

# ColorPickerView

## Edge Cases

- Null/empty input: `viewModel` (`ColorViewModel`) is a non-optional
  parameter; nil is ruled out by the type system. The component provides,
  and needs, no nil-handling path for its one initializer parameter.
- Boundary values — out-of-range or out-of-gamut color: `ColorPickerView`
  performs no clamping or validation of `sender.color` before writing it
  to `viewModel.color`. Clamping happens one layer down: `ColorViewModel`'s
  `color` setter converts the incoming `NSColor` to `RGBAColor(newValue)`,
  and `RGBAColor.init(red:green:blue:alpha:)` clamps each channel to
  `[0, 1]` via a private `Double.clamped()` helper — so an out-of-gamut or
  malformed `NSColor` is always normalized before it reaches storage, but
  that normalization is `RGBAColor`'s behavior, not `ColorPickerView`'s.
  See **delegates-color-clamping**.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated,
  so Swift's concurrency checker serializes all access to the main actor;
  there is no code path by which two threads can mutate the view
  simultaneously.
- Error states: Not applicable — every operation in this file (the color
  well's target-action and the `viewModel.color` write) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ColorViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `ColorPickerView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in ... }`, replacing whatever
  handler (if any) was previously registered on that `viewModel`. See
  **owns-on-change**.
