---
id: c1787e74-2485-4d7b-a219-feb4c07cf97c
title: TextEditView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/text-edit-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings text row pairing a label with a plain NSTextField,
  synced to a ViewModel<String> and restyled on every theme change.
platforms:
- swift
- macos
tags:
- settings
- form-control
- text-input
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/secure-text-edit-view
references: []
approved-by: ''
approved-date: ''
---

# TextEditView

## Overview

`TextEditView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextEditView.swift`):
a leading label paired with a trailing plain `NSTextField`, bound to a
`ComposableSettings.ViewModel<String>`. It builds its text field through an
`open class func makeTextField(initialValue:)` factory so a subclass can
substitute a different `NSTextField` subclass while inheriting everything
else — the row layout, the theme-driven font/color styling, the
target/action commit path, and the view-model sync. `SecureTextEditView`
(`.../Views/SecureTextEditView.swift`, documented separately at
`agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/secure-text-edit-view`) is the one subclass
present in source, overriding only that factory to return an
`NSSecureTextField`. This recipe documents `TextEditView` itself: the
behavior every row built from it — plain or secure — inherits.

## Behavioral Requirements

- **constructs-plain-text-field**: Component MUST construct `textField` by
  calling `makeTextField(initialValue:)` with `viewModel.value`, whose
  default implementation on `TextEditView` returns
  `NSTextField(string: initialValue)`.
- **supports-text-field-substitution**: Component MUST declare
  `makeTextField(initialValue:)` as `open class func`, so a subclass can
  override it to return a different `NSTextField` subclass (as
  `SecureTextEditView` does) while reusing every other `TextEditView`
  behavior unmodified.
- **arranges-row-layout**: Component MUST arrange the label and the text
  field in a single horizontal row (`label`, then `textField`), and MUST
  pin that row to the edges of the view.
- **expands-text-field-to-fill-row**: Component MUST give `textField` a
  horizontal content-hugging priority lower than the row spacer's, so the
  field — not the gap between it and the label — takes the width left over
  after the label (see Design Decisions for the specific priority value).
- **wires-text-field-action**: Component MUST route `textField`'s
  target/action commit to itself, so a committed edit reaches
  `settingObserver` (see Platform Notes for the specific selector).
- **initializes-from-view-model**: Component MUST, during initialization,
  set the label's text to `viewModel.title` and construct `textField` with
  `viewModel.value` as its initial value.
