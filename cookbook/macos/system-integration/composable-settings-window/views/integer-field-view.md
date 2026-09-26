---
id: a7653559-cb70-43db-a75c-d032e4f599b3
title: IntegerFieldView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/integer-field-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
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
- appkit
depends-on:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/checkbox-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/captioned-slider-view
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
locale-aware parse/clamp/commit logic. `IntegerFieldView` stays as public API
"because it is public API of a framework other repos link: a bounded integer
field is still exactly this call" (source comment).

The wrapped `NumberFieldView<Int>`'s own behavior — theming, target/action and
delegate wiring, layout when `labelWidth` is set, locale-aware parsing,
clamping, revert-on-invalid, and external-change sync — is documented in full
at `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view`, which this recipe depends on.
This recipe documents only what `IntegerFieldView` itself contributes:
constructing and forwarding to that wrapped view, exposing its constituent
views, and the initializer/actor requirements `IntegerFieldView` does not
inherit from it.

## Behavioral Requirements

The wrapped `NumberFieldView<Int>`'s own requirements — label/field
construction, theming, target/action and delegate wiring, `labelWidth`
layout, locale-aware parsing, clamping, revert-on-invalid, and
external-change sync — are documented at
`agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#requirements`. The requirements
below are `IntegerFieldView`'s own: what it does to construct, forward to,
and expose that wrapped view.

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
- **default-field-width**: Component's initializer MUST default
  `fieldWidth` to 52 points when the caller supplies none — narrower than
  the wrapped `NumberFieldView`'s own uncalled default of 72 points (see
  Design Decisions) — and MUST pass that value through to the wrapped
  `NumberFieldView`'s own `fieldWidth` parameter.
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
  default here, per **default-field-width**), constrained onto the wrapped
  field's `textField.widthAnchor` by the wrapped `NumberFieldView`'s own
  `fixes-field-width` requirement (see
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#requirements/fixes-field-width`).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| integer-field-view-001 | wraps-number-field-view | Construct `IntegerFieldView(viewModel:)` with `viewModel.minValue = 0`, `viewModel.maxValue = 10`; set `textField.stringValue = "99"`, then trigger the field's target-action (`NSApplication.shared.sendAction(textField.action!, to: textField.target, from: textField)`) | `textField.stringValue` becomes `"10"` — the clamp visible on the public `textField` shows `viewModel.minValue`/`viewModel.maxValue` reached the wrapped field's `minimum`/`maximum` bounds |
| integer-field-view-002 | exposes-constituent-views | Construct `IntegerFieldView` with any `viewModel` | `.label` and `.textField` are accessible from outside the type and are the same instances the wrapped `NumberFieldView` built |
| integer-field-view-003 | arranges-single-child | Construct `IntegerFieldView` with any `viewModel`, add it to a laid-out view hierarchy of a known size | The public `label` and `textField` together occupy the full bounds of `IntegerFieldView` with no additional outer inset: `label`'s frame `minX` equals `IntegerFieldView`'s `minX`, and `textField`'s frame `maxX` equals `IntegerFieldView`'s `maxX` |
| integer-field-view-004 | forwards-editing-end-to-wrapped-field | Set `textField.delegate` to the `IntegerFieldView` instance itself, type a valid number, then trigger `controlTextDidEndEditing` | The wrapped `NumberFieldView.commit()` runs and the new value is stored |
| integer-field-view-005 | default-field-width | Construct `IntegerFieldView(viewModel:)` with no `fieldWidth` argument | `textField.widthAnchor`'s constant is 52 |
| integer-field-view-006 | forwards-label-width | Construct `IntegerFieldView(viewModel:, labelWidth: 80)` | The wrapped field's `label.widthAnchor` constant is 80 and `label.alignment == .right` |
| integer-field-view-007 | requires-designated-initializer | Attempt `IntegerFieldView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| integer-field-view-008 | rejects-frame-only-initialization | Attempt `IntegerFieldView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| integer-field-view-009 | confines-to-main-actor | Attempt to construct or mutate an `IntegerFieldView` from off the main actor | Compiler rejects the call at compile time under `@MainActor` isolation checking |

## Edge Cases

- **Null/empty input**: `viewModel` (`RangeViewModel<Int>`) is a
  non-optional, typed constructor parameter; Swift's type system rules out
  `nil`. The wrapped field's own revert-on-empty-text behavior — an empty
  `textField.stringValue` fails the parse the same as any other unparseable
  text — is documented at
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#edge-cases`.
- **Boundary values**: Clamping at `minimum`/`maximum`, and skipping the
  clamp when `minimum > maximum`, is entirely the wrapped
  `NumberFieldView<Int>`'s behavior; see
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#edge-cases`. `IntegerFieldView`
  only supplies those bounds, via `viewModel.minValue`/`viewModel.maxValue`
  (**wraps-number-field-view**).
- **Out-of-range magnitude and fractional/locale-formatted text**: Parsing
  — POSIX-first with a locale-aware fallback, magnitude-exactness rejection,
  and fractional rejection — is entirely the wrapped `NumberFieldView<Int>`'s
  behavior; see `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#edge-cases`.
- **Concurrent access**: Not applicable — `IntegerFieldView` is declared
  `@MainActor` (**confines-to-main-actor**), so all construction and
  mutation is serialized to the main actor by the compiler. The wrapped
  `NumberFieldView<Int>` carries the same isolation independently; see
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#edge-cases`.
- **Error states**: Not applicable — every operation in
  `IntegerFieldView.swift` (construction, forwarding, and
  `controlTextDidEndEditing`) is synchronous and non-throwing; no `try`,
  `Result`, or error-producing API appears in this file.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking; it only forwards to the wrapped `NumberFieldView<Int>`,
  which itself only reads from and writes to an in-process view model.
- **Overwritten external observer**: This is entirely the wrapped
  `NumberFieldView<Int>`'s behavior — its initializer, not
  `IntegerFieldView`'s, unconditionally assigns `viewModel.onChange`; see
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#edge-cases`.
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
- **WinUI 3**: Build the row as a `Grid` with column definitions `*,Auto`
  (the same shape the boolean-row recipe uses): a `TextBlock` for the title
  in column 0, and a `NumberBox` — WinUI's purpose-built numeric field — in
  column 1, in place of a raw `TextBox`. `NumberBox` already exposes
  `Minimum`/`Maximum` properties that map directly to this component's
  `minimum`/`maximum`, and setting `SpinButtonPlacementMode="Collapsed"`
  keeps it visually a bare field rather than a stepper, matching this
  source's "a slider/stepper is the wrong control" rationale. Set
  `NumberBox.ValidationMode="InvalidInputOverwritten"` to reproduce
  reverts-on-unparseable-text (WinUI overwrites the box with the last valid
  value on an invalid commit, the same behavior as this source's `sync()`
  revert), and handle the `ValueChanged` event to write the already-clamped,
  committed value into the bound setting with an equality guard before
  writing, mirroring skips-redundant-commits. Set
  `AutomationProperties.LabeledBy` on the `NumberBox` to the `TextBlock`,
  the WinUI analog of `setAccessibilityTitleUIElement`. Give `NumberBox` a
  fixed `Width` matching `fieldWidth` (52 by default here) rather than
  letting it stretch, since WinUI's `NumberBox` otherwise fills its column.
  Two divergences `NumberBox` does not close: it has no POSIX-first parse —
  its own locale-aware `NumberFormatter`-equivalent parsing has no fallback
  ordering to reproduce this source's
  parses-locale-aware-integer-text/POSIX-first behavior (see
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#requirements/parses-posix-integer-first`),
  so a value written by this source's POSIX `settingsFieldString` can read
  differently under a non-en-US Windows locale; and `NumberBox.Minimum`/
  `Maximum`, when both set with `Minimum > Maximum`, has no documented
  skip-the-clamp behavior matching
  skips-clamp-on-contradictory-bounds (see
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view#requirements/skips-clamp-on-contradictory-bounds`)
  — a WinUI port needs an explicit `Minimum > Maximum` check before relying
  on `NumberBox`'s own clamping.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/IntegerFieldView.swift` |

## Design Decisions

- **Decision**: Keep `IntegerFieldView` as a thin, forwarding wrapper
  around `NumberFieldView<Int>` rather than folding its logic in directly.
  **Rationale**: Per the source's own doc comment, "this name stays because
  it is public API of a framework other repos link: a bounded integer
  field is still exactly this call" — `NumberFieldView` generalizes to
  optional, one-sided bounds that `RangeViewModel` (which requires both)
  cannot express, so the behavior moved there (see
  `agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view`) while `IntegerFieldView`
  stayed as the compatible entry point.
  **Approved**: pending
- **Decision**: Default `fieldWidth` to 52pt in `IntegerFieldView`'s
  initializer, rather than reusing `NumberFieldView`'s own uncalled
  default of 72pt.
  **Rationale**: `IntegerFieldView` always passes an explicit `fieldWidth`
  argument to `NumberFieldView`'s initializer, so `NumberFieldView`'s 72pt
  default is never reached through this type; 52pt is `IntegerFieldView`'s
  own, narrower, pre-existing default, kept for source fidelity to callers
  that relied on it.
  **Approved**: pending
- **Decision**: Keep `IntegerFieldView.controlTextDidEndEditing(_:)` even
  though `textField.delegate` is set to the wrapped `NumberFieldView`, not
  to `IntegerFieldView` itself.
  **Rationale**: Per the source's own comment, this method is "kept because
  it was public, and forwards for the same reason" — AppKit calls the
  inner view's delegate method in the normal case, but any external caller
  still holding a reference to `IntegerFieldView` as an
  `NSTextFieldDelegate` (as public API predating this refactor allowed)
  still reaches `commit()` through this forwarding method.
  **Approved**: pending

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
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: move NumberFieldView<Int>'s own requirements, test vectors, edge cases, and design decisions out to the number-field-view recipe and cite it via depends-on/related, keeping only IntegerFieldView's own forwarding requirements; rewrite the wraps-number-field-view and arranges-single-child test vectors to assert observable outcomes (clamp visible on textField, label/textField frames) instead of the private wrapped view's internals; rename defaults-field-width-to-52-points to default-field-width and move the 52pt value into the requirement body; drop the redundant macos tag and backfill related with sibling recipe domains; reformat Design Decisions to the **Decision**/**Rationale**/**Approved** form and drop the now-inaccurate requirement-count decision; state NumberBox's POSIX-parsing and contradictory-bounds divergences in the WinUI 3 note and drop its "(the reason this recipe exists)" aside; remap Compliance citations to the catalog; backfill the missing 1.0.0 Change History row; fix the Accessibility section's dangling citation to the now-external fixes-field-width requirement |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
