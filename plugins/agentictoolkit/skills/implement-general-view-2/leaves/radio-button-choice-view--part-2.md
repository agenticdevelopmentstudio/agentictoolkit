<!-- leaf: implement-general-view-2/radio-button-choice-view--part-2 · source: radio-button-choice-view.md -->

# RadioButtonChoiceView — continued (part 2)

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only displays a value supplied by `viewModel` and reports radio
  selections back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `ChoiceViewModel`/`settingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `radioButtons`, the two `NSStackView`s) and its reference to
  `viewModel` for its own lifetime; it persists nothing beyond that.

## Platform Notes

- **SwiftUI**: `Picker("", selection: $value) { ForEach(choices) { Text($0
  .label).tag($0.value) } }.pickerStyle(.radioGroup).labelsHidden()`,
  preceded by its own `Text(viewModel.title)` heading, is the closest native
  analog — `.radioGroup` is a macOS-only `Picker` style that renders one
  native radio button per case, matching `builds-one-radio-button-per-choice`
  directly. SwiftUI has no first-class axis toggle on `.radioGroup`, so
  matching `axis` requires composing custom `Toggle`-styled radio rows inside
  a `VStack`/`HStack` chosen by `axis`, rather than relying on the built-in
  style, when a horizontal layout is required. Commit the selection to the
  backing view model from the `Binding`'s setter with an equality guard,
  mirroring skips-redundant-commits.
- **Compose**: There is no Material 3 "radio group" composable; build a
  `Column`/`Row` (chosen by axis) of `RadioButton(selected = choice.value ==
  value, onClick = { ... })` each paired with a trailing `Text(choice.label)`,
  wrapped in `Modifier.selectableGroup()` on the container — the Compose
  analog of the group-to-heading accessibility linkage this component's
  source does not implement (see Accessibility). Guard the write with an
  equality check before calling the parent's setter, mirroring
  skips-redundant-commits.
- **React/Web**: A `<fieldset>` with a `<legend>{title}</legend>` — the
  direct web analog of the heading-to-group linkage this component's source
  does not implement (see Accessibility) — wrapping a flex container (`flex-direction: column` or
  `row` per axis) of `<input type="radio" name={groupName} value=...
  checked={...}>` elements, each paired with its own `<label>` set from
  `choice.label`. Giving every input the same `name` attribute is the web's
  own native mutual-exclusivity mechanism, the direct analog of AppKit's
  same-superview radio exclusivity noted in Edge Cases. Commit the new value
  on each input's `onChange`, comparing against the previous value first to
  mirror skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/RadioButtonChoiceView.swift`.
  A macOS-only (`import AppKit`), generic-over-`Value` `NSView` subclass,
  isolated to the main actor via Swift's `@MainActor`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes a `ThemedLabel` heading (via `ComposableSettings.makeRowLabel`)
  and, for each choice, one native `.radio`-type `NSButton` built from
  `NSButton(radioButtonWithTitle:target:action:)` wired to the
  `radioChanged(_:)` action, into two nested `NSStackView`s
  (`controlsStack.orientation`/`.alignment` driven by `axis`) pinned via
  `pinToEdges` — unlike its sibling row views, it does not use
  `ComposableSettings.makeRow`. Selection state is AppKit's `NSButton.state`
  (`.on`/`.off`); the `radioButtons` array is exposed as `public
  private(set)` so callers can read but not replace it. There is no UIKit
  code path in source; UIKit has no native radio-button control, so a port
  would need `UIButton`s manually toggled in a target/action handler
  (clearing every sibling's selected state before setting the tapped one),
  or a `UISegmentedControl`/checkmarked table rows as an alternate native
  composition.
- **WinUI 3** (the reason this recipe exists): Use the
  `Microsoft.UI.Xaml.Controls.RadioButtons` control directly — it is a
  near 1:1 analog of this component: its `Orientation` property
  (`Vertical`/`Horizontal`) is the direct WinUI equivalent of the `axis`
  parameter (mirroring lays-out-controls-along-axis and
  aligns-controls-stack-by-axis in one property, since `RadioButtons`
  handles the alignment difference between orientations internally), and its
  `Header` property is the direct analog of this component's heading
  `label` — critically, `RadioButtons.Header` is exposed to `UIA` as the
  group's accessible name automatically, which is the exact linkage this
  component's own source leaves unimplemented (see Accessibility). Bind
  `ItemsSource="{x:Bind Choices}"` with
  `DisplayMemberPath="Label"`, and `SelectedItem="{x:Bind SelectedChoice,
  Mode=TwoWay}"` through a property setter that skips the assignment (and so
  skips raising `INotifyPropertyChanged`) when the incoming value already
  equals the current one, mirroring skips-redundant-commits. `RadioButtons`'
  built-in `SelectionChanged` event is the WinUI analog of `radioChanged(_:)`.

## Design Decisions

- **Decision**: Compose two nested `NSStackView`s (an outer vertical
  `[label, controlsStack]` plus an inner `controlsStack`) rather than using
  `ComposableSettings.makeRow`'s single horizontal `[label, spacer,
  control...]` layout that every other `ComposableSettings` row view uses.
  **Rationale**: a multi-choice radio group needs to grow along its own axis
  independent of the heading, unlike a single trailing control (a switch,
  slider, or popup) that fits beside the label in one row's height; source
  never calls `makeRow` anywhere in this file.
  **Approved**: pending
- **Decision**: Switch `controlsStack.alignment` between `.leading` (vertical
  axis) and `.firstBaseline` (horizontal axis) via the source's own
  ternary, rather than using one alignment for both orientations.
  **Rationale**: stacked buttons of possibly different widths want a common
  left edge when arranged vertically, while buttons placed side by side want
  their title text sitting on one shared line, which `.firstBaseline`
  provides and `.leading` does not.
  **Approved**: pending
- **Decision**: Build each choice's control from AppKit's stock
  `NSButton(radioButtonWithTitle:)` factory rather than pairing a bare radio
  `NSButton` with a separate `ThemedLabel` per choice, the way the heading
  label is built.
  **Rationale**: `radioButtonWithTitle:` is the standard AppKit factory that
  bundles a radio control and its title into one control; source builds no
  second `ThemedLabel` per row, at the traceable cost that per-choice titles
  do not follow the app's theme `sizeScale` or repaint-on-theme-change path
  the way the heading label does (see Appearance).
  **Approved**: pending
- **Decision**: Leave every radio button `.off` when `viewModel.value` matches
  no choice's `value`, rather than falling back to a default selection.
  **Rationale**: `syncSelection()`'s `(value == current) ? .on : .off`
  comparison is evaluated independently per button with no fallback branch in
  source; the component makes no attempt to guarantee "exactly one selected"
  when the view model's value is not representable by any choice.
  **Approved**: pending
- **Decision**: Both `init(coder:)` and the frame-only `init(frame:)` trigger
  a fatal error, leaving `init(viewModel:axis:)` as the only usable
  initializer.
  **Rationale**: The view has no meaningful default state — it cannot render
  a title, choice set, or value without a `viewModel` — so both inherited
  `NSView` initializers that could construct it without one are
  intentionally disabled.
  **Approved**: pending
  Known defect: the frame-only override's fatal-error message is the
  truncated string `"init(frame frameRect: NSRect"` (missing its closing
  parenthesis); it is reproduced here exactly as written in source, not
  corrected.
- **Decision**: The initializer unconditionally assigns `viewModel.onChange`,
  replacing whatever handler (if any) was previously registered on that
  `ChoiceViewModel` instance, rather than composing with an existing handler.
  **Rationale**: `viewModel.onChange` is a single closure property; a plain
  assignment is the simplest way to route external changes into
  `syncSelection()`, at the traceable cost that another party's previously
  registered `onChange` observer on the same view-model instance is silently
  discarded (see Edge Cases).
  **Approved**: pending
- **Decision**: Leave the heading `label` with no accessibility group or
  title-UI-element linkage to the radio buttons beneath it (no
  `NSAccessibilityGroupRole`, no `setAccessibilityTitleUIElement`), unlike
  sibling `CheckboxView`, which does link its single control to its label.
  **Rationale**: Not yet decided; see Accessibility (Label requirements) for
  what the source does and does not implement. WinUI's
  `RadioButtons.Header`, Compose's `selectableGroup()`, and the Web
  `<fieldset>`/`<legend>` notes already assume a named accessibility group as
  the eventual target for this component.
  **Approved**: pending
