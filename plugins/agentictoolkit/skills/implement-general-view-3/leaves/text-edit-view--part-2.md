<!-- leaf: implement-general-view-3/text-edit-view--part-2 · source: text-edit-view.md -->

# TextEditView — continued (part 2)

## Privacy

- **Data collected**: Whatever the field's typed value is — an arbitrary
  string supplied and read by the caller through `viewModel`.
  `TextEditView.swift` does not classify, mask, or redact this value; it
  displays it in full as plain text (unlike its `SecureTextEditView`
  subclass) and holds it in `viewModel.settingObserver.value`, passing it
  through unchanged.
- **Storage**: Not applicable within this file — `TextEditView` holds the
  value only in `textField.stringValue` and
  `viewModel.settingObserver.value` for the view's lifetime. Persistence,
  when it happens, is owned entirely by the caller-supplied
  `ComposableSettings.ViewModel<String>`'s backing `UserSetting<String>`,
  outside code in `TextEditView.swift` itself.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this file. Where the committed value goes afterward is entirely
  owned by whatever consumes `viewModel.settingObserver.value`.
- **Retention**: The value lives only in `textField.stringValue` and
  `viewModel.settingObserver.value` for as long as the row is on screen
  and its view model is retained. No explicit zeroing or secure-erasure
  call is made on the string anywhere in `TextEditView.swift`; the value
  is released along with the view and its view model like any other
  property.

## Platform Notes

- **SwiftUI**: Replace with an `HStack` pairing `Text(viewModel.title)`
  leading and a trailing `TextField("", text: $value)`, tracked through a
  local editing state. Commit the value back into the underlying setting
  on `.onSubmit` (Return) or when a `@FocusState` boolean bound to the
  field transitions from `true` to `false` (focus loss) — not on every
  keystroke via the binding setter — with an equality guard before
  assigning, mirroring skips-redundant-commits and `NSTextField`'s
  target/action commit points. Give the field an explicit
  `.accessibilityLabel(viewModel.title)` — the fix this recipe's
  Accessibility section flags as missing from the AppKit source — and
  drive its font/color from the same semantic theme tokens (`.body`,
  `primaryText`, `placeholderText`) rather than fixed literals, mirroring
  applies-theme-styling/restyles-existing-placeholder.
