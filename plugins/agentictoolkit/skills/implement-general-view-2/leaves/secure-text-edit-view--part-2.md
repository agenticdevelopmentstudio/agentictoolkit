<!-- leaf: implement-general-view-2/secure-text-edit-view--part-2 · source: secure-text-edit-view.md -->

# SecureTextEditView — continued (part 2)

## Platform Notes

- **SwiftUI**: Replace with an `HStack` pairing `Text(viewModel.title)`
  leading and a trailing `SecureField("", text: $value)`, writing the
  binding's setter back into the underlying setting with an equality guard
  before assigning, mirroring **skips-redundant-commits**. Give the field an
  explicit `.accessibilityLabel(viewModel.title)` — the fix this recipe's
  Accessibility section flags as missing from the AppKit source — and drive
  its font/color from the same semantic theme tokens (`.body`, `primaryText`,
  `placeholderText`) rather than fixed literals, mirroring the theme styling
  documented for `TextEditView`.
- **Compose**: Use a `Row` with `Text(title)` leading and a trailing
  `OutlinedTextField(value = value, onValueChange = { ... },
  visualTransformation = PasswordVisualTransformation(), singleLine = true)`
  — `PasswordVisualTransformation` is Compose's dot-masking analog of
  `NSSecureTextField`. Commit to the backing state/view model on focus loss
  or `ImeAction.Done` (`KeyboardOptions(imeAction = ImeAction.Done)` with a
  `KeyboardActions.onDone`, or a `Modifier.onFocusChanged` check), not on
  every `onValueChange` call — `onValueChange` fires per keystroke, which
  would otherwise write partial secrets to storage — comparing against the
  previous value before writing, mirroring **skips-redundant-commits**. Give
  it `Modifier.semantics { contentDescription = title }` (the missing
  accessibility link's Compose analog).
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title and
  an `<input type="password">` whose `aria-labelledby` points at the title
  `<label>`'s `id` — the web analog of the accessibility link this recipe
  flags as missing from the source. Commit the new value on the input's
  `blur` handler (or Enter via `onKeyDown`), not on every `onChange` call —
  an `<input>` fires `onChange` per keystroke, which would otherwise write
  partial secrets to storage — comparing against the previous value before
  calling the parent's setter, mirroring **skips-redundant-commits**; style
  the input's font/color and any placeholder from theme tokens equivalent to
  `.body`/`primaryText`/`placeholderText`, mirroring the theme styling
  documented for `TextEditView`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SecureTextEditView.swift`
  — a macOS-only, `@MainActor`, `final` subclass of `TextEditView` inside the
  `ComposableSettings` namespace, overriding only
  `makeTextField(initialValue:)` to return `NSSecureTextField(string:
  initialValue)`. `final` is what makes **forecloses-subclassing** true; the
  override requires `class func` (not `static`) because it overrides
  `TextEditView`'s `open class func makeTextField`, which trips SwiftLint's
  `static_over_final_class` rule (see Design Decisions). `TextEditView.swift`
  (`agentictoolkit://recipes/text-edit-view`) supplies everything else — row
  layout, content-hugging, the `textFieldChanged(_:)` target/action commit
  path, `observeTheme` styling, and `viewModel.onChange` sync — and is out of
  this recipe's scope. There is no UIKit code path in source; a UIKit port
  would replace `NSSecureTextField` with a `UITextField` configured
  `isSecureTextEntry = true`.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*`: a `TextBlock` for the title in column 0
  and a `PasswordBox` — WinUI's own dot-masking control and the direct
  analog of `NSSecureTextField` — in column 1, `HorizontalAlignment="Stretch"`
  so the `*` column's leftover width goes to the field rather than the
  title, the WinUI analog of `expands-text-field-to-fill-row`. Set
  `AutomationProperties.LabeledBy` on the `PasswordBox` to the `TextBlock` —
  the WinUI analog of the `setAccessibilityTitleUIElement` link this recipe
  flags as missing from the AppKit source; add it in the port even though
  the source itself omits it. Commit on the `PasswordBox`'s `LostFocus`
  event (or Enter), not on every `PasswordChanged` event — `PasswordChanged`
  fires per keystroke, which would otherwise write partial secrets to
  storage (the keychain, in the typical setup) — writing through a property
  setter that skips the assignment (and so skips raising
  `INotifyPropertyChanged`) when the incoming value already equals the
  current one, mirroring **skips-redundant-commits**. Bind
  `PasswordBox.Foreground`/`PlaceholderForeground` to theme resource
  brushes equivalent to `primaryText`/`placeholderText`, mirroring the
  theme styling documented for `TextEditView`. Note `PasswordBox` ships its
  own built-in reveal-password toggle button, an affordance neither
  `NSSecureTextField` nor this source provides; carrying it over in the port
  is a platform enhancement, not something to gate on parity with the
  AppKit source.

## Design Decisions

Decisions governing `TextEditView`'s inherited behavior — the content-hugging
priority, the `open class func` factory pattern, `observeTheme` placement,
placeholder-restyle timing, and the placeholder contrast floor — are recorded
at `agentictoolkit://recipes/text-edit-view#design-decisions` and are not
repeated here.

- **Decision**: Implement `SecureTextEditView` as a `TextEditView` subclass
  overriding only `makeTextField(initialValue:)`, rather than composing a
  new view from scratch.
  **Rationale**: Per the source's own doc comment, this reuses all of
  `TextEditView`'s row layout, theme styling, and commit wiring; the only
  difference between a plain and a secure text row is the underlying
  `NSTextField` subclass.
  **Approved**: pending
- **Decision**: Mark `SecureTextEditView` `final`.
  **Rationale**: Traceable to `public final class SecureTextEditView:
  TextEditView` in source — forecloses further subclassing since it is the
  one masking variant `TextEditView` needs (see **forecloses-subclassing**).
  **Approved**: pending
- **Decision**: Suppress SwiftLint's `static_over_final_class` rule
  (`// swiftlint:disable:next static_over_final_class`) on the
  `makeTextField` override.
  **Rationale**: Overriding `TextEditView`'s `open class func makeTextField`
  requires `class func` even though `SecureTextEditView` itself is `final`,
  which trips a lint rule that otherwise prefers `static` — this is an
  intentional, documented suppression traceable to the source comment, not
  an accidental disable, and is recorded here per the source-fidelity
  requirement to document known workarounds.
  **Approved**: pending
- **Decision**: Treat storage and persistence of the masked value as
  entirely out of scope of `SecureTextEditView.swift`.
  **Rationale**: Per the source's own doc comment, the value is "typically"
  routed to a `UserSetting<String>` with `isSecure: true`, which
  `SettingsStore` then routes to `KeychainSecureSettingsStorageProvider`;
  `SecureTextEditView.swift` only masks the on-screen glyphs and never
  itself reads or writes the keychain.
  **Approved**: pending
