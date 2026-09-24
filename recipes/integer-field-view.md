---
id: a7653559-cb70-43db-a75c-d032e4f599b3
title: IntegerFieldView
domain: agentictoolkit://recipes/integer-field-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row forwarding to NumberFieldView<Int>, pairing
  a title label with a bounded, locale-aware integer text field.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
- numeric
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# IntegerFieldView

## Overview

`IntegerFieldView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/IntegerFieldView.swift`):
a title label leading and a narrow, right-aligned integer text field trailing,
clamped to a `RangeViewModel<Int>`'s bounds. Per the source's own doc comment,
it exists because "a slider is the wrong control for a number the user
already knows" — "12 points on the left" is typed, not dragged — and a
`StepperView` "makes you click twelve times to say it." The type is kept as a
thin, forwarding wrapper around a private `NumberFieldView<Int>`
(`.../Views/NumberFieldView.swift`), which does the actual work: it builds
the label and field, wires theming and accessibility, and owns the
locale-aware parse/clamp/commit logic described below. `IntegerFieldView`
stays as public API "because it is public API of a framework other repos
link: a bounded integer field is still exactly this call" (source comment).

## Behavioral Requirements

- **wraps-number-field-view**: Component MUST construct a private
  `NumberFieldView<Int>`, passing the supplied `RangeViewModel<Int>` as its
  view model and `viewModel.minValue`/`viewModel.maxValue` as its
  `minimum`/`maximum` bounds.
- **exposes-constituent-views**: Component MUST expose `label` and
  `textField` as public properties, set to the wrapped `NumberFieldView`'s
  own `label` and `textField` instances.
- **arranges-single-child**: Component MUST add the wrapped
  `NumberFieldView` as its only subview and pin it to its own top, leading,
  trailing, and bottom edges, contributing no additional outer padding of
  its own.
- **forwards-editing-end-to-wrapped-field**: Component's
  `controlTextDidEndEditing(_:)` MUST call `commit()` on the wrapped
  `NumberFieldView`.
- **defaults-field-width-to-52-points**: Component's initializer MUST
  default `fieldWidth` to 52 points when the caller supplies none, and MUST
  pass that value through to the wrapped `NumberFieldView`'s own
  `fieldWidth` parameter.
- **forwards-label-width**: Component's initializer MUST pass its own
  `labelWidth` parameter (default `nil`) through unchanged to the wrapped
  `NumberFieldView`.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **builds-label-from-view-model-title**: The wrapped field's `label` MUST
  be built via `ComposableSettings.makeRowLabel(viewModel.title)`.
- **right-aligns-field-text**: The wrapped field's `textField` MUST set
  `alignment = .right`.
- **initializes-display-from-view-model**: At the end of initialization,
  the wrapped field MUST set `label.stringValue` to `viewModel.title` and
  `textField.stringValue` to `viewModel.value.settingsFieldString`.
- **wires-field-target-action**: The wrapped field MUST set
  `textField.target` to itself and `textField.action` to its
  `fieldChanged(_:)` selector.
- **delegates-field-to-wrapped-view**: The wrapped field MUST set
  `textField.delegate` to itself (the `NumberFieldView` instance, not the
  outer `IntegerFieldView`).
- **links-field-accessibility-title**: The wrapped field MUST call
  `textField.setAccessibilityTitleUIElement(label)`.
- **themes-field-live**: The wrapped field MUST set `textField.font` to
  `palette.font(.code)` and `textField.textColor` to
  `palette.primaryTextColor`, both immediately on construction and again
  every time the active theme changes.
- **fixes-field-width**: The wrapped field MUST constrain
  `textField.widthAnchor` to the constant `fieldWidth` supplied at
  construction.
- **aligns-label-when-width-fixed**: When `labelWidth` is non-nil, the
  wrapped field MUST right-align `label` and pin its width to that
  constant.
- **lays-out-content-width-row-when-label-fixed**: When `labelWidth` is
  non-nil, the wrapped field MUST pin the row's top, leading, and bottom
  edges to the container and constrain the row's trailing edge
  `lessThanOrEqualTo` the container's trailing edge.
- **lays-out-full-width-row-by-default**: When `labelWidth` is `nil`, the
  wrapped field MUST pin the row to all four edges of the container instead
  of the content-width layout.
