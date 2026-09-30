<!-- leaf: implement-general-view-1/color-picker-view--part-2 · source: color-picker-view.md -->

# ColorPickerView — continued (part 2)

## Platform Notes

- **SwiftUI**: Compose a `ColorPicker(viewModel.title, selection: $color)`
  bound to a `Binding<Color>` that reads and writes through the same
  view-model color — passing `viewModel.title` as the picker's own label
  parameter (rather than `ColorPicker("", …)` with `.labelsHidden()` next
  to a separate `Text`) keeps the visual title programmatically linked to
  the control's accessible name, mirroring `commits-color-value`'s
  unconditional, no-equality-check write on every change.
- **Compose**: Use a `Row` with a leading `Text(title)` and a trailing
  color swatch `Box` (a fixed-size, rounded-rect `Modifier.background`)
  that on click opens a color-selection dialog or bottom sheet; commit
  the picked color back to the view model's state on every selection
  callback, again with no equality guard, mirroring `commits-color-value`.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<label htmlFor="…">` wrapping (or `for`-linked to) the
  title text and a trailing `<input type="color" id="…" value>` given a
  fixed width — the `<label for>` association replaces a bare `<span>`
  so the title is programmatically tied to the control; update the bound
  value on the input's `onInput`/`onChange` handler unconditionally,
  mirroring `commits-color-value`.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ColorPickerView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside
  the `ComposableSettings` namespace, conforming to `SettingsViewProtocol`.
  It composes two subviews — a `ThemedLabel` from
  `ComposableSettings.makeRowLabel` and a stock `NSColorWell` — into one
  row via `ComposableSettings.makeRow` and `pinToEdges`. There is no
  UIKit code path in source, and UIKit has no direct `NSColorWell`
  equivalent; a UIKit port would replace it with a custom swatch
  `UIButton` that presents a `UIColorPickerViewController` and receives
  the chosen color through `UIColorPickerViewControllerDelegate` rather
  than target/action. UIKit also has no `NSCoder`-vs-frame initializer
  split to fatal-error on both the way `rejects-coder-initialization`
  and `rejects-frame-only-initialization` do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column
  0, given the star-sized column so it absorbs the row's leftover width,
  and a `Button` styled as a swatch pinned in column 1 whose `Background`
  is a `SolidColorBrush` converted from the bound color (an
  `IValueConverter` mirroring the `NSColor`↔stored-value bridge
  `ColorViewModel.color` performs) — the star/auto split mirrors the
  AppKit row's flexible spacer between `label` and `colorWell`, keeping
  the swatch pinned to the row's trailing edge instead of hugging the
  title. The swatch `Button`'s `Click` handler
  opens a `Microsoft.UI.Xaml.Controls.ColorPicker` inside a `Flyout` — the
  WinUI analog of `NSColorWell` opening the system color panel, mirroring
  the Pressed state's inherited open-a-picker behavior. Wire the
  `ColorPicker`'s `ColorChanged` event to write the new color straight
  into the bound view-model property on every event, with no equality
  check before the write, mirroring `commits-color-value`'s unconditional
  commit; drive the swatch's `Background` from the same bound property so
  an external change (mirroring `syncs-on-external-change`) repaints the
  swatch without any additional code.

## Design Decisions

- **Decision**: Write `sender.color` into `viewModel.color` inside
  `colorChanged(_:)` on every invocation, with no comparison against the
  current value.
  **Rationale**: `colorChanged(_:)` only fires from `NSColorWell`'s
  target-action in response to a user-driven change committed in the
  system color panel, so a redundant same-value write is user-caused and
  harmless; unlike the sibling `CaptionedSliderView`, whose slider fires
  continuously during a drag and needs an equality guard to avoid a flood
  of redundant writes on every pixel of motion, a color well's action
  fires once per committed selection, so no guard was added here.
  **Approved**: pending
- **Decision**: Overwrite `viewModel.onChange` unconditionally in the
  initializer, replacing any handler already registered on that
  `ColorViewModel`.
  **Rationale**: Mirrors the same closure-property-assignment pattern used
  across the ComposableSettingsWindow row family; the view provides no
  way to compose with an existing observer. This constraint on callers is
  now captured as the **owns-on-change** requirement.
  **Approved**: pending
