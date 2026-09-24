---
id: 2e0bf51e-905d-476d-9c0c-48465174ba59
title: SecureTextEditView
domain: agentictoolkit://recipes/secure-text-edit-view
type: ingredient
version: 1.0.0
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
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# SecureTextEditView

## Overview

`SecureTextEditView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SecureTextEditView.swift`):
a `TextEditView` variant that swaps in an `NSSecureTextField` so the entry is
dot-masked. Per the source's own doc comment, it is meant for API keys,
passwords, and other secrets that are still routed through a
`ComposableSettings.ViewModel<String>` — typically one whose backing
`UserSetting<String>` has `isSecure: true` and is therefore stored through the
keychain-backed `SecureStoredSettingsStorageProvider`. `SecureTextEditView`
itself contributes exactly one override — `makeTextField(initialValue:)`
returns `NSSecureTextField(string: initialValue)` in place of the plain
`NSTextField` its superclass `TextEditView`
(`.../Views/TextEditView.swift`) would return — and inherits every other
behavior unmodified: the row layout, the theme-driven font/color styling, the
target/action commit path, and the view-model sync. This recipe documents the
full inherited behavior of the composed class, not only the override, since
that is what a caller instantiating `SecureTextEditView` actually gets.

## Behavioral Requirements

- **masks-entry-with-secure-field**: Component MUST override
  `makeTextField(initialValue:)` to return an `NSSecureTextField(string:
  initialValue)`, so `textField` is a dot-masking secure field rather than
  the plain `NSTextField` `TextEditView` would otherwise construct.
- **forecloses-subclassing**: Component MUST NOT be subclassable further; the
  class is declared `final`.
- **arranges-row-layout**: Component MUST arrange the label and the secure
  text field in a single horizontal row (`label`, then `textField`), and
  MUST pin that row to the edges of the view.
- **expands-text-field-to-fill-row**: Component MUST give `textField` a
  horizontal content-hugging priority (`NSLayoutConstraint.Priority(1)`)
  lower than the row spacer's, so the field — not the gap between it and the
  label — takes the width left over after the label.
- **wires-text-field-action**: Component MUST set `textField.target` to
  itself and `textField.action` to its `textFieldChanged(_:)` selector.
- **initializes-from-view-model**: Component MUST, during initialization,
  set the label's text to `viewModel.title` and construct `textField` with
  `viewModel.value` as its initial (masked) value.