- **commits-value-on-change**: Component MUST write the field's current
  string value into `viewModel.settingObserver.value` whenever
  `textField`'s action fires and that value differs from the current
  `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the field's value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  `viewModel.title` and the field's string value to `viewModel.value`
  whenever `viewModel.onChange` fires.
- **applies-theme-styling**: Component MUST set `textField.font` to the
  theme's `.body`-role font and `textField.textColor` to the theme's
  `primaryText` color, both immediately upon construction and again on
  every subsequent theme change (via `observeTheme`).
- **restyles-existing-placeholder**: Component MUST, whenever a theme
  change fires and `textField.placeholderString` is non-nil at that
  moment, replace `textField.placeholderAttributedString` with one styled
  in the theme's `.body`-role font and `placeholderText` color.
- **exposes-constituent-views**: Component MUST expose `label` and
  `textField` as public, directly-accessible, immutable (`let`)
  properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **conforms-to-settings-view-protocol**: Component MUST conform to
  `SettingsViewProtocol`, a marker protocol
  (`.../Views/SettingsViewProtocol.swift`) that `ComposableSettings` uses
  to type its row views; the protocol adds no requirements of its own
  beyond `NSView` conformance.
- **claims-sole-onchange-observer**: Component MUST assign its own handler
  to `viewModel.onChange` during initialization
  (`viewModel.onChange = { [weak self] _ in ... }`), superseding any
  handler already registered on that view model instance (see
  **overwritten external observer** in Edge Cases).

## Appearance

- **Corner radius**: Not applicable — `TextEditView.swift` adds no custom
  layer or drawn shape; `textField` keeps whatever corner rendering
  `NSTextField`'s own default bezel style draws, which is AppKit's
  rendering, not this source's.
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
  no additional constant, so `TextEditView` contributes 0pt of outer
  padding beyond that internal 8pt/0pt spacing.
- **Font**: The label (`ComposableSettings.makeRowLabel`, `textRole:
  .button`) resolves to `TextRole.button`'s default style: 13pt, medium
  weight, proportional system font. `textField`'s typed text uses
  `TextRole.body`'s default style: 13pt, regular weight, proportional
  system font (`palette.font(.body)`, set in `observeTheme`). Both scale
  with the active theme's `sizeScale` and repaint automatically on a theme
  change.
- **Background**: Not customized in source — `textField` keeps
  `NSTextField(string:)`'s own default editable-field chrome
  (bordered/bezeled, background drawn); the file sets neither
  `drawsBackground`, `isBordered`, nor `isBezeled`, and gives the row
  `NSStackView` or the component itself no layer or background color.
- **Foreground/Text**: The label (`role: .primaryText`) and `textField`'s
  typed text (`textField.textColor = palette.primaryTextColor`) both
  resolve to the same role — the active theme's foreground color
  unchanged — recomputed live on a theme change. Placeholder text, when
  present, uses `placeholderText` instead (see Design Decisions for its
  contrast floor).
- **Border**: Not customized in source; whatever bezel/border
  `NSTextField`'s default construction draws (AppKit's own rendering)
  applies unmodified.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `TextEditView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set; sizing is governed entirely by the label's and
  `textField`'s own intrinsic content sizes, the row's 8pt/0pt spacing,
  the content-hugging priorities described above, and `pinToEdges`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `textField`'s value equals `viewModel.value`, rendered as plain typed characters. |
| Editing | Not styled by source — no focus-ring customization anywhere in `TextEditView.swift`; AppKit's own default `NSControl`/`NSTextField` focus ring applies when the field becomes first responder. |
| Committed | After `textField`'s target/action fires (per `NSTextField`'s own default target/action semantics — on Return and on the field resigning first responder) and the new value differs from `settingObserver.value`, `textFieldChanged(_:)` writes it into `settingObserver.value`. |
| Placeholder shown | Not applicable unless a caller sets `textField.placeholderString` directly through the public `textField` property — `viewModel` carries no placeholder value of its own. When one is set and a later theme change fires, its attributed string is restyled per restyles-existing-placeholder (see Design Decisions for why the very first, construction-time apply never restyles it). |
| Disabled | Not implemented in source; `isEnabled` is never read or set on `label` or `textField`. A caller may set `textField.isEnabled` directly through the public property, at which point `NSTextField`'s native disabled dimming applies. |
| Pressed | Not applicable: a text field has no discrete pressed state distinct from becoming first responder and placing the caret; no such state is drawn in source. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized — no `setAccessibilityRole` call appears
  in `TextEditView.swift`; `NSTextField` carries AppKit's own built-in
  text-field accessibility role.
