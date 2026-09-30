<!-- leaf: implement-general-view-1/checkbox-view--part-2 · source: checkbox-view.md -->

# CheckboxView — continued (part 2)

## Platform Notes

- **SwiftUI**: Replace with an `HStack` containing `Text(viewModel.title)`
  and a trailing `Toggle("", isOn: $isOn).labelsHidden()`, giving the
  `Toggle` an `.accessibilityLabel(viewModel.title)` (SwiftUI's analog of
  `setAccessibilityTitleUIElement`) so the switch announces the row's title
  rather than being unlabelled. Write the user's flips back into the
  underlying setting from the `Binding`'s setter with an equality guard,
  mirroring skips-redundant-commits.
- **Compose**: Use a `Row` with `Text(title)` leading and a trailing
  `Switch(checked = value, onCheckedChange = { ... })`. Give the `Switch` a
  `Modifier.semantics { contentDescription = title }` (the Compose analog
  of the title-element link), and commit to the backing state/view-model
  from `onCheckedChange` with an equality check before writing, mirroring
  skips-redundant-commits.
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title and
  an `<input type="checkbox" role="switch">` (or a styled switch component)
  whose `aria-labelledby` points at the title `<label>`'s `id` — the web
  analog of `setAccessibilityTitleUIElement`. Commit the new value on the
  input's `onChange` handler, comparing against the previous value before
  calling the parent's setter to mirror skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CheckboxView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and an `NSSwitch` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`, links the switch's
  accessibility title to the label, and wires the switch's target/action
  (`toggle.target = self`, `toggle.action = #selector(toggleChanged(_:))`) —
  the AppKit plumbing behind **commits-toggle-value** — to
  `toggleChanged(_:)`. There is no UIKit code path in source; a UIKit port
  would replace `NSSwitch` with `UISwitch` and the `target`/`action`
  pattern with `.addTarget(_:action:for: .valueChanged)` — UIKit has no
  `NSCoder`-vs-frame initializer split to fatal-error on both the way
  requires-designated-initializer and rejects-frame-only-initialization do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column 0
  (the `*` column lets the title claim the row's leading space, the WinUI
  analog of `makeRow`'s flexible spacer sitting between the label and the
  control); a `ToggleSwitch` (or `ToggleSwitch` restyled with
  `OnContent=""`/`OffContent=""` to read as a plain switch, matching
  `NSSwitch`'s minimal chrome) bound `IsOn="{x:Bind IsOn, Mode=TwoWay}"` in
  column 1, `HorizontalAlignment="Right"`. Set
  `AutomationProperties.LabeledBy` on the `ToggleSwitch` to the `TextBlock`
  — the WinUI analog of `setAccessibilityTitleUIElement` linking a bare
  control's name to its visible label. Write the committed value through a
  property setter that skips the assignment (and so skips raising
  `INotifyPropertyChanged`) when the incoming value already equals the
  current value, mirroring skips-redundant-commits. `ToggleSwitch`'s
  built-in `Toggled` event is the WinUI analog of `toggleChanged(_:)`.

## Design Decisions

- Decision: Draw the row's control as an `NSSwitch`, not a checkbox button,
  despite the type being named `CheckboxView`.
  Rationale: Per the source's own doc comment, the switch replaced a
  checkbox-with-title button because a checkbox puts its control on the
  left, "the one row shape that cannot line up with the popups, steppers
  and sliders beside it in the same card — and left every group looking
  like two different lists interleaved."
  Approved: pending
- Decision: Name the public property `toggle`, not `checkbox`.
  Rationale: Per the source's own doc comment, the control "has not been a
  checkbox since the row was restyled, and a name that lies about a
  control's class is the kind that gets `state = .on` written against the
  wrong API."
  Approved: pending
- Decision: Link the switch's accessibility title to the label via
  `setAccessibilityTitleUIElement` rather than setting a separate
  accessibility label string.
  Rationale: Per the source's own comment, "AppKit gives a bare switch no
  name, so VoiceOver would announce it as an unlabelled control; the
  visible label is its title element."
  Approved: pending
- Decision: Force a fatal error from both `init(coder:)` and the
  frame-only `init(frame:)`, leaving `init(with:)` as the only usable
  initializer.
  Rationale: The view has no meaningful default state — it cannot render a
  title or value without a `viewModel` — so both inherited `NSView`
  initializers that could construct it without one are intentionally
  disabled rather than left to produce a half-configured row.
  Approved: pending
- **Decision**: Keep the public type name `CheckboxView` even though it
  draws an `NSSwitch`, not a checkbox.
  **Rationale**: The type is `SettingsViewProtocol`-conforming API surface
  read by callers across `ComposableSettingsWindow`; renaming it (e.g. to
  `SwitchRowView`) is a breaking rename with no behavioral upside, while the
  file's own doc comments already correct the mismatch at the
  `toggle`-vs-`checkbox` property level (see the `toggle` naming decision
  above) — VoiceOver, callers, and tests all read `toggle`, not the type
  name, so the outer name causes no runtime confusion today.
  **Approved**: pending
- **Decision**: Unconditionally overwrite `viewModel.onChange` with the
  component's own handler during initialization, rather than chaining it
  after any previously registered handler.
  **Rationale**: `ComposableSettings.ViewModel<Bool>`'s `onChange` is a
  single closure property with no built-in multicast support; chaining
  would require a broader change to the shared view-model type, which is
  out of scope for this row view. The source accepts the tradeoff that one
  `CheckboxView` (or other observer) per view model instance is the
  supported usage (see **claims-sole-onchange-observer**).
  **Approved**: pending