- **Compose**: Use a `Row` with `Text(title)` leading and a trailing
  `OutlinedTextField(value = value, onValueChange = { value = it },
  singleLine = true)` backed by local text state. Commit to the backing
  state/view model only on focus loss (`Modifier.onFocusChanged`) or
  `ImeAction.Done`, not on every `onValueChange` call — `onValueChange`
  fires per keystroke — comparing against the previous value before
  writing, mirroring skips-redundant-commits and `NSTextField`'s
  target/action commit points. Give it `Modifier.semantics {
  contentDescription = title }` (the missing accessibility link's Compose
  analog).
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title
  and an `<input type="text">` whose `aria-labelledby` points at the
  title `<label>`'s `id` — the web analog of the accessibility link this
  recipe flags as missing from the source. Track the typed value locally
  and commit the new value to the parent's setter only on the input's
  `blur` handler or Enter via `onKeyDown`, not on every `onChange` call —
  an `<input>` fires `onChange` per keystroke — comparing against the
  previous value before calling the parent's setter, mirroring
  skips-redundant-commits and `NSTextField`'s target/action commit points;
  style the input's font/color and any placeholder from theme tokens
  equivalent to `.body`/`primaryText`/`placeholderText`, mirroring
  applies-theme-styling.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextEditView.swift`:
  a macOS-only, `@MainActor` `NSView` subclass inside the
  `ComposableSettings` namespace, `open` to subclassing through its
  `makeTextField(initialValue:)` factory — the mechanism
  `SecureTextEditView.swift` (in the same directory) uses to substitute
  `NSSecureTextField`. `textField.target` is set to the view itself and
  `textField.action` to `Selector("textFieldChanged:")`, its private
  `@objc` handler that performs the commit (see wires-text-field-action).
  The file is macOS-only (`import AppKit`); there is no UIKit code path in
  source. A UIKit port would replace `NSTextField` with a `UITextField`
  and the target/action pattern with
  `.addTarget(_:action:for: .editingDidEndOnExit)`. Known source bug: the
  frame-only initializer's fatal-error message string is malformed
  (`fatalError("init(frame frameRect: NSRect")`, missing its closing
  parenthesis) — the trap still fires correctly (see
  rejects-frame-only-initialization); only the printed message text is
  wrong.
- **WinUI 3**: Build the row as a `Grid` with column definitions `Auto,*`:
  a `TextBlock` for the title in column 0 (`Auto`, sized to its content,
  the WinUI analog of `makeRow`'s label), and a `TextBox` — the direct
  analog of the plain `NSTextField` this class constructs — in column 1
  (the `*` column, which claims the row's leftover space), with
  `HorizontalAlignment="Stretch"` so the field, not the title, takes the
  leftover width the way expands-text-field-to-fill-row does. Set
  `AutomationProperties.LabeledBy` on the `TextBox` to the `TextBlock` —
  the WinUI analog of the `setAccessibilityTitleUIElement` link this
  recipe flags as missing from the AppKit source; add it in the port even
  though the source itself omits it. Commit on the `TextBox.LostFocus`
  event (or `KeyDown` on Enter, mirroring `NSTextField`'s target/action
  firing points), writing through a property setter that skips the
  assignment (and so skips raising `INotifyPropertyChanged`) when the
  incoming value already equals the current one, mirroring
  skips-redundant-commits. Bind `TextBox.Foreground` and
  `PlaceholderForeground`/`PlaceholderText` to theme resource brushes
  equivalent to `primaryText`/`placeholderText` rather than hardcoded
  colors, mirroring
  applies-theme-styling/restyles-existing-placeholder. For a secure
  variant, a `PasswordBox` is the WinUI analog to build against instead,
  the way `SecureTextEditView` overrides this class's factory.

## Design Decisions

- **Decision**: Give `textField` a horizontal content-hugging priority
  (`NSLayoutConstraint.Priority(1)`) one step below the row spacer's,
  rather than leaving it at its default hugging.
  **Rationale**: per the source's own inline comment, this is "below the
  row spacer's hugging, so the field — not the gap — takes the width left
  over after the label. An empty field sized to its own content is a few
  points wide and unclickable." Without it, an empty `NSTextField` would
  shrink to its own tiny intrinsic width and the spacer would absorb the
  row's slack instead.
  **Approved**: pending
- **Decision**: Declare `makeTextField(initialValue:)` as an
  `open class func` factory instead of returning a fixed `NSTextField`
  inline in `init`.
  **Rationale**: this is the one seam `TextEditView` designs in for
  variation — `SecureTextEditView` overrides only this method to
  substitute `NSSecureTextField`, reusing every other line of `init` (row
  layout, content-hugging, theme observation, commit wiring) unmodified.
  **Approved**: pending
- **Decision**: Attach `observeTheme` styling inside `init` rather than by
  returning an already-themed field type from the factory.
  **Rationale**: per the source's own inline comment, "subclasses
  substitute their own field ... so the theme is attached here rather than
  by returning a `ThemedTextField` from the factory" — keeping theming in
  one place regardless of which `NSTextField` subclass `makeTextField`
  returns.
  **Approved**: pending
- **Decision**: Restyle an existing `textField.placeholderString` only on
  a theme change that occurs *after* construction, never on the initial
  apply.
  **Rationale**: `ThemePaletteObserver.init`
  (`external/agenticdevelopertoolkit/.../Theme/ThemeBinding.swift`)
  applies its closure immediately upon registration, which happens inside
  `TextEditView.init` before any caller can reach the newly-created
  `textField` to set a placeholder — so that first, construction-time
  apply always finds `field.placeholderString == nil` and the `if let`
  guard in `observeTheme`'s closure skips it. The placeholder is only
  ever styled by a later, caller-triggered theme change. This is a
  non-obvious consequence of the two files' evaluation order, not a bug
  being idealized away.
  **Approved**: pending
- **Decision**: Accept that placeholder text is guaranteed only a 1.6:1
  contrast floor against the background.
  **Rationale**: the theme layer's `SemanticPalette` derivation for
  `placeholderText` dims the theme's foreground toward its background
  with `minContrast: 1.6` — below WCAG 2.1 SC 1.4.3's 4.5:1 floor for
  normal text. This is a theme-layer choice inherited by every themed
  field, including this one; `TextEditView.swift` neither sets nor can
  override it. Recorded here as technical debt affecting accessibility
  correctness, per source-fidelity's requirement to document such debt
  rather than idealize it away.
  **Approved**: pending
- **Decision**: Whether `TextEditView` should call
  `setAccessibilityTitleUIElement(label)` to link `textField` to `label`
  for VoiceOver, the way sibling `CheckboxView` links its switch's
  accessibility title.
  **Rationale**: Not implemented in source (see Accessibility's Label
  requirements gap) — `TextEditView.swift` never calls
  `setAccessibilityTitleUIElement` or otherwise links `textField` to
  `label`, so VoiceOver announces `textField` as an unnamed text field
  rather than by the row's title. Recording the proposal here lets a port
  choose to copy the gap or fix it, since the Platform Notes already
  direct every port besides the AppKit source to add the link.
  **Approved**: pending
- **Decision**: Unconditionally overwrite `viewModel.onChange` with the
  component's own handler during initialization, rather than chaining it
  after any previously registered handler.
  **Rationale**: `ComposableSettings.ViewModel<String>`'s `onChange` is a
  single closure property with no built-in multicast support; chaining
  would require a broader change to the shared view-model type, which is
  out of scope for this row view. The source accepts the tradeoff that one
  `TextEditView` (or other observer, including `SecureTextEditView`) per
  view model instance is the supported usage (see
  **claims-sole-onchange-observer**).
  **Approved**: pending
