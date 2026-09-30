<!-- leaf: implement-general-view-3/text-edit-view · source: text-edit-view.md -->

**Rules** (cite as `implement-general-view-3/text-edit-view#<slug>`):

- `constructs-plain-text-field` MUST
- `supports-text-field-substitution` MUST
- `arranges-row-layout` MUST
- `expands-text-field-to-fill-row` MUST
- `wires-text-field-action` MUST
- `initializes-from-view-model` MUST
- `commits-value-on-change` MUST
- `skips-redundant-commits` MUST
- `syncs-on-external-change` MUST
- `applies-theme-styling` MUST
- `restyles-existing-placeholder` MUST
- `exposes-constituent-views` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST
- `confines-to-main-actor` MUST
- `conforms-to-settings-view-protocol` MUST
- `claims-sole-onchange-observer` MUST

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
`agentictoolkit://recipes/secure-text-edit-view`) is the one subclass
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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<String>` | — (required) | Supplies the row's title and current string value; receives committed edits via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted but never read or displayed by `TextEditView`. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `textField.stringValue`, `textField.font`/`textColor`). |
| Increase Contrast | Not applicable to this file directly: `TextEditView.swift` sets no literal `NSColor`; text/label color comes from the theme's `primaryText`/`placeholderText` roles, whose actual resolved contrast (including the placeholder role's 1.6:1 floor — see Design Decisions and the Accessibility section's Contrast note) is the theme layer's responsibility, not this component's; `textField`'s bezel/border follow AppKit's own default rendering. |
| Differentiate Without Color | Not applicable: the field's content is the plain typed text itself; no state in this component is communicated by color alone. |

