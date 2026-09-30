<!-- leaf: implement-extension/input-box-view-controller--part-2 · source: extension-input-box-view-controller.md -->

# ExtensionInputBoxViewController — continued (part 2)

## Privacy

- **Data collected**: The field's typed value — potentially a secret
  (e.g. a token or password) when `model.request.isPassword` is `true`,
  in which case `NSSecureTextField` masks it on screen. The component
  does not otherwise classify or redact this value; it holds it in
  `model.value` and returns it verbatim via `onAccept`.
- **Storage**: Not applicable — `ExtensionInputBoxViewController` and
  `ExtensionInputBoxModel` hold the value only in memory (a `String`
  property) for the panel's lifetime; no write to disk, `UserDefaults`,
  or any other persistent store appears in source.
- **Transmission**: Not applicable within this file — the accepted value
  is handed to the caller-supplied `onAccept` closure; this file performs
  no networking itself. Where that value goes afterward (back across the
  extension-host bridge to the requesting extension) is owned by
  `ExtensionPickerPresenter`/the VS Code API bridge, not by
  `ExtensionInputBoxViewController.swift`.
- **Retention**: The value lives only in `model.value` and the field's own
  `stringValue` for as long as the panel is on screen. No explicit
  zeroing or secure-erasure call is made on the string anywhere in this
  file; the value is simply released along with the controller and its
  model when the panel closes.

## Platform Notes

- **SwiftUI**: Compose a `Form`/`VStack` with an optional
  `Text(title).font(.headline)`, an optional
  `Text(prompt).font(.caption).foregroundStyle(.secondary)`, a
  `SecureField`/`TextField` bound to `@State` and driving validation from
  `.onChange(of:)`, and an optional `Text(validationMessage)` styled per
  severity (`.foregroundStyle(.red)`/`.orange`/`.secondary`), shown only
  when a message is present — mirroring `validation-message-shown`/
  `validation-message-hidden`. `.onSubmit` alone only gates a Return
  against the current `canAccept` value; it cannot replay one pressed
  while validation is in flight. Mirror `model-gated-acceptance`/
  `acceptance-deferral` with a `@State pendingSubmit` flag: `.onSubmit`
  accepts immediately when the SwiftUI-side `canAccept` is already true,
  otherwise (while validating) sets `pendingSubmit = true` and does not
  accept; an `.onChange(of: canAccept)` (or the validation-result
  callback) checks `pendingSubmit` when `canAccept` turns true, accepts,
  and clears the flag — the same held-then-replayed Return the AppKit
  source implements, not a drop. Cancel via a
  `.keyboardShortcut(.cancelAction)` button, mirroring
  `escape-cancellation`.
- **Compose**: Use a `Column` with an optional title `Text` (`titleMedium`),
  an optional prompt `Text` (`bodySmall`, `onSurfaceVariant`), an
  `OutlinedTextField` (with `visualTransformation = PasswordVisualTransformation()`
  when secure) driving validation from `onValueChange`, and a `Text`
  colored by `MaterialTheme.colorScheme.error`/tertiary/`onSurfaceVariant`
  for the validation message, shown only when non-null. Gate the IME
  "Done" action and a confirm button the same way `model.canAccept` gates
  Return here, and map system back-press to cancellation, mirroring
  `escape-cancellation`.