- **commits-on-field-action**: The wrapped field MUST call `commit()`
  whenever `textField`'s target-action fires (`fieldChanged(_:)`).
- **commits-on-editing-end**: The wrapped field MUST call `commit()`
  whenever its own `controlTextDidEndEditing(_:)` delegate callback fires.
- **parses-locale-aware-integer-text**: `commit()` MUST parse
  `textField.stringValue` as an `Int` by first attempting a POSIX parse,
  then, only if that fails, a locale-aware decimal parse that requires the
  entire string to be consumed and the result to be an exact, finite
  integer within `Int`'s range; any other text MUST be treated as
  unparseable.
- **reverts-on-unparseable-text**: When `commit()` cannot parse
  `textField.stringValue` as an `Int`, it MUST leave
  `viewModel.settingObserver.value` unchanged and MUST reset both
  `label.stringValue` and `textField.stringValue` from the view model's
  current title/value.
- **clamps-to-bounds**: When `minimum` and `maximum` are not both set with
  `minimum` greater than `maximum`, `commit()` MUST clamp a successfully
  parsed value up to `minimum` (if the value is lower) and then down to
  `maximum` (if the value is higher) before storing it.
- **skips-clamp-on-contradictory-bounds**: When both `minimum` and
  `maximum` are set and `minimum` is greater than `maximum`, `commit()`
  MUST store the parsed value unclamped.
- **redisplays-committed-text**: After computing the value to store,
  `commit()` MUST set `textField.stringValue` to that value's
  `settingsFieldString` whenever it differs from the field's current text.
- **skips-redundant-commits**: `commit()` MUST NOT write to
  `viewModel.settingObserver.value` when the computed value equals its
  current value.
- **syncs-on-external-change**: The wrapped field's initializer MUST
  assign `viewModel.onChange` to a closure that re-sets `label.stringValue`
  and `textField.stringValue` from the view model, and that closure MUST
  fire whenever `viewModel.onChange` is invoked.

## Appearance

- **Corner radius**: Not applicable — neither `IntegerFieldView` nor
  `NumberFieldView` sets a layer or draws a custom shape; both are plain
  `NSView` subclasses composing stock `NSTextField`s.
- **Padding**: `NumberFieldView`'s `makeRow([label, textField])` inserts a
  flexible spacer between them, sets the `NSStackView`'s `spacing` to
  `SettingsLayout.default[.rowSpacing]` = 8pt (applied to the
  label→spacer gap), and zeroes the spacer→`textField` gap
  (`setCustomSpacing(0, after: spacer)`) — the same row shape and spacing
  math `CheckboxView` and `CaptionedSliderView` use.
  `IntegerFieldView.pinToEdges(field, of: self)` adds 0pt of outer padding
  of its own; `NumberFieldView`'s own edge-pinning (`pinToEdges`, or the
  content-width variant when `labelWidth` is set) likewise adds nothing
  beyond that internal 8pt/0pt spacing.
- **Font**: `label` uses `ComposableSettings.makeRowLabel`'s `textRole:
  .button`, resolving to `ThemeTypography.defaultStyle(.button)`: 13pt,
  medium weight, proportional system font, scaled by the active theme's
  `sizeScale`. `textField` uses `palette.font(.code)`, resolving to
  `ThemeTypography.defaultStyle(.code)`: 12pt, regular weight, the system
  monospaced font, also scaled by `sizeScale` — chosen so a changing value
  doesn't reflow the field.
- **Background**: `label` — none (transparent); `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, `isBezeled = false`.
  `textField` — source never overrides `isBordered`, `isBezeled`, or
  `drawsBackground` on it; it stays a plain, default-initialized
  `NSTextField()`, which keeps AppKit's standard bezeled, opaque text-field
  background rather than being transparent like the label.
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength, repainted live via
  `ThemePaletteObserver`. `textField.textColor` is set directly to
  `palette.primaryTextColor` (the same `.primaryText` role, applied through
  `observeTheme` rather than through a `ThemedLabel`), also repainted live
  on every theme change.
- **Border**: `label` — none (`ThemedLabel` sets `isBordered = false`).
  `textField` — no border property is set in source, so it keeps
  `NSTextField()`'s default bezel (`bezelStyle` defaults to
  `.squareBezel`), drawn by AppKit rather than by this component.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `IntegerFieldView.swift` or `NumberFieldView.swift`.
