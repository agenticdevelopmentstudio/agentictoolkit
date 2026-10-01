---
id: 2e0bf51e-905d-476d-9c0c-48465174ba59
title: Secure Text Edit View
domain: agentictoolkit://cookbook/ui/settings/rows/secure-text-edit-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings text row that masks its entry, for secrets such as API
  keys and passwords.
platforms:
- swift
- macos
tags:
- settings
- form-control
- text-input
- secure-input
depends-on:
- agentictoolkit://cookbook/ui/settings/rows/text-edit-view
related:
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
references: []
approved-by: ''
approved-date: ''
---

# Secure Text Edit View

## Overview

The Secure Text Edit View is a settings text row. Per the source's own doc
comment, it is meant for API keys, passwords, and other secrets that are
still routed through a view model — typically one whose backing setting has
secure storage enabled and is therefore stored through a keychain-backed
storage provider.

It specializes the text edit row
(agentictoolkit://cookbook/ui/settings/rows/text-edit-view), overriding
exactly one thing — it constructs a masking (dot-obscured) secure field in
place of the plain field its base row would otherwise construct — so the
entry is dot-masked. The text edit row's own row layout, theme-driven
font/color styling, commit path, and view-model sync are out of this
recipe's scope; only the delta this specialization adds — the masked field
type and the ban on further specialization — is documented here. See
agentictoolkit://cookbook/ui/settings/rows/text-edit-view for everything a
caller instantiating this component also gets.

## Behavioral Requirements

- **masks-entry-with-secure-field**: Component MUST construct its field as
  a masking (dot-obscured) secure text field, so the field is a secure,
  masking field rather than the plain field its base row would otherwise
  construct.

All other behavior — row layout, expanding the field to fill the row,
wiring the field's action, initializing from and syncing with the view
model, theme styling, restyling an existing placeholder, exposing the
label and the field, the designated-initializer-only construction rule,
and UI-thread confinement — is inherited unmodified from the text edit
row; see
agentictoolkit://cookbook/ui/settings/rows/text-edit-view#behavioral-requirements
(arranges-row-layout, expands-text-field-to-fill-row,
wires-text-field-action, initializes-from-view-model,
commits-value-on-change, skips-redundant-commits, syncs-on-external-change,
applies-theme-styling, restyles-existing-placeholder,
exposes-constituent-views, requires-designated-initializer,
rejects-frame-only-initialization, confines-to-main-actor). Foreclosing
further specialization of this component is a platform-specific
construction detail, recorded in Platform Notes rather than as a
normative requirement here (see Platform Notes).

## Appearance

Inherited unmodified from the text edit row — corner radius, padding,
font, background, foreground/text, border, shadow, and min/max size are
all as documented at
agentictoolkit://cookbook/ui/settings/rows/text-edit-view#appearance; this
component sets no font, color, or layout property of its own. The one
appearance difference this specialization introduces is that the field's
typed characters render as the platform's built-in dot-mask glyphs rather
than plain text — see **masks-entry-with-secure-field** and the Default
row under States below.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; the field's underlying value equals the view model's value, rendered as one dot-mask glyph per character — the platform's own built-in masked rendering, per the source's doc comment ("so the entry is dot-masked") — see **masks-entry-with-secure-field**. |
| All other states | Editing, Committed, Placeholder shown, Disabled, Pressed, and Loading are inherited unmodified from the text edit row; see `agentictoolkit://cookbook/ui/settings/rows/text-edit-view#states`. |

## Accessibility

- **Role/trait**: Inherited unmodified from the text edit row — no
  explicit accessibility role override appears in either file; the
  platform's secure text field carries its own built-in secure-text-field
  accessibility role.
- **Label requirements**: Neither the text edit row's construction (which
  this component inherits unmodified) nor this component's own source
  links the field's accessible name to the label — unlike the sibling
  checkbox row (agentictoolkit://cookbook/ui/settings/rows/checkbox-view),
  which links its switch to its label for exactly this reason (the
  platform gives a bare switch no name). Without that link, a screen
  reader announces the field as an unnamed secure text field rather than
  by the row's title.
- **Announce state changes**: Inherited unmodified from the text edit row
  — the component has no loading state and never disables itself in
  source; masked characters being typed or deleted are announced through
  the platform's own native accessibility value reporting.
- **Minimum tap target**: Inherited unmodified from the text edit row —
  this is a pointer/trackpad-driven control composition (no touch input
  path in source); the 44×44pt minimum is touch guidance, not a
  pointer-interface requirement.
- **Contrast**: Inherited unmodified from the text edit row — the label
  and the field's typed-text color both resolve to the theme's
  `primaryText` role, and placeholder text resolves to `placeholderText`,
  which is guaranteed only a 1.6:1 contrast floor against the background
  (see `agentictoolkit://cookbook/ui/settings/rows/text-edit-view#design-decisions`
  and **contrast-ratio** in Compliance below). Whether an active theme's
  actual resolved colors clear WCAG 2.1 SC 1.4.3's 4.5:1 threshold for
  body text is a property of the chosen theme, not of this component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| secure-text-edit-view-001 | masks-entry-with-secure-field | Construct the component with any view model | The field is a secure, masking field, not a plain text field |

All other conformance test vectors — row layout, content-hugging, action
wiring, view-model sync, theme styling, placeholder restyling,
constituent-view exposure, the initializer traps, and UI-thread
confinement — are inherited unmodified from the text edit row; see
`agentictoolkit://cookbook/ui/settings/rows/text-edit-view#conformance-test-vectors`.

## Edge Cases

All edge-case behavior — the non-optional view-model parameter ruling out
a missing value, unbounded text length, UI-thread-serialized concurrent
access, the absence of any throwing or error-producing API, no
networking, and the change-notification-callback overwrite when a second
observer is constructed against the same view model — is inherited
unmodified from the text edit row, whose initializer this component
reuses without change; see
`agentictoolkit://cookbook/ui/settings/rows/text-edit-view#edge-cases`.
This component's own source contributes no code beyond constructing its
field as a secure field, so it introduces no edge case of its own.

## Configuration

Inherited unmodified from the text edit row — this component accepts no
configuration option of its own beyond the view-model parameter
documented at
`agentictoolkit://cookbook/ui/settings/rows/text-edit-view#configuration`.
The only thing this specialization changes about that shared
configuration is what the value is typically used for: per the source's
own doc comment, a secret such as an API key or password.

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in source or the behavior it inherits.

## Localization

Not applicable: this component's own source contains no user-facing
string literal of its own. The row's title comes entirely from the view
model's title, a value the caller provides, so there is nothing for this
component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Inherited unmodified from the text edit row — source contains no animation or transition call in either file; every state change is an instantaneous property assignment. |
| Increase Contrast | Inherited unmodified from the text edit row — text/label color comes from the theme's `primaryText`/`placeholderText` roles, whose actual resolved contrast (including the placeholder role's 1.6:1 floor — see **contrast-ratio** in Compliance below) is the theme layer's responsibility, not this component's. |
| Differentiate Without Color | Inherited unmodified from the text edit row; also not applicable on its own terms here — masking is communicated by replacing characters with the system's dot glyphs, not by color, so there is no color-only signal for this component to provide an alternative to. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in this component's own source or the text edit row behavior it
inherits; the row always renders once constructed.

