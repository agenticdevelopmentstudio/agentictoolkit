---
id: acd561ca-90a4-4303-a411-cfe23410b42a
title: Number Field View
domain: agentictoolkit://cookbook/ui/settings/rows/number-field-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row generic over a number value contract — a title
  label paired with an optionally bounded, locale-aware number field.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
- numeric
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/integer-field-view
references: []
approved-by: ''
approved-date: ''
---

# Number Field View

## Overview

The Number Field View is the settings row underlying every numeric text
field in the framework: a title label leading and a narrow, right-aligned
number field trailing, parsed and clamped through a number value contract
rather than being tied to one numeric type. Optional (rather than required)
bounds are the whole reason this exists: every other numeric row is built on
a range view model that requires both, and most numeric settings a caller
declares name neither — a number with no ceiling is still a number, not a
text box. The concept also defines the number value contract itself — the
interface a number type implements so a field can display it, read it back,
and compare it — with two built-in conformances, integer and floating-point,
each supplying its own locale-aware parsing and canonical text form. The
Integer Field View (`agentictoolkit://cookbook/ui/settings/rows/integer-field-view`)
is a thin, forwarding wrapper around this component specialized for
integers; this recipe documents the field itself, including the parsing
contract that wrapper delegates to.

## Behavioral Requirements

- **builds-label-from-view-model-title**: Component MUST derive its label
  text from the view model's title.
- **right-aligns-field-text**: Component MUST right-align the field's text.
- **omits-input-formatter**: Component MUST NOT format or validate the
  field's text while the user is typing; parsing happens only on commit.
- **links-field-accessibility-title**: Component MUST associate the field's
  accessible name with its label, rather than a separate
  accessibility-label string.
- **themes-field-live**: Component MUST apply the code text role's font and
  the `.primaryText` color to the field, both immediately on construction
  and again every time the active theme changes.
- **fixes-field-width**: Component MUST constrain the field's width to the
  constant `fieldWidth` supplied at construction (default `72`).
- **aligns-label-when-width-fixed**: WHEN `labelWidth` is set, Component
  MUST right-align the label and pin its width to that constant.
- **lays-out-content-width-row-when-label-fixed**: WHEN `labelWidth` is
  set, Component MUST pin the row's top, leading, and bottom edges to the
  container and constrain the row's trailing edge to be no greater than the
  container's trailing edge.
- **lays-out-full-width-row-by-default**: WHEN `labelWidth` is not set,
  Component MUST pin the row to all four edges of the container instead of
  the content-width layout.
- **initializes-display-from-view-model**: At the end of initialization,
  Component MUST set the label's text to the view model's title and the
  field's text to the view model's value, in its field-string
  representation.
- **syncs-on-external-change**: Component's initializer MUST assign the
  view model's change-notification callback to one that re-sets the label
  and field text from the view model, and that callback MUST fire whenever
  the view model's change notification is invoked.
- **exposes-constituent-properties**: Component MUST expose the label, the
  field, `minimum`, and `maximum` as public, directly-accessible
  properties.
- **confines-to-ui-thread**: Component MUST be usable only from the UI
  thread.
- **commits-on-field-action**: Component MUST commit the field's text
  whenever the field's own change action fires.
- **commits-on-editing-end**: Component MUST commit the field's text
  whenever editing on it ends.
- **parses-committed-text-via-value-type**: Commit MUST parse the field's
  text via the number value contract's locale-aware parse operation for the
  field's declared value type.
- **reverts-on-unparseable-text**: WHEN commit cannot parse the field's
  text, it MUST leave the view model's value unchanged and MUST reset both
  the label and field text from the view model's current title/value.
- **clamps-to-bounds**: Unless **skips-clamp-on-contradictory-bounds**
  applies, commit MUST clamp a successfully parsed value up to `minimum`
  (if the value is lower) and then down to `maximum` (if the value is
  higher) before storing it.
- **skips-clamp-on-contradictory-bounds**: WHEN both `minimum` and
  `maximum` are set and `minimum` is greater than `maximum`, commit MUST
  store the parsed value unclamped.
- **redisplays-committed-text**: After computing the value to store, commit
  MUST set the field's text to that value's field-string representation
  whenever it differs from the field's current text.