- **Min/Max size**: `textField.widthAnchor` is fixed to the constant
  `fieldWidth` (52pt via `IntegerFieldView`'s own default; `NumberFieldView`'s
  own uncalled default is 72pt — see Design Decisions). No height
  constraint is set on either `label` or `textField`; height comes from
  each control's intrinsic content size within the row.

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `textField` shows the current value's `settingsFieldString`, right-aligned, in the code-role monospaced font. |
| Editing | The user's typed text is shown verbatim in `textField.stringValue` while focused; no `NSFormatter` is attached (deliberate — see Design Decisions), so intermediate/partial text (e.g. a leading `-`) is not rejected mid-edit. |
| Committed — valid | On `Return`/`Tab`/click-away (`controlTextDidEndEditing`) or on the field's own action firing, a parseable value is clamped (unless bounds are contradictory) and written back to `textField.stringValue` and `viewModel.settingObserver.value`. |
| Committed — invalid | An unparseable string reverts `textField.stringValue` and `label.stringValue` to the view model's current value/title; `viewModel.settingObserver.value` is left unchanged. |
| Pressed | Not applicable: neither file renders a button; there is no press/highlight state to define. |
| Disabled | Not implemented in source; `isEnabled` is never read or set on `label` or `textField`. A caller may set `textField.isEnabled` directly through the public `textField` property, at which point `NSTextField`'s native disabled dimming applies. |
| Focused | Not styled by this component; any focus ring shown when the field becomes first responder is `NSTextField`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |

## Accessibility

- **Role/trait**: Not set explicitly anywhere in source. `textField` keeps
  `NSTextField`'s default editable-text-field accessibility role; `label`
  keeps AppKit's default for a non-editable field (`ThemedLabel` sets
  `isEditable = false`) — a static-text element.
- **Label requirements**: Component MUST call
  `textField.setAccessibilityTitleUIElement(label)` — the same row pattern
  `CheckboxView` and its siblings use — so the field's accessible name
  comes from its adjacent visible label rather than a separate
  `accessibilityLabel` string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller
  (see States); a committed clamp or revert updates `textField.stringValue`
  directly, which `NSTextField`'s own accessibility value reporting picks
  up automatically, with no explicit announcement call in source.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/keyboard-driven `NSView`/`NSControl` composition with no touch
  input path in source; the 44×44pt guidance is iOS/touch-specific. No
  `controlSize` is set on `textField`, so it keeps `NSTextField`'s regular
  system metrics; its clickable width is the fixed `fieldWidth` (52pt
  default) set by **fixes-field-width**.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| integer-field-view-001 | wraps-number-field-view | Construct `IntegerFieldView(viewModel:)` with `viewModel.minValue = 0`, `viewModel.maxValue = 10` | The private `NumberFieldView<Int>` is constructed with `minimum == 0` and `maximum == 10` |