- **React/Web**: A `<form>` with an optional `<h2>`/`<p>` for title/prompt,
  an `<input type={isPassword ? "password" : "text"}>` wired to `onChange`
  for per-keystroke validation, and a `role="alert"` `<span>` for the
  validation message (colored by severity), rendered only when a message
  exists — mirroring the show/hide and severity-color requirements. Gate
  the form's `onSubmit` on the same "not currently validating and no
  active error" condition `model.canAccept` expresses, and bind an Escape
  `keydown` handler (or a Cancel button) to cancellation, mirroring
  `escape-cancellation`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionInputBoxViewController.swift`
  — macOS-only (`import AppKit`), `@MainActor` `NSViewController`, laid
  out entirely with programmatic Auto Layout (no XIB/Storyboard), sharing
  `PickerKeyboardController` with `ExtensionQuickPickViewController`.
  The pending-Return and once-per-instance-prefill guards described by
  `acceptance-deferral`/`pending-acceptance-reset` and
  `prefill-validation-once` are backed by two private properties,
  `acceptWhenValidationLands` and `hasValidatedPrefill`.
  There is no UIKit code path in source; a UIKit port would replace
  `NSSecureTextField`/`NSTextField` with `UITextField`
  (`isSecureTextEntry`), `NSTextFieldDelegate` with
  `UITextFieldDelegate`'s `textField(_:shouldChangeCharactersIn:
  replacementString:)`/`textFieldDidEndEditing`, and the window-level
  Escape `NSEvent` monitor with a Cancel bar item or interactive dismissal
  (iOS has no Escape-key equivalent).
- **WinUI 3** (the reason this recipe exists): Build the panel as a
  `StackPanel` inside the picker's shared content host: an optional
  `TextBlock` (`Style="{StaticResource BodyStrongTextBlockStyle}"`) for
  the title, an optional `TextBlock`
  (`Style="{StaticResource CaptionTextBlockStyle}"`, `Opacity="0.7"`) for
  the prompt, a `PasswordBox` when the request is a password field or a
  `TextBox` otherwise (`Text="{x:Bind Value, Mode=TwoWay}"`), and a
  `TextBlock` for the validation message whose `Visibility` is bound to
  "message present" and whose `Foreground` switches between the theme's
  error/caution/tertiary brushes for `.error`/`.warning`/`.information` —
  mirroring `validation-message-shown`/`validation-message-hidden`.
  Wire the `TextBox`/`PasswordBox`'s `TextChanged`/`PasswordChanged` event
  to the same commit-and-revalidate round trip
  `value-commit-and-revalidation` describes; gate the panel's default
  action — a `ContentDialog.DefaultButton` set to `Primary` when the panel
  is hosted as a `ContentDialog`, or a `KeyboardAccelerator` for
  `VirtualKey.Enter` on the root otherwise — on the WinUI equivalent of
  `model.canAccept`, mirroring `model-gated-acceptance` and
  `acceptance-deferral`; and drive Cancel from
  `ContentDialog.CloseButton` (or a `KeyboardAccelerator` for
  `VirtualKey.Escape`) so it fires unconditional cancellation, mirroring
  `escape-cancellation` — WinUI 3 has no `IsDefault`/`IsCancel` button
  properties (those are WPF's). Map focus to
  `TextBox`/`PasswordBox.Focus(FocusState.Programmatic)`; initial
  selection via `Select(start, length)` applies only to `TextBox` —
  `PasswordBox` exposes no selection API, so a secure field can only be
  focused, not pre-selected, which is as far as
  `focus-then-initial-selection`'s focus-then-select order can carry over
  for a password field.

## Design Decisions

- **Decision**: Choose the field's concrete class (`NSSecureTextField` vs.
  `NSTextField`) once, in `init(model:)`, from
  `model.request.isPassword`, rather than allowing it to change later.
  **Rationale**: Source's own comment: a field that changes class after
  gaining focus loses its caret and typed text, and `isPassword` cannot
  change during one `showInputBox` request, so there is exactly one
  moment this decision needs to be made.
  **Approved**: pending
- **Decision**: Hold a Return pressed while `model.isValidating` is `true`
  and replay it once validation lands, rather than accepting it
  immediately or dropping the keystroke.
  **Rationale**: Source's own comment on `choose()`: a Return pressed
  mid-validation is "not yet," not "no" — replaying it once the answer
  arrives lets a slow validator delay acceptance instead of silently
  swallowing the user's keystroke.
  **Approved**: pending
- **Decision**: Validate the pre-filled `model.value` once, on the first
  `viewDidAppear` after the controller instance is created, via the guard
  described in `prefill-validation-once`, rather than in `viewDidLoad`.
  **Rationale**: Source's own comment: `viewDidAppear` can run more than
  once for one panel, so the guard keeps a re-appearance from
  re-triggering a validation round trip for a value that never changed;
  `viewDidLoad` was rejected because the presenter assigns
  `onValueChanged` only after `viewDidLoad` can already have run, leaving
  nothing to call yet.
  **Approved**: pending
- **Decision**: Route the field's `doCommandBy:` selectors through the
  shared `PickerKeyboardController`, which also recognizes
  `moveUp`/`moveDown` (arrow keys), even though this controller never
  sets `onMoveSelection`.
  **Rationale**: `PickerKeyboardController` is shared byte-for-byte with
  the picker views that do use `onMoveSelection` to move a row selection;
  reusing it here consumes the up/down arrow key events (marked handled,
  so they do not propagate further) but produces no visible effect in
  this single-field panel, since `onMoveSelection` is left at its default
  no-op closure.
  **Approved**: pending