## Analytics

Not applicable: neither this component's own source nor the text edit row
behavior it inherits contains an analytics or telemetry call.

## Privacy

- **Data collected**: The field's typed value — per the source's own doc
  comment, typically a secret such as an API key or password — which the
  platform's secure field masks on screen as it is typed. The component
  does not otherwise classify or redact this value; it holds it in the
  view model's value and passes it through unchanged (see
  `agentictoolkit://cookbook/ui/settings/rows/text-edit-view#privacy` for
  the storage, transmission, and retention behavior this shares with the
  text edit row, which applies to whatever string value either component
  holds).
- **Storage**: Not applicable within this component's own source itself —
  persistence, when it happens, is owned by the caller-supplied view
  model's backing setting: the settings store routes a setting with
  secure storage enabled to a secure storage provider (a keychain-backed
  one, by default) — this is the reason the source recommends this view
  for secrets, but none of it is code in this component's own source
  itself.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this component's own source or the text edit row behavior it
  inherits.
- **Retention**: Inherited unmodified from the text edit row — the value
  lives only in the field and the view model's value for as long as the
  row is on screen and its view model is retained; see
  `agentictoolkit://cookbook/ui/settings/rows/text-edit-view#privacy`.
- **Security-violation handling**: Not applicable — this component has no
  detection surface of its own (no validation, rate-limiting, or
  authentication logic); it only masks on-screen glyphs. Any
  violation-handling behavior belongs to whatever storage/auth layer the
  caller's setting is wired to, outside these two files.