| integer-field-view-002 | exposes-constituent-views | Construct `IntegerFieldView` with any `viewModel` | `.label` and `.textField` are accessible from outside the type and are the same instances the wrapped `NumberFieldView` built |
| integer-field-view-003 | arranges-single-child | Construct `IntegerFieldView` with any `viewModel` | The wrapped `NumberFieldView` is the only subview, pinned to `IntegerFieldView`'s top/leading/trailing/bottom with no additional constant |
| integer-field-view-004 | forwards-editing-end-to-wrapped-field | Set `textField.delegate` to the `IntegerFieldView` instance itself, type a valid number, then trigger `controlTextDidEndEditing` | The wrapped `NumberFieldView.commit()` runs and the new value is stored |
| integer-field-view-005 | defaults-field-width-to-52-points | Construct `IntegerFieldView(viewModel:)` with no `fieldWidth` argument | `textField.widthAnchor`'s constant is 52 |
| integer-field-view-006 | forwards-label-width | Construct `IntegerFieldView(viewModel:, labelWidth: 80)` | The wrapped field's `label.widthAnchor` constant is 80 and `label.alignment == .right` |
| integer-field-view-007 | requires-designated-initializer | Attempt `IntegerFieldView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| integer-field-view-008 | rejects-frame-only-initialization | Attempt `IntegerFieldView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| integer-field-view-009 | confines-to-main-actor | Attempt to construct or mutate an `IntegerFieldView` from off the main actor | Compiler rejects the call at compile time under `@MainActor` isolation checking |
| integer-field-view-010 | builds-label-from-view-model-title | `viewModel.title = "Left Margin"` | `label.stringValue == "Left Margin"` after construction |
| integer-field-view-011 | right-aligns-field-text | Construct with any `viewModel` | `textField.alignment == .right` |
| integer-field-view-012 | initializes-display-from-view-model | `viewModel.title = "Left Margin"`, `viewModel.value = 12` | After init, `label.stringValue == "Left Margin"` and `textField.stringValue == "12"` |
| integer-field-view-013 | wires-field-target-action | Any initialized field | `textField.target === field`; `textField.action == Selector("fieldChanged:")` |
| integer-field-view-014 | delegates-field-to-wrapped-view | Any initialized field | `textField.delegate === field` (the `NumberFieldView` instance), not the outer `IntegerFieldView` |
| integer-field-view-015 | links-field-accessibility-title | Construct with any `viewModel` | `textField`'s accessibility title UI element is `label` |
| integer-field-view-016 | themes-field-live | Construct the field, then post a theme change to a palette with a distinct `.code` font/`.primaryText` color | `textField.font` and `textField.textColor` update to match the new palette both immediately at construction and again after the change |
| integer-field-view-017 | fixes-field-width | Construct with `fieldWidth: 90` | `textField.widthAnchor`'s constant is 90 |
| integer-field-view-018 | aligns-label-when-width-fixed | Construct with `labelWidth: 100` | `label.alignment == .right` and `label.widthAnchor`'s constant is 100 |
| integer-field-view-019 | lays-out-content-width-row-when-label-fixed | Construct with `labelWidth: 100` | The row's top/leading/bottom are pinned to the container; its trailing constraint is `lessThanOrEqualTo` the container's trailing edge |
| integer-field-view-020 | lays-out-full-width-row-by-default | Construct with `labelWidth: nil` | The row is pinned to all four edges of the container |
| integer-field-view-021 | commits-on-field-action | Type `"7"` into `textField` and invoke `fieldChanged(textField)` directly | `viewModel.settingObserver.value == 7` after the call |
| integer-field-view-022 | commits-on-editing-end | Type `"7"` into `textField` and invoke `controlTextDidEndEditing` on the wrapped field | `viewModel.settingObserver.value == 7` after the call |
| integer-field-view-023 | parses-locale-aware-integer-text | With the current locale set to `de_DE`, set `textField.stringValue = "1.234"` (POSIX-parseable as `1` with trailing garbage is rejected; full-string decimal-locale parse reads it as `1234`) and commit | `viewModel.settingObserver.value == 1234` |
| integer-field-view-024 | reverts-on-unparseable-text | `viewModel.settingObserver.value = 5`; set `textField.stringValue = "abc"` and commit | `viewModel.settingObserver.value` remains `5`; `textField.stringValue` is reset to `"5"` |
| integer-field-view-025 | clamps-to-bounds | `minimum = 0`, `maximum = 10`; set `textField.stringValue = "99"` and commit | `viewModel.settingObserver.value == 10`; `textField.stringValue == "10"` |
| integer-field-view-026 | skips-clamp-on-contradictory-bounds | `minimum = 10`, `maximum = 1`; set `textField.stringValue = "37"` and commit | `viewModel.settingObserver.value == 37` (stored unclamped) |
| integer-field-view-027 | redisplays-committed-text | `minimum = 0`, `maximum = 10`; set `textField.stringValue = "99"` and commit | `textField.stringValue` changes from `"99"` to `"10"` |
| integer-field-view-028 | skips-redundant-commits | `viewModel.settingObserver.value = 5`; set `textField.stringValue = "5"` (same value) and commit | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| integer-field-view-029 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `textField.stringValue` both update to reflect the new view-model state |

## Edge Cases

- **Null/empty input**: `viewModel` (`RangeViewModel<Int>`) is a
  non-optional, typed constructor parameter; Swift's type system rules out
  `nil`. An empty `textField.stringValue` fails the `Int(settingsFieldString:)`
  parse (a trimmed empty string fails both the POSIX and the locale-aware
  parse), so `commit()` takes the revert path
  (**reverts-on-unparseable-text**) rather than storing `0`. MUST.
