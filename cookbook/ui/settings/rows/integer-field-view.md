---
id: a7653559-cb70-43db-a75c-d032e4f599b3
title: Integer Field View
domain: agentictoolkit://cookbook/ui/settings/rows/integer-field-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row forwarding to a generic number field view, pairing a title
  label with a bounded, locale-aware integer text field.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
- numeric
depends-on:
- agentictoolkit://cookbook/ui/settings/rows/number-field-view
related:
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
- agentictoolkit://cookbook/ui/settings/rows/captioned-slider-view
references: []
approved-by: ''
approved-date: ''
---

# Integer Field View

## Overview

The integer field view is a settings row: a title label leading and a
narrow, right-aligned integer text field trailing, clamped to a range view
model's bounds. It exists because a slider is the wrong control for a
number the user already knows — "12 points on the left" is typed, not
dragged — and a stepper control makes the user click twelve times to say
it. The type is kept as a thin, forwarding wrapper around a private,
generic number field view, which does the actual work: it builds the label
and field, wires theming and accessibility, and owns the locale-aware
parse/clamp/commit logic. This component stays as its own public entry
point because a bounded integer field is still exactly this call, distinct
from the generic field it forwards to.

The wrapped number field view's own behavior — theming, activation and
delegate wiring, layout when a fixed label width is set, locale-aware
parsing, clamping, revert-on-invalid, and external-change sync — is
documented in full at
`agentictoolkit://cookbook/ui/settings/rows/number-field-view`, which this
recipe depends on. This recipe documents only what this component itself
contributes: constructing and forwarding to that wrapped view, exposing
its constituent views, and the construction/thread-confinement
requirements it does not inherit from it.

## Behavioral Requirements

The wrapped number field view's own requirements — label/field
construction, theming, activation and delegate wiring, fixed-label-width
layout, locale-aware parsing, clamping, revert-on-invalid, and
external-change sync — are documented at
`agentictoolkit://cookbook/ui/settings/rows/number-field-view#behavioral-requirements`. The requirements
below are this component's own: what it does to construct, forward to, and
expose that wrapped view.

- **wraps-number-field-view**: Component MUST construct a private, generic
  number field view, passing the supplied range view model as its view
  model and the view model's minimum/maximum values as its own
  minimum/maximum bounds.
- **exposes-constituent-views**: Component MUST expose the label and text
  field as public properties, set to the wrapped view's own label and
  text-field instances.
- **arranges-single-child**: Component MUST add the wrapped view as its
  only subview and pin it to its own top, leading, trailing, and bottom
  edges, contributing no additional outer padding of its own.
- **forwards-editing-end-to-wrapped-field**: WHEN the component is
  notified that editing of its text field has ended, it MUST commit that
  edit on the wrapped view.
- **default-field-width**: Component's initializer MUST default the field
  width to 52 points when the caller supplies none — narrower than the
  wrapped view's own uncalled default of 72 points (see Design Decisions)
  — and MUST pass that value through to the wrapped view's own field-width
  parameter.
- **forwards-label-width**: Component's initializer MUST pass its own
  label-width parameter (default none) through unchanged to the wrapped
  view.
- **requires-view-model-at-construction**: Component MUST support
  construction only through its designated initializer, which requires a
  view model; construction via a bare/default construction path or a
  serialization/decoding-based construction path MUST both trigger a fatal
  error.
- **confines-to-ui-thread**: Component MUST be usable only on the UI
  thread.

## Appearance

- **Corner radius**: Not applicable — neither this component nor the
  wrapped view sets a layer or draws a custom shape; both compose stock
  text controls.
- **Padding**: The wrapped view's row inserts a flexible spacer between
  the label and text field, sets the row's spacing to the button role's
  default row spacing (8pt, applied to the label→spacer gap), and zeroes
  the spacer→field gap — the same row shape and spacing math several
  sibling row controls in this system use. This component's own edge
  pinning adds 0pt of outer padding of its own; the wrapped view's own
  edge-pinning (or the content-width variant when a fixed label width is
  set) likewise adds nothing beyond that internal 8pt/0pt spacing.
- **Font**: The label uses the button text role, resolving to that role's
  default style: 13pt, medium weight, proportional system font, scaled by
  the active theme's size scale. The text field uses the code text role,
  resolving to that role's default style: 12pt, regular weight, the
  system monospaced font, also scaled by the size scale — chosen so a
  changing value doesn't reflow the field.
- **Background**: The label — none (transparent). The text field — source
  never overrides its border, bezel, or background settings on it; it
  stays a plain, default-initialized text field, which keeps the
  platform's standard bezeled, opaque text-field background rather than
  being transparent like the label.
- **Foreground/Text**: The label (primaryText role) resolves to the active
  theme's foreground color at full strength, repainted live on a theme
  change. The text field's text color is set directly to the same
  primaryText role, applied through the theme-observation mechanism rather
  than through the label's own theming path, also repainted live on every
  theme change.