## Logging

Not applicable: neither this component's own source nor the text edit row
behavior it inherits contains a logging call (no print, log, or logger
reference anywhere in source).

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
  initialValue)`. `final` is what forecloses further specialization (the
  requirement this recipe's Behavioral Requirements section defers to this
  entry): it makes `SecureTextEditView` the terminal specialization of
  `TextEditView` for masked entry, so the compiler rejects any attempt to
  declare a further subclass of it. The override requires `class func` (not
  `static`) because it overrides `TextEditView`'s `open class func
  makeTextField`, which trips SwiftLint's `static_over_final_class` rule
  (see Design Decisions). `TextEditView.swift`
  (`agentictoolkit://cookbook/ui/settings/rows/text-edit-view`) supplies everything else — row
  layout, content-hugging, the `textFieldChanged(_:)` target/action commit
  path, `observeTheme` styling, and `viewModel.onChange` sync — and is out of
  this recipe's scope. There is no UIKit code path in source; a UIKit port
  would replace `NSSecureTextField` with a `UITextField` configured
  `isSecureTextEntry = true`, and would enforce "no further subclassing" (if
  desired) with a `final` class declaration, UIKit's own equivalent
  mechanism.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SecureTextEditView.swift` |

## Design Decisions

Decisions governing the text edit row's inherited behavior — the
content-hugging priority, the factory-method pattern, theme-observation
placement, placeholder-restyle timing, and the placeholder contrast floor
— are recorded at
`agentictoolkit://cookbook/ui/settings/rows/text-edit-view#design-decisions`
and are not repeated here.

- **Decision**: Implement this component as a specialization of the text
  edit row overriding only its field-construction step, rather than
  composing a new view from scratch.
  **Rationale**: Per the source's own doc comment, this reuses all of the
  text edit row's row layout, theme styling, and commit wiring; the only
  difference between a plain and a secure text row is the underlying field
  type.
  **Approved**: pending
- **Decision**: Foreclose further specialization of this component
  (AppKit/UIKit source: declared `final`).
  **Rationale**: Traceable to `public final class SecureTextEditView:
  TextEditView` in source — forecloses further subclassing since it is the
  one masking variant the text edit row needs (see Platform Notes).
  **Approved**: pending
- **Decision**: Suppress a lint rule (AppKit/UIKit source: `//
  swiftlint:disable:next static_over_final_class`) on the
  field-construction override.
  **Rationale**: Overriding the text edit row's open factory method
  requires a non-static override even though this component itself
  forecloses further specialization, which trips a lint rule that
  otherwise prefers a static method — this is an intentional, documented
  suppression traceable to the source comment, not an accidental disable,
  and is recorded here per the source-fidelity requirement to document
  known workarounds.
  **Approved**: pending
- **Decision**: Treat storage and persistence of the masked value as
  entirely out of scope of this component's own source.
  **Rationale**: Per the source's own doc comment, the value is
  "typically" routed to a setting with secure storage enabled, which the
  settings store then routes to a keychain-backed secure storage provider;
  this component's own source only masks the on-screen glyphs and never
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
reader-support` is `partial` because `textField` has no accessibility label
linking it to `label`'s title text — see Label requirements in
Accessibility above; `contrast-ratio` is
`partial` because the inherited placeholder-text color clears only a 1.6:1
floor against WCAG's 4.5:1 threshold (see
`agentictoolkit://cookbook/ui/settings/rows/text-edit-view#design-decisions`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restructure to a delta-only recipe depending on text-edit-view, pruning duplicated requirements/appearance/states/test-vectors/edge-cases/configuration/privacy/logging content to the masking-specific delta (masks-entry-with-secure-field, forecloses-subclassing); reword forecloses-subclassing platform-neutrally and move the `final`/SwiftLint detail to Platform Notes; drop the macos tag; add text-edit-view to depends-on and checkbox-view to related; reformat Design Decisions to the bold convention and move the inherited placeholder-timing/contrast-floor decisions to text-edit-view; fix the WinUI Grid column order (Auto,\*) and correct WinUI/Compose/React commit timing to end-editing/submit instead of per-keystroke; add a partial contrast-ratio compliance row with a supporting sentence; remap compliance citations to the catalog |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