- **commits-value-on-change**: Component MUST write the field's current
  string value into `viewModel.settingObserver.value` whenever `textField`'s
  action fires and that value differs from the current
  `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the field's value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  `viewModel.title` and the field's string value to `viewModel.value`
  whenever `viewModel.onChange` fires.
- **applies-theme-styling**: Component MUST set `textField.font` to the
  theme's `.body`-role font and `textField.textColor` to the theme's
  `primaryText` color, both immediately upon construction and again on every
  subsequent theme change (via `observeTheme`).
- **restyles-existing-placeholder**: Component MUST, whenever a theme change
  fires and `textField.placeholderString` is non-nil at that moment, replace
  `textField.placeholderAttributedString` with one styled in the theme's
  `.body`-role font and `placeholderText` color.
- **exposes-constituent-views**: Component MUST expose `label` and
  `textField` as public, directly-accessible properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class (and its superclass) is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — neither `SecureTextEditView.swift` nor
  `TextEditView.swift` adds a custom layer or draws a shape; `textField`
  keeps whatever corner rendering `NSSecureTextField`'s own default bezel
  style draws, which is AppKit's rendering, not this source's.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer
  between `label` and `textField` and sets the row `NSStackView`'s
  `spacing` to `SettingsLayout.default[.rowSpacing]` = 8pt, which applies
  to the label-to-spacer gap; `makeRow` explicitly zeroes the
  spacer-to-field gap (`setCustomSpacing(0, after: spacer)`), so the
  spacer's own width is the only thing between the label and the field.
  `textField`'s content-hugging priority is set below the spacer's, so the
  field absorbs the row's leftover width instead of the spacer (see
  expands-text-field-to-fill-row). `pinToEdges` pins the row's top,
  leading, trailing, and bottom directly to the component's own edges with
  no additional constant, so `SecureTextEditView` contributes 0pt of outer
  padding beyond that internal 8pt/0pt spacing.
- **Font**: The label (`ComposableSettings.makeRowLabel`, `textRole:
  .button`) resolves to `TextRole.button`'s style: 13pt, medium weight,
  proportional system font. `textField`'s typed text uses `TextRole.body`'s
  style: 13pt, regular weight, proportional system font
  (`palette.font(.body)`, set in `observeTheme`). Both scale with the
  active theme's size scale and repaint automatically on a theme change.
- **Background**: Not customized in source — `textField` keeps
  `NSSecureTextField(string:)`'s own default editable-field chrome
  (bordered/bezeled, background drawn); neither file sets
  `drawsBackground`, `isBordered`, or `isBezeled`, nor gives the row
  `NSStackView` or the component itself a layer or background color.
- **Foreground/Text**: The label (`role: .primaryText`) and `textField`'s
  typed text (`textField.textColor = palette.primaryTextColor`) both
  resolve to the same role — the active theme's foreground color
  unchanged (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  with no dimming) — recomputed live on a theme change. Placeholder text,
  when present, uses `placeholderText` instead: `foreground` dimmed toward
  `background` with only a `minContrast: 1.6` floor (see Design Decisions).
- **Border**: Not customized in source; whatever bezel/border
  `NSSecureTextField`'s default construction draws (AppKit's own
  rendering) applies unmodified.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `SecureTextEditView.swift` or `TextEditView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in either file; sizing is governed entirely by the
  label's and `textField`'s own intrinsic content sizes, the row's 8pt/0pt
  spacing, the content-hugging priorities described above, and
  `pinToEdges`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `textField`'s underlying value equals `viewModel.value`, rendered as one dot-mask glyph per character — `NSSecureTextField`'s own built-in masked rendering, per the source's doc comment ("so the entry is dot-masked"). |
| Editing | Not styled by source — no focus-ring customization anywhere in `SecureTextEditView.swift` or `TextEditView.swift`; AppKit's own default `NSControl`/`NSTextField` focus ring applies when the field becomes first responder. |
| Committed | After `textField`'s target/action fires (per `NSTextField`'s own default target/action semantics — on Return and on the field resigning first responder) and the new value differs from `settingObserver.value`, `textFieldChanged(_:)` writes it into `settingObserver.value`. |
| Placeholder shown | Not applicable unless a caller sets `textField.placeholderString` directly through the public `textField` property — `viewModel` carries no placeholder value of its own. When one is set and a later theme change fires, its attributed string is restyled per restyles-existing-placeholder (see Design Decisions for why the very first, construction-time apply never restyles it). |
| Disabled | Not implemented in source; `isEnabled` is never read or set on `label` or `textField`. A caller may set `textField.isEnabled` directly through the public property, at which point `NSTextField`'s native disabled dimming applies. |
| Pressed | Not applicable: a text field has no discrete pressed state distinct from becoming first responder and placing the caret; no such state is drawn in source. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized — no `setAccessibilityRole` call appears in
  `SecureTextEditView.swift` or `TextEditView.swift`; `NSSecureTextField`
  carries AppKit's own built-in secure-text-field accessibility role.