- **Boundary values**: A typed value exactly equal to `minimum` or
  `maximum` commits unclamped (the clamp is a no-op at the boundary). A
  value one below `minimum` clamps up to `minimum`; one above `maximum`
  clamps down to `maximum`. When `minimum` and `maximum` are both set and
  `minimum > maximum`, clamping is skipped entirely and the raw typed
  value is stored (**skips-clamp-on-contradictory-bounds**) — a caller
  configuration error, not a range this component enforces. MUST.
- **Out-of-range magnitude**: A typed value whose magnitude exceeds what
  `Int` can hold exactly — per `Int.settingsExactInt(from:)`'s
  `Decimal`-based check, which catches the case `NSNumber.int64Value` would
  otherwise silently saturate — is treated as unparseable and reverts
  rather than storing a clamped `Int.max`/`Int.min`. MUST.
- **Fractional and locale-formatted text**: A fractional string (`"1.5"`,
  or `"1,5"` in a comma-decimal locale) is rejected outright —
  `Int.settingsAllowsFloats` is `false`, so the locale `NumberFormatter`
  refuses it, and the whole-string-consumed check refuses a partial parse
  like the leading `"1"` of `"1,5"`. An integral-valued fractional spelling
  (`"1.0"`) is refused for the same reason. Text using the process
  locale's own decimal grammar parses via the locale-aware branch once the
  POSIX parse fails. MUST.
- **Concurrent access**: Not applicable — both `IntegerFieldView` and
  `NumberFieldView` are declared `@MainActor`, so all construction and
  mutation is serialized to the main actor by the compiler (see
  **confines-to-main-actor**).
- **Error states**: Not applicable — every operation in both files
  (parsing, clamping, the `settingObserver.value` write) is synchronous and
  non-throwing; no `try`, `Result`, or error-producing API appears in
  source.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking; it only reads from and writes to an in-process view
  model.
- **Overwritten external observer**: `viewModel.onChange` is a single
  closure property. `NumberFieldView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.sync() }`, replacing
  whatever handler (if any) was previously registered on that view model —
  the same closure-overwrite behavior `CheckboxView` and
  `CaptionedSliderView` document. The component MUST NOT be assumed to
  coexist with another `onChange` observer already registered on the same
  view model instance.
- **Delegate reassignment**: Because `textField.delegate` is set to the
  `NumberFieldView` instance, not `IntegerFieldView`, a caller that
  reassigns `textField.delegate` to something else silently disables
  `commit()`-on-editing-end; `IntegerFieldView.controlTextDidEndEditing(_:)`
  only fires if a caller explicitly re-points `textField.delegate` back at
  the outer `IntegerFieldView` (see Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.RangeViewModel<Int>` | — (required) | Supplies the row's title and min/max/current integer value; receives committed field changes via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the wrapped field's own sync handler (see Edge Cases). |
| `fieldWidth` | `CGFloat` | `52` | Width of the number field, in points. Differs from `NumberFieldView`'s own uncalled default of `72` — see Design Decisions. |
| `labelWidth` | `CGFloat?` | `nil` | When set, pins `label` to a fixed, right-aligned width so a column of rows lines up; when `nil`, the row spans the container's full width. |

## Deep Linking

Not applicable: `IntegerFieldView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `IntegerFieldView.swift` or `NumberFieldView.swift`.

## Localization

Not applicable: neither source file contains a user-facing string literal
of its own. The row's title comes entirely from `viewModel.title`, a value
the caller provides, so there is nothing for this component to localize
itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears in either file; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: neither file sets a custom `NSColor` outside the theme's `.primaryText` role; `NSTextField`'s own default border/bezel rendering already tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — valid, invalid, and clamped values are communicated entirely through the displayed digits; an invalid entry reverts silently with no color-only error indicator in source. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `IntegerFieldView.swift` or `NumberFieldView.swift`; the row always
renders once constructed.

## Analytics

Not applicable: neither source file contains an analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by `viewModel` and reports
  committed edits back through `viewModel.settingObserver`.
- **Storage**: Not applicable — neither `IntegerFieldView.swift` nor
  `NumberFieldView.swift` reads or writes `UserDefaults`, the keychain, or
  any other store directly. Persistence is owned by
  `RangeViewModel<Int>`/`UserSettingObserver`/`UserSetting`, which are not
  part of these files; by default that chain routes through
  `UserDefaultsSettingsStorageProvider`, so a committed value survives an
  app restart, but that guarantee lives outside this component.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `textField`, the wrapped `field`) and its reference to
  `viewModel` for its own lifetime; it persists nothing itself beyond
  that.