- **skips-redundant-commits**: Commit MUST NOT write to the view model's
  value when the computed value equals its current value.
- **defines-number-parsing-contract**: The number value contract MUST
  declare a locale-aware parse operation that can fail, a field-string
  representation, and a flag indicating whether fractional values are
  allowed, and MUST itself support serialization, safe use across
  concurrent contexts, and ordering comparison.
- **provides-current-locale-parse**: The number value contract's default
  form MUST provide a parse operation that uses the active locale without
  requiring the caller to specify one.
- **requires-whole-string-locale-parse**: The shared locale-aware parse
  MUST use a decimal-style parser configured to allow or disallow
  fractional input per the type's float-allowance flag, and MUST reject the
  input unless the parser's consumed range covers the entire string.
- **trims-whitespace-before-parsing-int**: The integer conformance's parse
  operation MUST trim leading and trailing whitespace from the input before
  parsing.
- **parses-posix-integer-first**: The integer conformance's parse operation
  MUST accept a locale-invariant integer parse before attempting a
  locale-aware parse.
- **falls-back-to-locale-decimal-for-int**: WHEN the locale-invariant parse
  fails for an integer, the parse operation MUST attempt the locale-aware,
  whole-string decimal parse.
- **disallows-fractional-values-for-int**: The integer conformance's
  float-allowance flag MUST be false, so both the locale-invariant and
  locale-aware parse paths MUST reject any fractional spelling, including
  an integral-valued fractional spelling (e.g. `"1.0"`, `"1,0"`).
- **rejects-inexact-magnitude-for-int**: The locale-aware integer parse
  MUST reject a parsed number whose magnitude is not exactly representable
  as the integer type — via a finite, whole-number, exact-value check —
  rather than accepting a value a naive conversion would silently saturate.
- **writes-plain-integer-text**: The integer conformance's field-string
  representation MUST be a plain digit string, with no locale-specific
  grouping or decoration.
- **trims-whitespace-before-parsing-double**: The floating-point
  conformance's parse operation MUST trim leading and trailing whitespace
  from the input before parsing.
- **parses-posix-double-first**: The floating-point conformance's parse
  operation MUST accept a locale-invariant parse before attempting a
  locale-aware parse, but MUST reject a locale-invariant result that is not
  finite.
- **falls-back-to-locale-decimal-for-double**: WHEN the locale-invariant
  parse fails or is rejected for a floating-point value, the parse
  operation MUST attempt the locale-aware, whole-string decimal parse, and
  MUST reject a locale-aware result that is not finite.
- **allows-fractional-values-for-double**: The floating-point conformance's
  float-allowance flag MUST be true.
- **writes-whole-doubles-without-fraction**: The floating-point
  conformance's field-string representation MUST render a value equal to
  its own rounded value as an integer-looking string with no trailing
  fractional digits, and MUST fall back to the value's default decimal
  representation for any other value.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it composes stock text-field and label controls into a
  row.
- **Padding**: The row layout inserts a flexible spacer between the label
  and the field, sets the row's spacing to
  `SettingsLayout.default[.rowSpacing]` = 8pt (applied to the label→spacer
  gap), and zeroes the spacer→field gap — the same row shape and spacing
  math the checkbox row and the captioned slider row use. The row's own
  edge pinning (or the content-width variant used when `labelWidth` is set)
  adds 0pt of outer padding of its own beyond that internal 8pt/0pt
  spacing.
- **Font**: The label uses the button text role, resolving to 13pt, medium
  weight, proportional system font, scaled by the active theme's size
  scale. The field uses the code text role, resolving to 12pt, regular
  weight, the system monospaced font, also scaled by the size scale —
  chosen so a changing value doesn't reflow the field.
- **Background**: The label has none (transparent), drawing no background
  and no border of its own. The field is never given a transparent or
  borderless treatment; it keeps its platform's standard bezeled, opaque
  text-field background rather than being transparent like the label.