- **Label requirements**: `TextEditView.swift` never calls
  `setAccessibilityTitleUIElement` or otherwise links `textField` to
  `label` — unlike the sibling `CheckboxView`, which links its switch to
  its label for exactly this reason ("AppKit gives a bare switch no
  name"). Without that link, VoiceOver announces `textField` as an
  unnamed text field rather than by the row's title. Because
  `SecureTextEditView` inherits `init` unmodified, the same gap applies
  there.
- **Announce state changes**: Not applicable — the component has no
  loading state and never disables itself in source (see States); typed
  characters being entered or deleted are announced through
  `NSTextField`'s own native accessibility value reporting, unmodified by
  this file.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/trackpad-driven `NSView`/`NSControl` composition (no touch input
  path in source); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement. No `controlSize` is set on `textField`,
  so it keeps `NSTextField`'s regular system click-target metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `label` and `textField`'s typed-text color both resolve to the theme's `primaryText` role (no minimum contrast computed for this role), and placeholder text resolves to `placeholderText`, dimmed toward the background with only a `minContrast: 1.6` floor (see Design Decisions) — below WCAG 2.1 SC 1.4.3's 4.5:1 threshold for body text; settling it needs the text-to-background ratio measured for both roles under every shipped `ColorTheme`, or a raised `placeholderText` floor in the theme layer.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| text-edit-view-001 | constructs-plain-text-field | Construct `TextEditView` with any `viewModel` | `textField` is an instance of `NSTextField` whose `stringValue` equals `viewModel.value` |
| text-edit-view-002 | supports-text-field-substitution | Declare a subclass of `TextEditView` overriding `makeTextField(initialValue:)` to return an `NSSecureTextField` | The subclass compiles and constructing it produces a `textField` of the overridden type, with the row layout, theming, and commit wiring unchanged |
| text-edit-view-003 | arranges-row-layout | Construct `TextEditView` with any `viewModel` | `label` and `textField` are both subviews of a single row view that is pinned to the component's edges; no other layout container appears |
| text-edit-view-004 | expands-text-field-to-fill-row | Inspect `textField`'s horizontal content-hugging priority relative to the row spacer's after construction | `textField`'s priority is lower than the row spacer's hugging priority, so the field absorbs the row's leftover width (see Design Decisions for the exact value) |
| text-edit-view-005 | wires-text-field-action | Any initialized `TextEditView` | `textField.target` is the view itself; invoking `textField`'s registered commit action reaches the view's edit-commit handler, which can write to `settingObserver` (see Platform Notes for the specific selector name) |
| text-edit-view-006 | initializes-from-view-model | `viewModel.title = "Server Name"`, `viewModel.value = "prod-1"` | After init, `label.stringValue == "Server Name"` and `textField.stringValue == "prod-1"` |
| text-edit-view-007 | commits-value-on-change | `viewModel.settingObserver.value = "old"`; set `textField.stringValue = "new"` and invoke `textFieldChanged(textField)` | `viewModel.settingObserver.value == "new"` after the call |
| text-edit-view-008 | skips-redundant-commits | `viewModel.settingObserver.value = "same"`; set `textField.stringValue = "same"` and invoke `textFieldChanged(textField)`, observing writes via a recording spy or observer registered on `settingObserver` | The spy/observer records zero additional writes to `settingObserver.value` after the call |
| text-edit-view-009 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `textField.stringValue` both update to reflect the new `viewModel` state |
| text-edit-view-010 | applies-theme-styling | Construct the view, then trigger a theme change | `textField.font` equals the theme's `.body`-role font and `textField.textColor` equals the theme's `primaryText` color, both immediately after construction and again after the theme change |
| text-edit-view-011 | restyles-existing-placeholder | After construction, set `textField.placeholderString = "Enter value"`, then trigger a theme change | `textField.placeholderAttributedString`'s color attribute equals the theme's `placeholderText` color and its font equals the theme's `.body`-role font |
| text-edit-view-012 | exposes-constituent-views | Construct the component, then access `.label` and `.textField` from outside the type | Both properties are accessible and return the same `NSTextField` instances built during init |
| text-edit-view-013 | requires-designated-initializer | Attempt `TextEditView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| text-edit-view-014 | rejects-frame-only-initialization | Attempt `TextEditView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| text-edit-view-015 | confines-to-main-actor | (Static/compile-time check, not a runtime assertion) Attempt to construct or mutate a `TextEditView` from off the main actor | The call fails to compile under Swift's `@MainActor` isolation checking; there is no runtime behavior to observe |
| text-edit-view-016 | conforms-to-settings-view-protocol | Any `TextEditView` instance | `view is SettingsViewProtocol` evaluates `true` |
| text-edit-view-017 | claims-sole-onchange-observer | Register an observer closure on `viewModel.onChange`, then construct a `TextEditView` against that same `viewModel` | `viewModel.onChange` now points at `TextEditView`'s own handler; invoking it no longer calls the previously registered closure |

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ViewModel<String>`) is
  a non-optional, typed constructor parameter, so Swift's type system rules
  out `nil` entirely; the component needs no nil-handling path for its one
  initializer parameter. An empty `viewModel.title` or `viewModel.value`
  produces an empty label or field with no crash.
- Boundary values: Not applicable — the bound value is `String` with no
  minimum or maximum length enforced anywhere in `TextEditView.swift`; any
  length is accepted and displayed as-is.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see confines-to-main-actor).
- Error states: Not applicable — every operation in this file (the
  field's target-action commit and the `settingObserver.value` write) is
  a synchronous, non-throwing call; no `try`, `Result`, or error-producing
  API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ViewModel<String>`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `TextEditView.init` unconditionally assigns
  `viewModel.onChange = { [weak self] _ in ... }`, replacing whatever
  handler (if any) was previously registered on that `viewModel` (see
  **claims-sole-onchange-observer**). Constructing a second `TextEditView`
  (or `SecureTextEditView`, or any other observer) against the same view
  model silently drops the earlier handler.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<String>` | — (required) | Supplies the row's title and current string value; receives committed edits via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted but never read or displayed by `TextEditView`. |

## Deep Linking

Not applicable: `TextEditView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `TextEditView.swift`.

## Localization

Not applicable: the file contains no user-facing string literal of its
own. The row's title comes entirely from `viewModel.title`, a value the
caller provides, so there is nothing for this component to localize
itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `textField.stringValue`, `textField.font`/`textColor`). |
| Increase Contrast | Not applicable to this file directly: `TextEditView.swift` sets no literal `NSColor`; text/label color comes from the theme's `primaryText`/`placeholderText` roles, whose actual resolved contrast (including the placeholder role's 1.6:1 floor — see Design Decisions and the Accessibility section's Contrast note) is the theme layer's responsibility, not this component's; `textField`'s bezel/border follow AppKit's own default rendering. |
| Differentiate Without Color | Not applicable: the field's content is the plain typed text itself; no state in this component is communicated by color alone. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in `TextEditView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `TextEditView.swift` contains no analytics or telemetry
call.

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