- **Border**: The label — none. The text field — no border property is
  set in source, so it keeps the platform's default bezel, drawn by the
  platform rather than by this component.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: The text field's width is fixed to the constant field
  width (52pt via this component's own default; the wrapped view's own
  uncalled default is 72pt — see Design Decisions). No height constraint
  is set on either the label or the text field; height comes from each
  control's intrinsic content size within the row.

## States

| State | Appearance change |
|-------|------------------|
| Default | The label shows the view model's title; the text field shows the current value's formatted string, right-aligned, in the code-role monospaced font. |
| Editing | The user's typed text is shown verbatim while focused; no formatter is attached to intercept keystrokes (deliberate — see Design Decisions), so intermediate/partial text (e.g. a leading `-`) is not rejected mid-edit. |
| Committed — valid | On end-of-editing (Return/Tab/click-away) or on the field's own action firing, a parseable value is clamped (unless bounds are contradictory) and written back to the text field and the view model. |
| Committed — invalid | An unparseable string reverts the text field and label to the view model's current value/title; the view model is left unchanged. |
| Pressed | Not applicable: neither file renders a button; there is no press/highlight state to define. |
| Disabled | Not implemented in source; an enabled flag is never read or set on the label or text field. A caller may set the text field's enabled state directly through the public text-field property, at which point the platform's native disabled dimming applies. |
| Focused | Not styled by this component; any focus ring shown when the field becomes first responder is the platform's own native focus appearance for that control. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |

## Accessibility

- **Role/trait**: Not set explicitly anywhere in source. The text field
  keeps the platform's default editable-text-field accessibility role; the
  label keeps the platform's default for a non-editable field (set
  non-editable explicitly) — a static-text element.
- **Label requirements**: Component MUST link the text field's accessible
  name to the adjacent visible label — the same row pattern several
  sibling row controls in this system use — so the field's accessible name
  comes from that label rather than a separate accessibility-label string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller
  (see States); a committed clamp or revert updates the text field's
  displayed value directly, which the platform's own accessibility value
  reporting picks up automatically, with no explicit announcement call in
  source.
