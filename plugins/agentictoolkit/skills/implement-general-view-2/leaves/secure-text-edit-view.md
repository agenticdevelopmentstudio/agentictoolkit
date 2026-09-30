<!-- leaf: implement-general-view-2/secure-text-edit-view · source: secure-text-edit-view.md -->

**Rules** (cite as `implement-general-view-2/secure-text-edit-view#<slug>`):

- `masks-entry-with-secure-field` MUST
- `forecloses-subclassing` MUST

# SecureTextEditView

## Overview

`SecureTextEditView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SecureTextEditView.swift`).
Per the source's own doc comment, it is meant for API keys, passwords, and
other secrets that are still routed through a
`ComposableSettings.ViewModel<String>` — typically one whose backing
`UserSetting<String>` has `isSecure: true` and is therefore stored through the
keychain-backed `SecureStoredSettingsStorageProvider`.

It is a `final` subclass of `TextEditView`
(`agentictoolkit://recipes/text-edit-view`,
`.../Views/TextEditView.swift`), overriding exactly one member —
`makeTextField(initialValue:)` returns `NSSecureTextField(string:
initialValue)` in place of the plain `NSTextField` its superclass would
return — so the entry is dot-masked. `TextEditView`'s row layout,
theme-driven font/color styling, target/action commit path, and view-model
sync are out of this recipe's scope; only the delta this subclass adds — the
masked field type and the ban on further subclassing — is documented here.
See `agentictoolkit://recipes/text-edit-view` for everything a caller
instantiating `SecureTextEditView` also gets.

## Behavioral Requirements

- **masks-entry-with-secure-field**: Component MUST override
  `makeTextField(initialValue:)` to return an `NSSecureTextField(string:
  initialValue)`, so `textField` is a dot-masking secure field rather than
  the plain `NSTextField` `TextEditView` would otherwise construct.
- **forecloses-subclassing**: Component MUST NOT be subclassable further —
  it is the terminal specialization of `TextEditView` for masked entry (the
  class is declared `final`; see the AppKit bullet under Platform Notes).

All other behavior — row layout, expanding the field to fill the row, wiring
the field's target/action, initializing from and syncing with the view
model, theme styling, restyling an existing placeholder, exposing `label`
and `textField`, the `init(coder:)`/`init(frame:)` traps, and main-actor
confinement — is inherited unmodified from `TextEditView`; see
`agentictoolkit://recipes/text-edit-view#requirements` (arranges-row-layout,
expands-text-field-to-fill-row, wires-text-field-action,
initializes-from-view-model, commits-value-on-change,
skips-redundant-commits, syncs-on-external-change, applies-theme-styling,
restyles-existing-placeholder, exposes-constituent-views,
requires-designated-initializer, rejects-frame-only-initialization,
confines-to-main-actor).

## Appearance

Inherited unmodified from `TextEditView` — corner radius, padding, font,
background, foreground/text, border, shadow, and min/max size are all as
documented at `agentictoolkit://recipes/text-edit-view#appearance`;
`SecureTextEditView.swift` sets no font, color, or layout property of its
own. The one appearance difference this subclass introduces is that
`textField`'s typed characters render as `NSSecureTextField`'s built-in
dot-mask glyphs rather than plain text — see **masks-entry-with-secure-field**
and the Default row under States below.

## Accessibility

- **Role/trait**: Inherited unmodified from `TextEditView` — no
  `setAccessibilityRole` call appears in either file; `NSSecureTextField`
  carries AppKit's own built-in secure-text-field accessibility role.
- **Label requirements**: Neither `TextEditView.swift` (whose `init`
  `SecureTextEditView` inherits unmodified) nor `SecureTextEditView.swift`
  calls `setAccessibilityTitleUIElement` or sets an `accessibilityLabel`
  linking `textField` to `label` — unlike the sibling `CheckboxView`
  (`agentictoolkit://recipes/checkbox-view`), which links its switch to its
  label for exactly this reason ("AppKit gives a bare switch no name").
  Without that link, VoiceOver announces `textField` as an unnamed secure
  text field rather than by the row's title.