## Logging

Not applicable: `TextEditView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextEditView.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |

`native-controls-preference` and `platform-design-language` rest on
`textField` being an unmodified `NSTextField` with AppKit's default bezel
styling; `keyboard-navigable` rests on the field's inherited, unmodified
`NSControl` tab order (no custom key handling in source); `screen-reader-
support` is `partial` because the accessibility title link to `label` is
missing (see Accessibility's Label requirements above); `idempotent-
operations` rests on skips-redundant-commits's equality check before
writing to `settingObserver.value`; `separation-of-concerns` rests on the
view holding no persistence or business logic of its own — commits pass
straight through to the caller-supplied `settingObserver`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: promote the onChange-overwrite edge case to a named claims-sole-onchange-observer requirement with a test vector and a pending design decision; reword the null-input edge case to drop normative language; state committed-edit routing and the field's content-hugging priority as observable outcomes instead of a private selector/literal, moving the selector name to Platform Notes; correct SwiftUI/Compose/React commit timing to submit-or-focus-loss instead of per-keystroke, matching NSTextField's target/action semantics; fix the WinUI Grid column order (Auto,*) so the TextBox actually stretches; remove the malformed fatalError decision and log it as a known source bug in Platform Notes instead; drop the "(the reason this recipe exists)" filler; reformat Design Decisions to the bold convention and add a pending accessibility-label decision; clarify test vectors 008 (spy-based write count) and 015 (compile-time check); title-case Compliance categories and add a supporting sentence; backfill the initial Change History row; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