- **Minimum tap target**: Not applicable — this is a pointer/keyboard-driven
  composition with no touch input path in source; the 44×44pt guidance is
  touch-specific. No non-default control size is set on the text field, so
  it keeps the platform's regular system metrics; its clickable width is
  the fixed field width (52pt default here, per **default-field-width**),
  constrained onto the wrapped field's own width by the wrapped view's own
  fixed-width requirement (see
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#requirements/fixes-field-width`).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| integer-field-view-001 | wraps-number-field-view | Construct the component with a view model whose minimum is 0 and maximum is 10; set the text field's value to "99", then trigger the field's commit action | The text field's value becomes "10" — the clamp visible on the public text field shows the view model's minimum/maximum reached the wrapped field's own bounds |
| integer-field-view-002 | exposes-constituent-views | Construct the component with any view model | The label and text field are accessible from outside the type and are the same instances the wrapped view built |
| integer-field-view-003 | arranges-single-child | Construct the component with any view model, add it to a laid-out view hierarchy of a known size | The public label and text field together occupy the full bounds of the component with no additional outer inset: the label's frame leading edge equals the component's leading edge, and the text field's frame trailing edge equals the component's trailing edge |
| integer-field-view-004 | forwards-editing-end-to-wrapped-field | Set the text field's editing delegate to the component instance itself, type a valid number, then trigger the end-of-editing notification | The wrapped view's commit runs and the new value is stored |
| integer-field-view-005 | default-field-width | Construct the component with no field-width argument | The text field's width constraint is 52 |
| integer-field-view-006 | forwards-label-width | Construct the component with a label width of 80 | The wrapped field's label width constraint is 80 and the label is right-aligned |
| integer-field-view-007 | requires-view-model-at-construction | Attempt construction via a serialization/decoding-based construction path (no view model available) | The call traps with a fatal error (a platform-level runtime trap, not an ordinary in-process assertion); no instance is returned |
| integer-field-view-008 | requires-view-model-at-construction | Attempt construction via the bare/default construction path (no view model supplied) | The call traps with a fatal error (a platform-level runtime trap, not an ordinary in-process assertion); no instance is returned |
| integer-field-view-009 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking such as Swift's `@MainActor`, runtime-checked otherwise) |

Vector integer-field-view-009 is a static, code-inspection check (a compile-/runtime-enforced thread confinement), not a vector observed by running the program; a port lacking equivalent enforcement should document the gap rather than fabricate a runtime trap.

## Edge Cases

- **Null/empty input**: The view model is a non-optional, typed constructor
  parameter; the type system rules out a missing value. The wrapped field's
  own revert-on-empty-text behavior — an empty text-field value fails the
  parse the same as any other unparseable text — is documented at
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#edge-cases`.
- **Boundary values**: Clamping at the minimum/maximum, and skipping the
  clamp when the minimum exceeds the maximum, is entirely the wrapped
  view's behavior; see
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#edge-cases`.
  This component only supplies those bounds, via the view model's own
  minimum/maximum values (**wraps-number-field-view**).
- **Out-of-range magnitude and fractional/locale-formatted text**: Parsing
  — POSIX-first with a locale-aware fallback, magnitude-exactness rejection,
  and fractional rejection — is entirely the wrapped view's behavior; see
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#edge-cases`.
- **Concurrent access**: Not applicable — this component MUST be usable
  only on the UI thread (**confines-to-ui-thread**), so all construction
  and mutation is serialized to that thread. The wrapped view carries the
  same confinement independently; see
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#edge-cases`.
- **Error states**: Not applicable — every operation in source
  (construction, forwarding, and end-of-editing handling) is synchronous
  and non-throwing; no error-producing path appears in this file.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking; it only forwards to the wrapped view, which itself only
  reads from and writes to an in-process view model.
- **Overwritten external observer**: This is entirely the wrapped view's
  behavior — its initializer, not this component's, unconditionally
  assigns the view model's external-change handler; see
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#edge-cases`.
- **Delegate reassignment**: Because the text field's editing delegate is
  set to the wrapped view, not this component, a caller that reassigns the
  editing delegate to something else silently disables commit-on-editing-
  end; this component's own end-of-editing handler only fires if a caller
  explicitly re-points the editing delegate back at the outer component
  (see Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | range view model object | — (required) | Supplies the row's title and min/max/current integer value; receives committed field changes via the view model's setting observer. The initializer overwrites this view model's external-change handler with the wrapped field's own sync handler (see Edge Cases). |
| `fieldWidth` | numeric (points) | `52` | Width of the number field, in points. Differs from the wrapped view's own uncalled default of `72` — see Design Decisions. |
| `labelWidth` | numeric (points), optional | `nil` | When set, pins the label to a fixed, right-aligned width so a column of rows lines up; when unset, the row spans the container's full width. |

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in source.

## Localization

Not applicable: neither source file contains a user-facing string literal
of its own. The row's title comes entirely from the view model's title, a
value the caller provides, so there is nothing for this component to
localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation or transition call appears in either file; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: neither file sets a custom color outside the theme's primaryText role; the text field's own default border/bezel rendering already tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — valid, invalid, and clamped values are communicated entirely through the displayed digits; an invalid entry reverts silently with no color-only error indicator in source. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in source; the row always renders once constructed.

## Analytics

Not applicable: neither source file contains an analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by the view model and reports
  committed edits back through the view model's setting observer.
- **Storage**: Not applicable — neither source file reads or writes a
  platform storage mechanism directly. Persistence is owned by the range
  view model/setting-observer/setting chain, which is not part of these
  files; by default that chain routes through a settings-storage provider,
  so a committed value survives an app restart, but that guarantee lives
  outside this component.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (the label, the text field, the wrapped field) and its reference to the
  view model for its own lifetime; it persists nothing itself beyond that.

## Logging

Not applicable: neither source file contains a logging call anywhere in
source.

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
  fatal-error on both the way the source's designated initializer does
  (the mechanism behind **requires-view-model-at-construction**):
  `init?(coder:)` and `init(frame:)` are both overridden to call
  `fatalError`, so the only surviving construction path is the designated
  `init(viewModel:)`.
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
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#requirements/parses-posix-integer-first`),
  so a value written by this source's POSIX `settingsFieldString` can read
  differently under a non-en-US Windows locale; and `NumberBox.Minimum`/
  `Maximum`, when both set with `Minimum > Maximum`, has no documented
  skip-the-clamp behavior matching
  skips-clamp-on-contradictory-bounds (see
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view#requirements/skips-clamp-on-contradictory-bounds`)
  — a WinUI port needs an explicit `Minimum > Maximum` check before relying
  on `NumberBox`'s own clamping.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/IntegerFieldView.swift` |

## Design Decisions

- **Decision**: Keep this component as a thin, forwarding wrapper around
  the generic number field view rather than folding its logic in directly.
  **Rationale**: Per the source's own doc comment, "this name stays because
  it is public API of a framework other repos link: a bounded integer
  field is still exactly this call" — the generic view generalizes to
  optional, one-sided bounds that the range view model (which requires
  both) cannot express, so the behavior moved there (see
  `agentictoolkit://cookbook/ui/settings/rows/number-field-view`) while
  this component stayed as the compatible entry point.
  **Approved**: pending
- **Decision**: Default the field width to 52pt in this component's
  initializer, rather than reusing the wrapped view's own uncalled default
  of 72pt.
  **Rationale**: This component always passes an explicit field-width
  argument to the wrapped view's initializer, so the wrapped view's 72pt
  default is never reached through this type; 52pt is this component's
  own, narrower, pre-existing default, kept for source fidelity to callers
  that relied on it.
  **Approved**: pending
- **Decision (AppKit)**: Keep this component's own end-of-editing handler
  even though the text field's editing delegate is set to the wrapped
  view, not to this component itself.
  **Rationale**: Per the source's own comment, this method is "kept because
  it was public, and forwards for the same reason" — the platform calls
  the inner view's delegate method in the normal case, but any external
  caller still holding a reference to this component as an editing
  delegate (as public API predating this refactor allowed) still reaches
  the commit path through this forwarding method.
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