- **Foreground/Text**: The label resolves to the active theme's foreground
  color at full strength (the `.primaryText` role, unchanged from the
  theme's base foreground), repainted live whenever the theme changes. The
  field's text color is set directly to the same `.primaryText` role, also
  repainted live on every theme change.
- **Border**: The label has none. The field keeps its platform's default
  bezel/border rendering rather than one set by this component.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  this component.
- **Min/Max size**: The field's width is fixed to the constant `fieldWidth`
  (default `72`pt). The label's width is fixed only when `labelWidth` is
  supplied. No height constraint is set on either control; height comes
  from each control's intrinsic content size within the row.

## States

| State | Appearance change |
|-------|------------------|
| Default | The label shows the view model's title; the field shows the current value's field-string representation, right-aligned, in the code-role monospaced font. |
| Editing | The user's typed text is shown verbatim in the field while focused; no live input formatting or validation is attached (deliberate — see Design Decisions), so intermediate/partial text (e.g. a leading `-`) is not rejected mid-edit. |
| Committed — valid | On commit (editing ending, or the field's own change action firing), a parseable value is clamped (unless bounds are contradictory) and written back to the field and the view model. |
| Committed — invalid | An unparseable string reverts the field and label text to the view model's current value/title; the view model's value is left unchanged. |
| Pressed | Not applicable: the component renders no button; there is no press/highlight state to define. |
| Disabled | Not implemented in source; the enabled state is never read or set on either control. A caller may set the field's enabled state directly, at which point the platform's native disabled dimming applies. |
| Focused | Not styled by this component; any focus indication shown when the field becomes focused is the field's own native focus appearance. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator. |

## Accessibility

- **Role/trait**: Not set explicitly anywhere in source. The field keeps
  its platform's default editable-text-field accessibility role; the label
  keeps the platform default for a non-editable field — a static-text
  element.
- **Label requirements**: Component MUST associate the field's accessible
  name with its label — the same row pattern the checkbox row and its
  siblings use — so the field's accessible name comes from its adjacent
  visible label rather than a separate accessibility-label string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller
  (see States); a committed clamp or revert updates the field's text
  directly, which the field's own accessibility value reporting picks up
  automatically, with no explicit announcement call in source.
- **Minimum tap target**: Not applicable — this is a pointer/keyboard-driven
  control composition with no touch input path in source; the 44×44pt
  guidance is touch-specific. The field keeps its platform's regular
  control metrics; its clickable width is the fixed `fieldWidth` (72pt
  default) set by **fixes-field-width**.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The
  label and field text colors resolve from the active theme's
  `.primaryText` role against the hosting background at runtime, and the
  component performs no contrast check, so whether a given theme's resolved
  pair meets 4.5:1 cannot be determined from this file; settling it needs a
  theme-level contrast audit of `.primaryText` against the settings-row
  backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| number-field-view-001 | builds-label-from-view-model-title | View model's title = `"Left Margin"` | Label text == `"Left Margin"` after construction |
| number-field-view-002 | right-aligns-field-text | Construct the field with any view model | The field's text is right-aligned |
| number-field-view-003 | omits-input-formatter | Construct the component | No input formatter/validator is attached to the field |
| number-field-view-006 | links-field-accessibility-title | Construct the component | The field's accessible name is associated with the label |
| number-field-view-007 | themes-field-live | Construct the field, then switch the active theme to one whose palette has a distinct code font/`.primaryText` color | The field's font and text color update to match the new palette, both immediately at construction and again after the change |
| number-field-view-008 | fixes-field-width | Construct with `fieldWidth: 90` | The field's width is 90 |
| number-field-view-009 | aligns-label-when-width-fixed | Construct with `labelWidth: 100` | The label is right-aligned and its width is 100 |
| number-field-view-010 | lays-out-content-width-row-when-label-fixed | Construct with `labelWidth: 100` | The row's top/leading/bottom are pinned to the container; its trailing edge is constrained to be no greater than the container's trailing edge |
| number-field-view-011 | lays-out-full-width-row-by-default | Construct with `labelWidth: none` | The row is pinned to all four edges of the container |
| number-field-view-012 | initializes-display-from-view-model | View model's title = `"Left Margin"`, value = `12` | After init, label text == `"Left Margin"` and field text == `"12"` |
| number-field-view-013 | syncs-on-external-change | After construction, externally change the view model's title and value, then invoke its change-notification callback | The label and field text both update to reflect the new view-model state |
| number-field-view-014 | exposes-constituent-properties | Construct the component with `minimum: 0, maximum: 10` | The label, field, `minimum` (0), and `maximum` (10) are all accessible from outside the component |
| number-field-view-017 | confines-to-ui-thread | Attempt to construct or mutate the component from a thread other than the UI thread | The platform rejects or prevents the attempt (statically or at runtime, depending on platform — see Platform Notes) |
| number-field-view-018 | commits-on-field-action | Type `"7"` into the field and trigger its change action directly | The view model's value == 7 after the call |
| number-field-view-019 | commits-on-editing-end | Type `"7"` into the field and end editing | The view model's value == 7 after the call |
| number-field-view-020 | parses-committed-text-via-value-type | Field text = `"42"`, then commit | The view model's value == 42 |
| number-field-view-021 | reverts-on-unparseable-text | View model's value = 5; set field text = `"abc"` and commit | The view model's value remains 5; the field text is reset to `"5"` |
| number-field-view-022 | clamps-to-bounds | `minimum = 0`, `maximum = 10`; set field text = `"99"` and commit | The view model's value == 10; the field text == `"10"` |
| number-field-view-023 | skips-clamp-on-contradictory-bounds | `minimum = 10`, `maximum = 1`; set field text = `"37"` and commit | The view model's value == 37 (stored unclamped) |
| number-field-view-024 | redisplays-committed-text | `minimum = 0`, `maximum = 10`; set field text = `"99"` and commit | The field text changes from `"99"` to `"10"` |
| number-field-view-025 | skips-redundant-commits | View model's value = 5; set field text = `"5"` (same value) and commit | The view model's value is not written a second time (e.g. no additional write/observer notification is recorded) |
| number-field-view-026 | defines-number-parsing-contract | Declare a type conforming to the number value contract that omits the float-allowance flag or the locale-aware parse operation | The declaration does not satisfy the contract, and is rejected wherever the platform enforces it (e.g. at compile time) |
| number-field-view-027 | provides-current-locale-parse | With the active locale set to German (`de_DE`), parse the text `"1.234"` as an integer with no locale argument | Returns `1234` — a result only produced under a German (thousands-grouped) locale reading, showing the omitted-locale form used the active locale rather than, say, `en_US` (under which the same call returns nothing) |
| number-field-view-028 | requires-whole-string-locale-parse | With locale `en_US` and the integer conformance's float-allowance flag false, parse the text `"12abc"` as an integer | Returns nothing (the parser consumes only `"12"`, leaving the range short of the whole string) |
| number-field-view-029 | trims-whitespace-before-parsing-int | Parse the text `" 12 "` as an integer | Returns `12` |
| number-field-view-030 | parses-posix-integer-first | Parse the text `"12"` as an integer with locale `de_DE` | Returns `12` |
| number-field-view-031 | falls-back-to-locale-decimal-for-int | With locale `de_DE`, parse the text `"1.234"` as an integer | The locale-invariant parse of `"1.234"` fails (not a valid integer literal because it contains a decimal point), the locale-aware branch reads it as German thousands-grouped `1234`, and the parse returns `1234` |
| number-field-view-032 | disallows-fractional-values-for-int | Parse the text `"1.0"` and `"1,5"` as integers with locale `de_DE` | Both return nothing |
| number-field-view-033 | rejects-inexact-magnitude-for-int | Parse the text `"99999999999999999999999999"` as an integer | Returns nothing rather than a saturated maximum integer value |
| number-field-view-034 | writes-plain-integer-text | Render the integer `1234` as field text | Returns `"1234"`, with no grouping separators |
| number-field-view-035 | trims-whitespace-before-parsing-double | Parse the text `" 1.5 "` as a floating-point value | Returns `1.5` |
| number-field-view-036 | parses-posix-double-first | Parse the text `"nan"` as a floating-point value | The locale-invariant parse succeeds syntactically but the result is not finite, so the parse returns nothing rather than a NaN value |
| number-field-view-037 | falls-back-to-locale-decimal-for-double | With locale `de_DE`, parse the text `"1,5"` as a floating-point value | The locale-invariant parse of `"1,5"` fails, the locale-aware branch reads it as `1.5`, and the parse returns `1.5` |
| number-field-view-038 | allows-fractional-values-for-double | Parse the text `"1.5"` as a floating-point value | Returns `1.5` |
| number-field-view-039 | writes-whole-doubles-without-fraction | Render the floating-point values `20.0` and `20.5` as field text | Return `"20"` and `"20.5"` respectively |

## Edge Cases

- **Null/empty input**: The view model is a required, non-optional
  constructor parameter, so a missing view model is not possible. Empty
  field text fails the parse for both conformances (a trimmed empty string
  fails both the locale-invariant and the locale-aware parse), so commit
  takes the revert path (**reverts-on-unparseable-text**) rather than
  storing zero.
- **Boundary values**: A typed value exactly equal to `minimum` or
  `maximum` commits unclamped (the clamp is a no-op at the boundary). A
  value one below `minimum` clamps up to `minimum`; one above `maximum`
  clamps down to `maximum`. When `minimum` and `maximum` are both set and
  `minimum > maximum`, clamping is skipped entirely and the raw typed value
  is stored (**skips-clamp-on-contradictory-bounds**) — a caller
  configuration error, not a range this component enforces.
- **Out-of-range magnitude (integer)**: A typed value whose magnitude
  exceeds what the integer type can hold exactly — per an exact-value check
  that catches the case a naive 64-bit conversion would otherwise silently
  saturate — is treated as unparseable and reverts rather than storing a
  clamped maximum/minimum value.
- **Non-finite values (floating-point)**: `"nan"`, `"inf"`, and `"-inf"`
  all parse syntactically as floating-point numbers, but the parse
  operation explicitly rejects a non-finite locale-invariant result and a
  non-finite locale-aware result, returning nothing rather than storing a
  NaN or infinite value that would make every bounds comparison in commit
  false.
- **Fractional and locale-formatted text (integer)**: A fractional string
  (`"1.5"`, or `"1,5"` in a comma-decimal locale) is rejected outright — the
  integer conformance's float-allowance flag is false, so the locale-aware
  parse refuses it, and the whole-string-consumed check refuses a partial
  parse like the leading `"1"` of `"1,5"`. An integral-valued fractional
  spelling (`"1.0"`) is refused for the same reason.
- **Whole-number round-trip stability (floating-point)**: A stored `20.0`
  renders as `"20"` (**writes-whole-doubles-without-fraction**) rather than
  `"20.0"`, so a field showing a value the caller never edited does not
  visibly rewrite it into a longer, decorated form.
- **Concurrent access**: The number value contract's parsing/formatting
  operations are synchronous, pure value-type code with no shared mutable
  state; only the component itself is confined to a single execution
  context (see **confines-to-ui-thread**), so all construction and
  mutation of the component is serialized to that context even though the
  parsing/formatting code it calls is not itself confined.
- **Error states**: Not applicable — every operation in this component
  (parsing, clamping, the committed write) is synchronous and
  non-throwing; the one internal parse step that can fail is caught locally
  and converted to a "no result" outcome, never propagated. No error
  reaches the caller.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking; it only reads from and writes to an in-process view model.
- **Overwritten external observer**: The view model's change-notification
  callback is a single property. The initializer unconditionally replaces
  it with the component's own sync handler, replacing whatever handler (if
  any) was previously registered on that view model — the same
  closure-overwrite behavior the checkbox row and the captioned slider row
  document. The component MUST NOT be assumed to coexist with another
  change-notification observer already registered on the same view model
  instance.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | view model | — (required) | Supplies the row's title and current value; receives committed field changes. The initializer overwrites this view model's change-notification callback with the component's own sync handler (see Edge Cases). |
| `minimum` | number (same type as the field) or none | none | The lowest value the field will store. No minimum clamps nothing at the bottom. |
| `maximum` | number (same type as the field) or none | none | The highest value the field will store. No maximum clamps nothing at the top. |
| `fieldWidth` | number (points) | `72` | Width of the number field, in points. |
| `labelWidth` | number (points) or none | none | When set, pins the label to a fixed, right-aligned width so a column of rows lines up; when not set, the row spans the container's full width. |

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
applies.

## Localization

Not applicable: the component defines no user-facing string literals of its
own. The row's title comes entirely from the view model's title, a value
the caller provides, so there is nothing for this component to localize
itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation or transition is used anywhere in this component; every state change (init, sync, commit) is an instantaneous update. |
| Increase Contrast | Not applicable: the component sets no custom color outside the theme's `.primaryText` role; the field's native default border/bezel rendering already tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — valid, invalid, and clamped values are communicated entirely through the displayed digits; an invalid entry reverts silently with no color-only error indicator. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component; the row always renders once constructed.

## Analytics

Not applicable: this component reports no analytics or telemetry.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by the view model and reports
  committed edits back through it.
- **Storage**: Not applicable — this component never reads or writes any
  persistent store directly. Persistence is owned by the view model layer,
  which is not part of this component.
- **Transmission**: Not applicable — no networking call is made anywhere in
  this component.
- **Retention**: Not applicable — the component retains only its own
  subviews (label, field) and its reference to the view model for its own
  lifetime; it persists nothing itself beyond that.

## Logging

Not applicable: this component performs no logging (no print, log, or
logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: `TextField("", value: $numericValue, format: .number)` (or a
  `String`-backed `TextField` with a manual parse/format pair, to reproduce
  the locale-invariant-write/locale-aware-read asymmetry) inside an
  `HStack` with a leading `Text(viewModel.title)`, giving the field a fixed
  `.frame(width:)` matching `fieldWidth` and `.font(.system(.body, design:
  .monospaced))` for the code-role font. Commit and clamp from the
  `Binding`'s setter (or `.onSubmit`) rather than on every keystroke,
  mirroring commits-on-editing-end and reverts-on-unparseable-text;
  SwiftUI's own `FocusState` change is the analog of
  `controlTextDidEndEditing`.
- **Compose**: `OutlinedTextField`/`BasicTextField` with
  `keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)`, a
  leading `Text(title)`, and a `Modifier.width(...)` matching `fieldWidth`.
  Keep `onValueChange` parsing against a `String` buffer only (coercing to
  the numeric type on every keystroke would fight a user mid-edit, the same
  problem the source's no-formatter comment describes), and commit/clamp
  when focus is lost (`Modifier.onFocusChanged`), mirroring
  commits-on-editing-end.
- **React/Web**: `<input type="text" inputMode="decimal">` (not
  `type="number"`, whose native spinner and silent-empty-on-invalid behavior
  diverges from the source's explicit revert-on-invalid path, and no
  `pattern` attribute, which cannot express the source's locale-aware
  grammar — a locale-invariant-only pattern like `-?[0-9]*\.?[0-9]*` would
  reject comma-decimal locales and would also accept a fraction for the
  integer case) paired with a `<label>` wired via
  `aria-labelledby`/`htmlFor`, the web analog of
  `setAccessibilityTitleUIElement`. Parse and clamp on `blur`/`Enter`
  (mirroring commits-on-editing-end and commits-on-field-action), reverting
  the displayed text on a parse failure rather than accepting it, using the
  same two thin parse/format functions per type (rather than the `pattern`
  attribute) to police what each type accepts — the same generalization the
  number value contract gives the Swift source.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/NumberFieldView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, generic
  over `Value: SettingsNumberValue`, inside the `ComposableSettings`
  namespace, conforming to `SettingsViewProtocol` and
  `NSTextFieldDelegate`. It supports construction only through its
  designated initializer: both `init(coder:)` and the frame-only
  `init(frame:)` trigger a fatal error rather than producing an instance.
  It wires `textField.target`/`textField.action` to itself and
  `fieldChanged(_:)`, and sets `textField.delegate` to itself, so that a
  field action and `controlTextDidEndEditing(_:)` both drive `commit()`; it
  attaches no `NSFormatter`. The same file declares the
  `SettingsNumberValue` protocol and its `Int`/`Double` conformances, each
  supplying a POSIX-first, then locale-`NumberFormatter`-based parse and a
  canonical `settingsFieldString`. The locale-aware parse configures a
  `.decimal`-style `NumberFormatter` with `allowsFloats` set from
  `settingsAllowsFloats`, and requires the formatter's consumed range to
  cover the entire string. The `Int` conformance additionally rejects a
  parsed magnitude that is not exactly representable as `Int`, via
  `Int.settingsExactInt(from:)`'s finite/whole-number/`Decimal`-equality
  check — guarding against the silent saturation `NSNumber.int64Value`
  would otherwise perform on overflow, and against the false positive a
  `Double`-based magnitude check would produce at `Int64.max` (which rounds
  up to exactly 2^63 as a `Double`). There is no UIKit code path in source;
  a UIKit port would replace `NSTextField` with `UITextField`
  (`keyboardType = .numbersAndPunctuation` to allow a leading `-` and a
  decimal separator), replace target/action with
  `.addTarget(_:action:for: .editingDidEnd)`, and reimplement the generic
  `SettingsNumberValue`-driven parse/clamp/revert logic against
  `UITextField.text` — UIKit has no `NSCoder`-vs-frame initializer split to
  fatal-error on the way the source's designated-initializer-only
  construction rule does.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*` — a `TextBlock` for the title in column
  0, and a `NumberBox` — WinUI's purpose-built numeric field — in column 1,
  in place of a raw `TextBox`. Because `NumberBox.Value` is always a
  `double`, an integer-typed field (mirroring this recipe's `Int`
  conformance) MUST convert at the boundary with the same exactness check
  `Int.settingsExactInt(from:)` performs, rejecting (via
  `NumberBox.ValidationMode`/a `NumberBoxNumberFormatter` override) any
  value the round trip through `double` would not reproduce exactly; a
  floating-point-typed field maps directly. `NumberBox` already exposes
  `Minimum`/`Maximum` properties that map directly to this component's
  `minimum`/`maximum` when set; their own unset defaults are
  `double.MinValue`/`double.MaxValue` (not `NaN`), which already mirrors
  the no-clamp-at-that-end behavior of an unset bound with no extra
  sentinel needed. `NumberBox` has no equivalent of
  **skips-clamp-on-contradictory-bounds**, though: it documents no escape
  hatch for a caller-supplied `Minimum > Maximum`, so a port either
  validates that bounds are non-contradictory before setting them or
  accepts that `NumberBox`'s own (unspecified) behavior governs that case
  instead of this source's unclamped fallback — the two diverge there.
  `NumberBox` also parses its displayed text in the current culture only,
  with no locale-invariant-first fallback, so the round-trip guarantee
  behind this source's locale-invariant-first Design Decision (text this
  component itself wrote is guaranteed to read back correctly regardless of
  a later locale change) does not carry over automatically; a port that
  needs it must format and re-parse `NumberBox.Text` itself with the same
  locale-invariant-first-then-current-culture ordering rather than relying
  on `NumberBox`'s own culture-aware parsing. Setting
  `SpinButtonPlacementMode="Collapsed"` keeps it visually a bare field
  rather than a stepper. Set `NumberBox.ValidationMode=
  "InvalidInputOverwritten"` to reproduce reverts-on-unparseable-text
  (WinUI overwrites the box with the last valid value on an invalid commit,
  the same behavior as this source's `sync()` revert), and handle the
  `ValueChanged` event to write the already-clamped, committed value into
  the bound setting with an equality guard before writing, mirroring
  skips-redundant-commits. Set `AutomationProperties.LabeledBy` on the
  `NumberBox` to the `TextBlock`, the WinUI analog of
  `setAccessibilityTitleUIElement`. Give `NumberBox` a fixed `Width`
  matching `fieldWidth` (72 by default here) rather than letting it stretch
  to fill its column, the WinUI analog of fixes-field-width.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/NumberFieldView.swift` |

## Design Decisions

- **Decision**: Attach no live input formatter to the field, and parse only
  on commit (AppKit/UIKit source: no `NSFormatter`).
  **Rationale**: Per the source's own comment, a formatter with a minimum
  would reject valid intermediate text on the way to a valid number (e.g.
  typing "-" before "-5", or the "1" of "12" against a minimum of 10);
  parsing happens only on commit instead.
  **Approved**: pending
- **Decision**: Parse locale-invariant-first, falling back to a
  locale-aware parse only when the locale-invariant parse fails (or, for
  the floating-point conformance, produces a non-finite result).
  **Rationale**: Per the source's own comment on the number value contract,
  the field's own writer (its field-string representation) is
  locale-invariant; a locale-first parse risks misreading the
  locale-invariant text a sync just wrote as a locale-formatted number
  instead. The source itself notes this ordering is unobservable and
  deliberately untested for the integer conformance (its field-string
  representation emits no separators, so neither parse branch can see a
  string the other reads differently), while the floating-point
  conformance's ordering is pinned by a dedicated test, because its
  locale-invariant writer can emit a decimal point a locale-aware parse
  could misread.
  **Approved**: pending
- **Decision**: Skip clamping entirely when `minimum` and `maximum` are
  both set and `minimum > maximum`, rather than clamping to one of them.
  **Rationale**: Per the source's own comment, "a contradictory pair comes
  from a caller's own mistake, and the field's job then is to stay usable,
  not to enforce an empty range" — whichever bound clamping would apply
  first is an arbitrary artifact of the code's line order, so the source
  instead leaves the field unbounded in that case.
  **Approved**: pending
- **Decision**: Revert silently to the last committed value on unparseable
  text, rather than storing a coerced or default value.
  **Rationale**: Per the source's own comment, "text that is not a number of
  this type is not a zero; it is a typo," and a silently-stored zero (or a
  rounded fraction) would be a value the user never typed.
  **Approved**: pending
- **Decision**: Reject a parsed integer whose magnitude a naive 64-bit
  conversion would otherwise silently clamp, via an exact-value check
  (AppKit/UIKit source: `Int.settingsExactInt(from:)`), rather than
  accepting the clamped result.
  **Rationale**: Per the source's own comment, a naive 64-bit conversion
  saturates rather than failing on overflow, and converting to a
  double-precision float rounds up to a value indistinguishable from a true
  edge-of-range input, so only an exact (arbitrary-precision) comparison
  can tell a genuinely-typed maximum value apart from an overflow that
  would otherwise be silently stored as that maximum.
  **Approved**: pending
- **Decision**: Render a whole floating-point value without a trailing
  fraction (`20.0` → `"20"`) via a whole-number check, rather than always
  using the type's default decimal string form.
  **Rationale**: Per the source's own comment, the default decimal string
  form of `20.0` is `"20.0"`, and a field that turns the `20` a caller wrote
  into `20.0` the moment it is shown has edited a setting nobody touched.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference`, `platform-design-language`, `keyboard-navigable`,
`idempotent-operations`, and `separation-of-concerns` rest on the source's use
of a stock `NSTextField`'s own keyboard-and-focus behavior, its
skips-redundant-commits guard, and its single-responsibility split between the
generic view and the `SettingsNumberValue` parsing contract; `screen-reader-support`
is `partial` because `setAccessibilityTitleUIElement` gives the field a
spoken name, but an unparseable-text revert (**reverts-on-unparseable-text**)
changes `textField.stringValue` with no explicit `NSAccessibility` announcement
in source, so whether VoiceOver notices the reverted value while the field is
focused is left to AppKit's own, unverified-in-source, default behavior.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: cites IntegerFieldView by domain URL instead of file path and drops the out-of-scope, duplicative Design Decision about this recipe's requirement count; reformats Design Decisions to the three-line form and corrects an inaccurate parsing example in the POSIX-first decision; trims tags to five; rewords clamps-to-bounds' guard as a positive cross-reference; drops dangling trailing MUST keywords from Edge Cases; corrects the Concurrent Access edge case's actor-isolation claim; strengthens three test vectors (007, 020, 027, 030) to name a real trigger API or assert only observable outcomes; corrects WinUI 3's NumberBox.Minimum/Maximum defaults and documents its contradictory-bounds and locale-first-parsing divergence from this source; drops the web input's locale-hostile pattern attribute; marks screen-reader-support partial and documents why; backfills the missing 1.0.0 history row; remaps Compliance citations to the catalog; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