- **Label requirements**: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. Neither `TextEditView.swift` (whose `init` `SecureTextEditView`
  inherits unmodified) nor `SecureTextEditView.swift` calls
  `setAccessibilityTitleUIElement` or sets an `accessibilityLabel` linking
  `textField` to `label` — unlike the sibling `CheckboxView`, which links
  its switch to its label for exactly this reason ("AppKit gives a bare
  switch no name"). Without that link, VoiceOver announces `textField` as
  an unnamed secure text field rather than by the row's title. What would
  settle it: a decision on whether `TextEditView`/`SecureTextEditView`
  should adopt the same `setAccessibilityTitleUIElement(label)` call
  `CheckboxView` uses, or accessibility-audit evidence that this omission
  is acceptable as-is.
- **Announce state changes**: Not applicable — the component has no loading
  state and never disables itself in source (see States); masked
  characters being typed or deleted are announced through
  `NSSecureTextField`'s own native accessibility value reporting,
  unmodified by either file.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/trackpad-driven `NSView`/`NSControl` composition (no touch input
  path in source); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement. No `controlSize` is set on `textField`, so
  it keeps `NSSecureTextField`'s regular system click-target metrics.
- **Contrast**: Not set independently by this component — `label` and
  `textField`'s typed-text color both resolve to the theme's `primaryText`
  role (theme foreground, unchanged; no minimum contrast is computed for
  this role), and placeholder text resolves to `placeholderText`, which the
  same derivation dims toward the background with only a `minContrast: 1.6`
  floor (see Design Decisions). Whether an active theme's actual resolved
  colors clear WCAG 2.1 SC 1.4.3's 4.5:1 threshold for body text is a
  property of the chosen `ColorTheme`, not of `SecureTextEditView.swift`.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| secure-text-edit-view-001 | masks-entry-with-secure-field | Construct `SecureTextEditView` with any `viewModel` | `textField` is an instance of `NSSecureTextField`, not a plain `NSTextField` |
| secure-text-edit-view-002 | forecloses-subclassing | Attempt to declare a subclass of `ComposableSettings.SecureTextEditView` | Compiler rejects the declaration (`final`) |
| secure-text-edit-view-003 | arranges-row-layout | Construct `SecureTextEditView` with any `viewModel` | `label` and `textField` are both subviews of a single row view that is pinned to the component's edges; no other layout container appears |
| secure-text-edit-view-004 | expands-text-field-to-fill-row | Inspect `textField`'s horizontal content-hugging priority after construction | Equals `NSLayoutConstraint.Priority(1)`, lower than the row spacer's hugging priority |
| secure-text-edit-view-005 | wires-text-field-action | Any initialized `SecureTextEditView` | `textField.target === view`; `textField.action == Selector("textFieldChanged:")` |
| secure-text-edit-view-006 | initializes-from-view-model | `viewModel.title = "API Key"`, `viewModel.value = "sk-test"` | After init, `label.stringValue == "API Key"` and `textField.stringValue == "sk-test"` |
| secure-text-edit-view-007 | commits-value-on-change | `viewModel.settingObserver.value = "old"`; set `textField.stringValue = "new"` and invoke `textFieldChanged(textField)` | `viewModel.settingObserver.value == "new"` after the call |
| secure-text-edit-view-008 | skips-redundant-commits | `viewModel.settingObserver.value = "same"`; set `textField.stringValue = "same"` and invoke `textFieldChanged(textField)` | `settingObserver.value`'s setter is not invoked a second time (no additional write/observer notification is recorded) |
| secure-text-edit-view-009 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `textField.stringValue` both update to reflect the new `viewModel` state |
| secure-text-edit-view-010 | applies-theme-styling | Construct the view, then trigger a theme change | `textField.font` equals the theme's `.body`-role font and `textField.textColor` equals the theme's `primaryText` color, both immediately after construction and again after the theme change |
| secure-text-edit-view-011 | restyles-existing-placeholder | After construction, set `textField.placeholderString = "Enter key"`, then trigger a theme change | `textField.placeholderAttributedString`'s color attribute equals the theme's `placeholderText` color and its font equals the theme's `.body`-role font |
| secure-text-edit-view-012 | exposes-constituent-views | Construct the component, then access `.label` and `.textField` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSSecureTextField` instances built during init |
| secure-text-edit-view-013 | requires-designated-initializer | Attempt `SecureTextEditView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| secure-text-edit-view-014 | rejects-frame-only-initialization | Attempt `SecureTextEditView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| secure-text-edit-view-015 | confines-to-main-actor | Attempt to construct or mutate a `SecureTextEditView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ViewModel<String>`) is
  a non-optional, typed constructor parameter; Swift's type system rules
  out `nil`. An empty `viewModel.title` or `viewModel.value` produces an
  empty label or field with no crash. This is a MUST: the component
  provides, and needs, no nil-handling path for its one initializer
  parameter.
- Boundary values: Not applicable — the bound value is `String` with no
  minimum or maximum length enforced anywhere in `SecureTextEditView.swift`
  or `TextEditView.swift`; any length is accepted and displayed as-is
  (masked).
- Concurrent access: Not applicable — the class and its superclass are
  declared `@MainActor`, so all construction and mutation is serialized to
  the main actor by the compiler (see confines-to-main-actor).
- Error states: Not applicable — every operation in these two files (the
  field's target-action commit and the `settingObserver.value` write) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing
  API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ViewModel<String>`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `TextEditView.init` (inherited unmodified by
  `SecureTextEditView`) unconditionally assigns
  `viewModel.onChange = { [weak self] _ in ... }`, replacing whatever
  handler, if any, was previously registered on that `viewModel`. This is a
  MUST-level, source-traceable consequence of plain closure-property
  assignment: the component MUST NOT be assumed to coexist with another
  `onChange` observer already registered on the same view-model instance —
  constructing a second `SecureTextEditView` (or any other observer)
  against the same view model silently drops the earlier handler.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<String>` | — (required) | Supplies the row's title and current string value; receives committed edits via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted but never read or displayed by `SecureTextEditView`/`TextEditView`. |

## Deep Linking

Not applicable: `SecureTextEditView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `SecureTextEditView.swift` or `TextEditView.swift`.

## Localization

Not applicable: neither file contains a user-facing string literal of its
own. The row's title comes entirely from `viewModel.title`, a value the
caller provides, so there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call in either file; every state change is an instantaneous property assignment (`label.stringValue`, `textField.stringValue`, `textField.font`/`textColor`). |
| Increase Contrast | Not applicable to this file directly: `SecureTextEditView.swift`/`TextEditView.swift` set no literal `NSColor`; text/label color comes from the theme's `primaryText`/`placeholderText` roles, whose actual resolved contrast (including the placeholder role's 1.6:1 floor — see Design Decisions and the Accessibility section's Contrast note) is the theme layer's responsibility, not this component's; `textField`'s bezel/border follow AppKit's own default rendering. |
| Differentiate Without Color | Not applicable: masking is communicated by replacing characters with the system's dot glyphs, not by color, so there is no color-only signal for this component to provide an alternative to. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `SecureTextEditView.swift` or `TextEditView.swift`; the row always
renders once constructed.

## Analytics

Not applicable: neither `SecureTextEditView.swift` nor `TextEditView.swift`
contains an analytics or telemetry call.

## Privacy

- **Data collected**: The field's typed value — per the source's doc
  comment, typically a secret such as an API key or password — which
  `NSSecureTextField` masks on screen as it is typed. The component does
  not otherwise classify or redact this value; it holds it in
  `viewModel.settingObserver.value` and passes it through unchanged.
- **Storage**: Not applicable within these two files — `SecureTextEditView`
  and `TextEditView` hold the value only in `textField.stringValue` and
  `viewModel.settingObserver.value` for the view's lifetime. Persistence,
  when it happens, is owned by the caller-supplied
  `ComposableSettings.ViewModel<String>`'s backing `UserSetting<String>`:
  `SettingsStore` routes a setting with `isSecure: true` to
  `SecureSettingsStorageProvider` (`KeychainSecureSettingsStorageProvider`
  by default), i.e. the keychain — none of which is code in
  `SecureTextEditView.swift` itself.
- **Transmission**: Not applicable — no networking call appears anywhere in
  either file. Where the committed value goes afterward is entirely owned
  by whatever consumes `viewModel.settingObserver.value`.
- **Retention**: The value lives only in `textField.stringValue` and
  `viewModel.settingObserver.value` for as long as the row is on screen and
  its view model is retained. No explicit zeroing or secure-erasure call is
  made on the string anywhere in `SecureTextEditView.swift` or
  `TextEditView.swift`; the value is released along with the view and its
  view model like any other property.
- **Security-violation handling**: Not applicable — this component has no
  detection surface of its own (no validation, rate-limiting, or
  authentication logic); it only masks on-screen glyphs. Any
  violation-handling behavior belongs to whatever storage/auth layer the
  caller's `UserSetting<String>` is wired to, outside these two files.

## Logging

Not applicable: neither `SecureTextEditView.swift` nor `TextEditView.swift`
contains a logging call (no `print`, `os_log`, or logger reference anywhere
in source).

## Platform Notes

- **SwiftUI**: Replace with an `HStack` pairing `Text(viewModel.title)`
  leading and a trailing `SecureField("", text: $value)`, writing the
  binding's setter back into the underlying setting with an equality guard
  before assigning, mirroring skips-redundant-commits. Give the field an
  explicit `.accessibilityLabel(viewModel.title)` — the fix this recipe's
  Accessibility section flags as missing from the AppKit source — and drive
  its font/color from the same semantic theme tokens (`.body`,
  `primaryText`, `placeholderText`) rather than fixed literals, mirroring
  applies-theme-styling/restyles-existing-placeholder.
- **Compose**: Use a `Row` with `Text(title)` leading and a trailing
  `OutlinedTextField(value = value, onValueChange = { ... },
  visualTransformation = PasswordVisualTransformation(), singleLine =
  true)` — `PasswordVisualTransformation` is Compose's dot-masking analog
  of `NSSecureTextField`. Give it `Modifier.semantics { contentDescription
  = title }` (the missing accessibility link's Compose analog), and commit
  to the backing state/view model inside `onValueChange` with an equality
  check before writing, mirroring skips-redundant-commits.
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title and
  an `<input type="password">` whose `aria-labelledby` points at the title
  `<label>`'s `id` — the web analog of the accessibility link this recipe
  flags as missing from the source. Commit the new value on the input's
  `onChange` handler, comparing against the previous value before calling
  the parent's setter, mirroring skips-redundant-commits; style the input's
  font/color and any placeholder from theme tokens equivalent to `.body`/
  `primaryText`/`placeholderText`, mirroring applies-theme-styling.
- **AppKit/UIKit** (source platform): Source files
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SecureTextEditView.swift`
  (the class itself: a macOS-only, `@MainActor`, `final` subclass of
  `TextEditView` inside the `ComposableSettings` namespace, overriding only
  `makeTextField(initialValue:)` to return `NSSecureTextField(string:
  initialValue)`) and its superclass in the same directory,
  `TextEditView.swift`, which supplies the row layout, content-hugging
  setup, `textFieldChanged(_:)` target/action commit path, `observeTheme`
  styling, and `viewModel.onChange` sync. Both files are macOS-only
  (`import AppKit`); there is no UIKit code path in source. A UIKit port
  would replace `NSSecureTextField` with a `UITextField` configured
  `isSecureTextEntry = true` and the target/action pattern with
  `.addTarget(_:action:for: .editingDidEndOnExit)`.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column 0
  (the `*` column claims the row's leading space, the WinUI analog of
  `makeRow`'s flexible spacer between the label and the control), and a
  `PasswordBox` — WinUI's own dot-masking control and the direct analog of
  `NSSecureTextField` — in column 1, `HorizontalAlignment="Stretch"` so it
  takes the leftover width the way expands-text-field-to-fill-row does. Set
  `AutomationProperties.LabeledBy` on the `PasswordBox` to the `TextBlock`
  — the WinUI analog of the `setAccessibilityTitleUIElement` link this
  recipe flags as missing from the AppKit source; add it in the port even
  though the source itself omits it. Commit on the `PasswordBox.PasswordChanged`
  event, writing through a property setter that skips the assignment (and
  so skips raising `INotifyPropertyChanged`) when the incoming value
  already equals the current one, mirroring skips-redundant-commits. Bind
  `PasswordBox.Foreground` and `PlaceholderForeground` to theme resource
  brushes equivalent to `primaryText`/`placeholderText` rather than
  hardcoded colors, mirroring applies-theme-styling/restyles-existing-placeholder.
  Note `PasswordBox` ships its own built-in reveal-password toggle button,
  an affordance neither `NSSecureTextField` nor this source provides;
  carrying it over in the port is a platform enhancement, not something to
  gate on parity with the AppKit source.

## Design Decisions

- Decision: Implement `SecureTextEditView` as a `TextEditView` subclass
  overriding only `makeTextField(initialValue:)`, rather than composing a
  new view from scratch.
  Rationale: per the source's own doc comment, this reuses all of
  `TextEditView`'s row layout, theme styling, and commit wiring; the only
  difference between a plain and a secure text row is the underlying
  `NSTextField` subclass.
  Approved: pending
- Decision: Mark `SecureTextEditView` `final`.
  Rationale: traceable to `public final class SecureTextEditView:
  TextEditView` in source — forecloses further subclassing since it is the
  one masking variant `TextEditView` needs.
  Approved: pending
- Decision: Suppress SwiftLint's `static_over_final_class` rule
  (`// swiftlint:disable:next static_over_final_class`) on the
  `makeTextField` override.
  Rationale: overriding `TextEditView`'s `open class func makeTextField`
  requires `class func` even though `SecureTextEditView` itself is `final`,
  which trips a lint rule that otherwise prefers `static` — this is an
  intentional, documented suppression traceable to the source comment, not
  an accidental disable, and is recorded here per the source-fidelity
  requirement to document known workarounds.
  Approved: pending
- Decision: Restyle an existing `textField.placeholderString` only on a
  theme change that occurs *after* construction, never on the initial
  apply.
  Rationale: `ThemePaletteObserver.init`
  (`external/agenticdevelopertoolkit/.../Theme/ThemeBinding.swift`) applies
  its closure immediately upon registration, which happens inside
  `TextEditView.init` before any caller can reach the newly-created
  `textField` to set a placeholder — so that first, construction-time apply
  always finds `field.placeholderString == nil` and the `if let` guard in
  `observeTheme`'s closure skips it. The placeholder is only ever styled by
  a later, caller-triggered theme change. This is a non-obvious consequence
  of the two files' evaluation order, not a bug being idealized away.
  Approved: pending
- Decision: Accept that placeholder text is guaranteed only a 1.6:1
  contrast floor against the background.
  Rationale: `SemanticPalette.derive(.placeholderText)`
  (`external/agenticdevelopertoolkit/.../Theme/SemanticPalette.swift`) dims
  the theme's foreground toward its background with `minContrast: 1.6` —
  below WCAG 2.1 SC 1.4.3's 4.5:1 floor for normal text. This is a
  theme-layer choice inherited by every themed field, including this one;
  `SecureTextEditView.swift` neither sets nor can override it. Recorded
  here as technical debt affecting accessibility correctness, per
  source-fidelity's requirement to document such debt rather than idealize
  it away.
  Approved: pending
- Decision: Treat storage and persistence of the masked value as entirely
  out of scope of `SecureTextEditView.swift`.
  Rationale: per the source's own doc comment, the value is "typically"
  routed to a `UserSetting<String>` with `isSecure: true`, which
  `SettingsStore` then routes to `KeychainSecureSettingsStorageProvider`;
  `SecureTextEditView.swift` only masks the on-screen glyphs and never
  itself reads or writes the keychain.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