## Logging

Not applicable: neither source file contains a logging call (no `print`,
`os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: `TextField("", value: $intValue, format: .number)` (or a
  `String`-backed `TextField` with a manual parse/format pair, to reproduce
  the POSIX-write/locale-read asymmetry) inside an `HStack` with a leading
  `Text(viewModel.title)`, giving the field a fixed `.frame(width:)`
  matching `fieldWidth` and `.font(.system(.body, design: .monospaced))`
  for the code-role font. Commit and clamp from the `Binding`'s setter (or
  `.onSubmit`) rather than on every keystroke, mirroring
  commits-on-editing-end and reverts-on-unparseable-text; SwiftUI's own
  `FocusState` change is the analog of `controlTextDidEndEditing`.
- **Compose**: `OutlinedTextField`/`BasicTextField` with
  `keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)`,
  a leading `Text(title)`, and a `Modifier.width(...)` matching
  `fieldWidth`. Keep `onValueChange` parsing against a `String` buffer only
  (coercing to `Int` on every keystroke would fight a user mid-edit, the
  same problem the source's no-formatter comment describes), and
  commit/clamp when focus is lost (`Modifier.onFocusChanged`), mirroring
  commits-on-editing-end.
- **React/Web**: `<input type="text" inputMode="numeric" pattern="-?[0-9]*">`
  (not `type="number"`, whose native spinner and silent-empty-on-invalid
  behavior diverges from the source's explicit revert-on-invalid path)
  paired with a `<label>` wired via `aria-labelledby`/`htmlFor`, the web
  analog of `setAccessibilityTitleUIElement`. Parse and clamp on
  `blur`/`Enter` (mirroring commits-on-editing-end and
  commits-on-field-action), reverting the displayed text on a parse
  failure rather than accepting it.
- **AppKit/UIKit** (source platform): Source files
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/IntegerFieldView.swift`
  and `.../Views/NumberFieldView.swift`. Both are macOS-only (`import
  AppKit`) `NSView` subclasses, `@MainActor`, inside the
  `ComposableSettings` namespace. `IntegerFieldView` composes and forwards
  entirely to a private `NumberFieldView<Int>`, which performs the actual
  layout (`makeRow`/`pinToEdges`), theming (`observeTheme`), and
  parsing/clamping/commit work described above. There is no UIKit code
  path in source; a UIKit port would replace `NSTextField` with
  `UITextField` (`keyboardType = .numbersAndPunctuation` to allow a
  leading `-`), replace target/action with
  `.addTarget(_:action:for: .editingDidEnd)`, and reimplement the generic
  `SettingsNumberValue`-driven parse/clamp/revert logic against
  `UITextField.text` — UIKit has no `NSCoder`-vs-frame initializer split to
  fatal-error on the way requires-designated-initializer and
  rejects-frame-only-initialization do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto` (the same shape the boolean-row recipe
  uses): a `TextBlock` for the title in column 0, and a `NumberBox` —
  WinUI's purpose-built numeric field — in column 1, in place of a raw
  `TextBox`. `NumberBox` already exposes `Minimum`/`Maximum` properties
  that map directly to this component's `minimum`/`maximum`, and setting
  `SpinButtonPlacementMode="Collapsed"` keeps it visually a bare field
  rather than a stepper, matching this source's "a slider/stepper is the
  wrong control" rationale. Set `NumberBox.ValidationMode="InvalidInputOverwritten"`
  to reproduce reverts-on-unparseable-text (WinUI overwrites the box with
  the last valid value on an invalid commit, the same behavior as this
  source's `sync()` revert), and handle the `ValueChanged` event to write
  the already-clamped, committed value into the bound setting with an
  equality guard before writing, mirroring skips-redundant-commits. Set
  `AutomationProperties.LabeledBy` on the `NumberBox` to the `TextBlock`,
  the WinUI analog of `setAccessibilityTitleUIElement`. Give `NumberBox` a
  fixed `Width` matching `fieldWidth` (52 by default here) rather than
  letting it stretch, since WinUI's `NumberBox` otherwise fills its
  column.

## Design Decisions

- Decision: Keep `IntegerFieldView` as a thin, forwarding wrapper around
  `NumberFieldView<Int>` rather than folding its logic in directly.
  Rationale: Per the source's own doc comment, "this name stays because it
  is public API of a framework other repos link: a bounded integer field
  is still exactly this call" — `NumberFieldView` generalizes to optional,
  one-sided bounds that `RangeViewModel` (which requires both) cannot
  express, so the behavior moved there while `IntegerFieldView` stayed as
  the compatible entry point.
  Approved: pending
- Decision: Default `fieldWidth` to 52pt in `IntegerFieldView`'s
  initializer, rather than reusing `NumberFieldView`'s own uncalled
  default of 72pt.
  Rationale: `IntegerFieldView` always passes an explicit `fieldWidth`
  argument to `NumberFieldView`'s initializer, so `NumberFieldView`'s 72pt
  default is never reached through this type; 52pt is `IntegerFieldView`'s
  own, narrower, pre-existing default, kept for source fidelity to callers
  that relied on it.
  Approved: pending
- Decision: Skip clamping entirely when `minimum` and `maximum` are both
  set and `minimum > maximum`, rather than clamping to one of them.
  Rationale: Per the source's own comment, "a contradictory pair comes
  from a caller's own mistake, and the field's job then is to stay usable,
  not to enforce an empty range" — whichever bound clamping would apply
  first is an arbitrary artifact of the code's line order, so the source
  instead leaves the field unbounded in that case.
  Approved: pending
- Decision: Revert silently to the last committed value on unparseable
  text, rather than storing a coerced or default value.
  Rationale: Per the source's own comment, "text that is not a number of
  this type is not a zero; it is a typo," and a silently-stored zero (or a
  rounded fraction) would be a value the user never typed.
  Approved: pending
- Decision: Attach no `NSFormatter` to `textField`.
  Rationale: Per the source's own comment, a formatter with a minimum
  would reject valid intermediate text on the way to a valid number (e.g.
  typing "-" before "-5", or the "1" of "12" against a minimum of 10);
  parsing happens only on commit instead.
  Approved: pending
- Decision: Parse POSIX-first, falling back to a locale-aware parse only
  when the POSIX parse fails.
  Rationale: Per the source's own comment on `SettingsNumberValue`, the
  field's own writer (`settingsFieldString`) is POSIX; a locale-first
  parse would misread the POSIX text `sync()` itself just wrote (e.g.
  reading `"1.5"`'s `.` as a German thousands separator and storing `15`),
  multiplying a value by ten on every locale-mismatched commit cycle.
  Approved: pending
- Decision: Reject a parsed value whose magnitude `Int64` would otherwise
  silently clamp, via a `Decimal`-based exactness check
  (`Int.settingsExactInt(from:)`), rather than accepting the clamped
  result.
  Rationale: Per the source's own comment, `NSNumber.int64Value` saturates
  rather than failing on overflow, and `Double(Int64.max)` rounds up to
  exactly 2^63 — indistinguishable from a true 2^63 input as a `Double` —
  so only the `Decimal` comparison can tell a genuinely-typed `Int.max`
  apart from an overflow that would otherwise be silently stored as
  `Int.max`.
  Approved: pending
- Decision: Keep `IntegerFieldView.controlTextDidEndEditing(_:)` even
  though `textField.delegate` is set to the wrapped `NumberFieldView`, not
  to `IntegerFieldView` itself.
  Rationale: Per the source's own comment, this method is "kept because it
  was public, and forwards for the same reason" — AppKit calls the inner
  view's delegate method in the normal case, but any external caller still
  holding a reference to `IntegerFieldView` as an `NSTextFieldDelegate`
  (as public API predating this refactor allowed) still reaches
  `commit()` through this forwarding method.
  Approved: pending
- Decision: This recipe carries roughly twice the behavioral-requirement
  count of sibling `ComposableSettings` row recipes (e.g. `CheckboxView`'s
  eleven).
  Rationale: `IntegerFieldView` delegates its entire visible and
  interactive behavior to `NumberFieldView<Int>`, whose locale-aware
  parsing, bounds clamping, revert-on-invalid, and dual commit triggers
  are each independently testable behaviors that a boolean toggle or a
  single-drag slider does not have. Documenting that delegated behavior
  here, rather than treating it as out of scope, follows this cookbook's
  own instruction to trace a called helper's behavior into the recipe.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
