---
id: 2e0bf51e-905d-476d-9c0c-48465174ba59
title: SecureTextEditView
domain: agentictoolkit://recipes/secure-text-edit-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings text row backed by NSSecureTextField instead of
  NSTextField, dot-masking entry for secrets such as API keys and passwords.
platforms:
- swift
- macos
tags:
- settings
- form-control
- text-input
- secure-input
- appkit
depends-on:
- agentictoolkit://recipes/text-edit-view
related:
- agentictoolkit://recipes/checkbox-view
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `textField`'s underlying value equals `viewModel.value`, rendered as one dot-mask glyph per character — `NSSecureTextField`'s own built-in masked rendering, per the source's doc comment ("so the entry is dot-masked") — see **masks-entry-with-secure-field**. |
| All other states | Editing, Committed, Placeholder shown, Disabled, Pressed, and Loading are inherited unmodified from `TextEditView`; see `agentictoolkit://recipes/text-edit-view#states`. |

## Accessibility

- **Role/trait**: Inherited unmodified from `TextEditView` — no
  `setAccessibilityRole` call appears in either file; `NSSecureTextField`
  carries AppKit's own built-in secure-text-field accessibility role.
- **Label requirements**: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. Neither `TextEditView.swift` (whose `init` `SecureTextEditView`
  inherits unmodified) nor `SecureTextEditView.swift` calls
  `setAccessibilityTitleUIElement` or sets an `accessibilityLabel` linking
  `textField` to `label` — unlike the sibling `CheckboxView`
  (`agentictoolkit://recipes/checkbox-view`), which links its switch to its
  label for exactly this reason ("AppKit gives a bare switch no name").
  Without that link, VoiceOver announces `textField` as an unnamed secure
  text field rather than by the row's title. What would settle it: a
  decision on whether `TextEditView`/`SecureTextEditView` should adopt the
  same `setAccessibilityTitleUIElement(label)` call `CheckboxView` uses, or
  accessibility-audit evidence that this omission is acceptable as-is.
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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| secure-text-edit-view-001 | masks-entry-with-secure-field | Construct `SecureTextEditView` with any `viewModel` | `textField` is an instance of `NSSecureTextField`, not a plain `NSTextField` |
| secure-text-edit-view-002 | forecloses-subclassing | Attempt to declare a subclass of `ComposableSettings.SecureTextEditView` | Compiler rejects the declaration (`final`) |

All other conformance test vectors — row layout, content-hugging, target/
action wiring, view-model sync, theme styling, placeholder restyling,
constituent-view exposure, the initializer traps, and main-actor confinement
— are inherited unmodified from `TextEditView`; see
`agentictoolkit://recipes/text-edit-view#test-vectors`.

## Edge Cases

All edge-case behavior — the non-optional `viewModel` parameter ruling out
`nil`, unbounded `String` length, main-actor-serialized concurrent access,
the absence of any throwing or error-producing API, no networking, and the
`viewModel.onChange` overwrite when a second observer is constructed against
the same view model — is inherited unmodified from `TextEditView`, whose
initializer `SecureTextEditView` reuses without change; see
`agentictoolkit://recipes/text-edit-view#edge-cases`.
`SecureTextEditView.swift` contributes no code beyond the
`makeTextField(initialValue:)` override, so it introduces no edge case of
its own.

## Configuration

Inherited unmodified from `TextEditView` — `SecureTextEditView` accepts no
configuration option of its own beyond the `viewModel:
ComposableSettings.ViewModel<String>` parameter documented at
`agentictoolkit://recipes/text-edit-view#configuration`. The only thing this
subclass changes about that shared configuration is what the value is
typically used for: per the source's own doc comment, a secret such as an
API key or password.

## Deep Linking

Not applicable: `SecureTextEditView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `SecureTextEditView.swift` or the `TextEditView.swift`
behavior it inherits.

## Localization

Not applicable: `SecureTextEditView.swift` contains no user-facing string
literal of its own. The row's title comes entirely from `viewModel.title`, a
value the caller provides, so there is nothing for this component to
localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Inherited unmodified from `TextEditView` — source contains no animation, transition, or `NSAnimationContext` call in either file; every state change is an instantaneous property assignment. |
| Increase Contrast | Inherited unmodified from `TextEditView` — text/label color comes from the theme's `primaryText`/`placeholderText` roles, whose actual resolved contrast (including the placeholder role's 1.6:1 floor — see **contrast-ratio** in Compliance below) is the theme layer's responsibility, not this component's. |
| Differentiate Without Color | Inherited unmodified from `TextEditView`; also not applicable on its own terms here — masking is communicated by replacing characters with the system's dot glyphs, not by color, so there is no color-only signal for this component to provide an alternative to. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `SecureTextEditView.swift` or the `TextEditView.swift` behavior it
inherits; the row always renders once constructed.

## Analytics

Not applicable: neither `SecureTextEditView.swift` nor the
`TextEditView.swift` behavior it inherits contains an analytics or
telemetry call.

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

## Logging

Not applicable: neither `SecureTextEditView.swift` nor the
`TextEditView.swift` behavior it inherits contains a logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference` and `platform-design-language` rest on
`textField` being an unmodified `NSSecureTextField` with AppKit's default
bezel styling (**masks-entry-with-secure-field**); `keyboard-navigable`,
`idempotent-operations`, and `separation-of-concerns` rest on behavior that
is `TextEditView`'s concern and out of this recipe's scope (the field's
inherited, unmodified `NSControl` tab order, **skips-redundant-commits**,
and the view holding no persistence or business logic of its own); `screen-
reader-support` is `partial` because the accessibility title link is
missing — see the open question in Accessibility above; `contrast-ratio` is
`partial` because the inherited placeholder-text color clears only a 1.6:1
floor against WCAG's 4.5:1 threshold (see
`agentictoolkit://recipes/text-edit-view#design-decisions`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restructure to a delta-only recipe depending on text-edit-view, pruning duplicated requirements/appearance/states/test-vectors/edge-cases/configuration/privacy/logging content to the masking-specific delta (masks-entry-with-secure-field, forecloses-subclassing); reword forecloses-subclassing platform-neutrally and move the `final`/SwiftLint detail to Platform Notes; drop the macos tag; add text-edit-view to depends-on and checkbox-view to related; reformat Design Decisions to the bold convention and move the inherited placeholder-timing/contrast-floor decisions to text-edit-view; fix the WinUI Grid column order (Auto,\*) and correct WinUI/Compose/React commit timing to end-editing/submit instead of per-keystroke; add a partial contrast-ratio compliance row with a supporting sentence; remap compliance citations to the catalog |