- **Announce state changes**: Inherited unmodified from `TextEditView` — the
  component has no loading state and never disables itself in source; masked
  characters being typed or deleted are announced through
  `NSSecureTextField`'s own native accessibility value reporting.
- **Minimum tap target**: Inherited unmodified from `TextEditView` — this is
  a macOS, pointer/trackpad-driven `NSView`/`NSControl` composition (no touch
  input path in source); the 44×44pt minimum is iOS/touch guidance, not a
  macOS pointer-interface requirement.
- **Contrast**: Inherited unmodified from `TextEditView` — `label` and
  `textField`'s typed-text color both resolve to the theme's `primaryText`
  role, and placeholder text resolves to `placeholderText`, which is
  guaranteed only a 1.6:1 contrast floor against the background (see
  `agentictoolkit://recipes/text-edit-view#design-decisions` and
  **contrast-ratio** in Compliance below). Whether an active theme's actual
  resolved colors clear WCAG 2.1 SC 1.4.3's 4.5:1 threshold for body text is
  a property of the chosen `ColorTheme`, not of `SecureTextEditView.swift`.

## Configuration

Inherited unmodified from `TextEditView` — `SecureTextEditView` accepts no
configuration option of its own beyond the `viewModel:
ComposableSettings.ViewModel<String>` parameter documented at
`agentictoolkit://recipes/text-edit-view#configuration`. The only thing this
subclass changes about that shared configuration is what the value is
typically used for: per the source's own doc comment, a secret such as an
API key or password.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Inherited unmodified from `TextEditView` — source contains no animation, transition, or `NSAnimationContext` call in either file; every state change is an instantaneous property assignment. |
| Increase Contrast | Inherited unmodified from `TextEditView` — text/label color comes from the theme's `primaryText`/`placeholderText` roles, whose actual resolved contrast (including the placeholder role's 1.6:1 floor — see **contrast-ratio** in Compliance below) is the theme layer's responsibility, not this component's. |
| Differentiate Without Color | Inherited unmodified from `TextEditView`; also not applicable on its own terms here — masking is communicated by replacing characters with the system's dot glyphs, not by color, so there is no color-only signal for this component to provide an alternative to. |

## Privacy

- **Data collected**: The field's typed value — per the source's own doc
  comment, typically a secret such as an API key or password — which
  `NSSecureTextField` masks on screen as it is typed. The component does not
  otherwise classify or redact this value; it holds it in
  `viewModel.settingObserver.value` and passes it through unchanged (see
  `agentictoolkit://recipes/text-edit-view#privacy` for the storage,
  transmission, and retention behavior this shares with `TextEditView`,
  which applies to whatever string value either component holds).
- **Storage**: Not applicable within `SecureTextEditView.swift` itself —
  persistence, when it happens, is owned by the caller-supplied
  `ComposableSettings.ViewModel<String>`'s backing `UserSetting<String>`:
  `SettingsStore` routes a setting with `isSecure: true` to
  `SecureSettingsStorageProvider` (`KeychainSecureSettingsStorageProvider`
  by default), i.e. the keychain — this is the reason the source recommends
  this view for secrets, but none of it is code in `SecureTextEditView.swift`
  itself.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `SecureTextEditView.swift` or the `TextEditView.swift` behavior it
  inherits.
- **Retention**: Inherited unmodified from `TextEditView` — the value lives
  only in `textField.stringValue` and `viewModel.settingObserver.value` for
  as long as the row is on screen and its view model is retained; see
  `agentictoolkit://recipes/text-edit-view#privacy`.
- **Security-violation handling**: Not applicable — this component has no
  detection surface of its own (no validation, rate-limiting, or
  authentication logic); it only masks on-screen glyphs. Any
  violation-handling behavior belongs to whatever storage/auth layer the
  caller's `UserSetting<String>` is wired to, outside these two files.

