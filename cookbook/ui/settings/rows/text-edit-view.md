---
id: c1787e74-2485-4d7b-a219-feb4c07cf97c
title: Text Edit View
domain: agentictoolkit://cookbook/ui/settings/rows/text-edit-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a label with a plain text field, synced to a
  string-valued view model and restyled on every theme change.
platforms:
- swift
- macos
tags:
- settings
- form-control
- text-input
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/secure-text-edit-view
references: []
approved-by: ''
approved-date: ''
---

# Text Edit View

## Overview

The Text Edit View is a settings row: a leading label paired with a trailing
plain text field, bound to a string-valued view model. It builds its text
field through an overridable construction point so a variant can substitute
a different control type while inheriting everything else — the row layout,
the theme-driven font/color styling, the edit-completion commit path, and
the view-model sync. The Secure Text Edit View (documented separately at
`agentictoolkit://cookbook/ui/settings/rows/secure-text-edit-view`) is the
one variant that exists today, overriding only that construction point to
return a secure text-entry control. This recipe documents the Text Edit View
itself: the behavior every row built from it — plain or secure — inherits.

## Behavioral Requirements

- **constructs-plain-text-field**: Component MUST construct its text field
  with the view model's current value as its initial content, via an
  overridable construction point whose default implementation returns a
  plain text field.
- **supports-text-field-substitution**: Component MUST expose that
  construction point as overridable, so a variant (such as a secure
  text-entry row) can substitute a different control type while reusing
  every other behavior unmodified.
- **arranges-row-layout**: Component MUST arrange the label and the text
  field in a single horizontal row (label, then text field), and MUST pin
  that row to the edges of the component.
- **expands-text-field-to-fill-row**: Component MUST size the text field so
  it — not the gap between it and the label — takes the width left over
  after the label (see Design Decisions for the specific mechanism and
  value).
- **wires-text-field-action**: Component MUST route the text field's
  edit-completion signal to itself, so a committed edit reaches the view
  model's committed value (see Platform Notes for the specific mechanism).
- **initializes-from-view-model**: Component MUST, during initialization,
  set the label's text to the view model's title and construct the text
  field with the view model's value as its initial value.
- **commits-value-on-change**: Component MUST write the field's current
  string value into the view model's committed value whenever the field's
  edit-completion signal fires and that value differs from the current
  committed value.
- **skips-redundant-commits**: Component MUST NOT write to the view model's
  committed value when the field's value equals the current committed
  value.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  the view model's title and the field's string value to the view model's
  value whenever the view model's change notification fires.
- **applies-theme-styling**: Component MUST set the text field's font to the
  theme's body-role font and its text color to the theme's primary-text
  color, both immediately upon construction and again on every subsequent
  theme change.
- **restyles-existing-placeholder**: Component MUST, whenever a theme
  change fires and the field's placeholder text is set at that moment,
  restyle the placeholder in the theme's body-role font and
  placeholder-text color.
- **exposes-constituent-views**: Component MUST expose its label and its
  text field as public, directly-accessible, immutable sub-components.
- **claims-sole-onchange-observer**: Component MUST assign its own handler
  to the view model's change notification during initialization,
  superseding any handler already registered on that view model instance
  (see **overwritten external observer** in Edge Cases).

## Appearance

- **Corner radius**: Not applicable — no custom layer or drawn shape is
  added; the text field keeps whatever corner rendering its default bezel
  style draws, which is the platform's own rendering, not this component's.
- **Padding**: The row layout inserts a flexible spacer between the label
  and the text field and uses 8pt of spacing for the label-to-spacer gap;
  the spacer-to-field gap is explicitly zeroed, so the spacer's own width is
  the only thing between the label and the field. The text field is sized
  to absorb the row's leftover width instead of the spacer (see
  expands-text-field-to-fill-row). The row is pinned to the component's own
  edges with no additional constant, so the component contributes 0pt of
  outer padding beyond that internal 8pt/0pt spacing.
- **Font**: The label resolves to the button role's default style: 13pt,
  medium weight, proportional. The text field's typed text uses the body
  role's default style: 13pt, regular weight, proportional. Both scale with
  the active theme's size scale and repaint automatically on a theme
  change.
- **Background**: Not customized — the text field keeps its own default
  editable-field chrome (bordered/bezeled, background drawn); the component
  sets no background/border override on the field, the row, or itself.
- **Foreground/Text**: The label and the text field's typed text both
  resolve to the same role — the active theme's foreground color unchanged
  — recomputed live on a theme change. Placeholder text, when present, uses
  the placeholder-text role instead (see Design Decisions for its contrast
  floor).
- **Border**: Not customized; whatever bezel/border the text field's default
  construction draws (the platform's own rendering) applies unmodified.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set; sizing is governed entirely by the label's and the
  text field's own intrinsic content sizes, the row's 8pt/0pt spacing, the
  sizing behavior described above, and the row's edge pinning.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; the text field's value equals the view model's value, rendered as plain typed characters. |
| Editing | Not styled by the component — no focus-ring customization is applied; the platform's own default focus indicator applies when the field becomes focused. |
| Committed | After the field's edit-completion signal fires (on Return and on the field losing focus, per the platform's own default semantics) and the new value differs from the committed value, the new value is written into the committed value. |
| Placeholder shown | Not applicable unless a caller sets the field's placeholder text directly through the component's exposed text field — the view model carries no placeholder value of its own. When one is set and a later theme change fires, its styling is restyled per restyles-existing-placeholder (see Design Decisions for why the very first, construction-time apply never restyles it). |
| Disabled | Not implemented: the enabled state is never read or set on the label or the text field. A caller may set the text field's enabled state directly through the exposed property, at which point the platform's native disabled dimming applies. |
| Pressed | Not applicable: a text field has no discrete pressed state distinct from becoming focused and placing the caret; no such state is drawn. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator. |

## Accessibility

- **Role/trait**: Not customized — no explicit accessibility role is set;
  the text field carries the platform's own built-in text-field
  accessibility role.
- **Label requirements**: The component never links the text field's
  accessible name to the label — unlike the sibling checkbox row, which
  links its switch to its label for exactly this reason ("a bare switch has
  no name"). Without that link, a screen reader announces the text field as
  an unnamed text field rather than by the row's title. Because the secure
  variant inherits this initializer unmodified, the same gap applies there.
- **Announce state changes**: Not applicable — the component has no loading
  state and never disables itself in source (see States); typed characters
  being entered or deleted are announced through the text field's own
  native accessibility value reporting, unmodified by this component.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-driven
  composition (no touch input path); the 44×44pt minimum is touch-interface
  guidance, not a pointer-interface requirement. No explicit control size is
  set on the text field, so it keeps the platform's regular system
  click-target metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented by the
  component. The label and the text field's typed-text color both resolve
  to the theme's primary-text role (no minimum contrast computed for this
  role), and placeholder text resolves to the placeholder-text role, dimmed
  toward the background with only a `minContrast: 1.6` floor (see Design
  Decisions) — below WCAG 2.1 SC 1.4.3's 4.5:1 threshold for body text;
  settling it needs the text-to-background ratio measured for both roles
  under every shipped theme, or a raised placeholder-text floor in the
  theme layer.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| text-edit-view-001 | constructs-plain-text-field | Construct with any view model | The text field is constructed with the view model's value as its string value |
| text-edit-view-002 | supports-text-field-substitution | Define a variant overriding the control-construction extension point to return a secure text-entry control | The variant compiles and constructing it produces a text field of the overridden type, with the row layout, theming, and commit wiring unchanged |
| text-edit-view-003 | arranges-row-layout | Construct with any view model | The label and the text field are both part of a single row that is pinned to the component's edges; no other layout container appears |
| text-edit-view-004 | expands-text-field-to-fill-row | Inspect the text field's sizing behavior relative to the row's spacer after construction | The text field is configured to absorb the row's leftover width, not the spacer (see Design Decisions for the exact mechanism and value) |
| text-edit-view-005 | wires-text-field-action | Any initialized component | The text field's edit-completion signal is routed to the component itself; invoking it reaches the component's edit-commit handler, which can write to the committed value (see Platform Notes for the specific mechanism) |
| text-edit-view-006 | initializes-from-view-model | View model's title is "Server Name", value is "prod-1" | After construction, the label's text is "Server Name" and the text field's value is "prod-1" |
| text-edit-view-007 | commits-value-on-change | Committed value is "old"; set the text field's value to "new" and trigger its edit-completion signal | The committed value is "new" after the call |
| text-edit-view-008 | skips-redundant-commits | Committed value is "same"; set the text field's value to "same" and trigger its edit-completion signal, observing writes via a recording spy or observer registered on the committed value | The spy/observer records zero additional writes to the committed value after the call |
| text-edit-view-009 | syncs-on-external-change | After construction, externally change the view model's title and value, then trigger its change notification | The label's text and the text field's value both update to reflect the new view-model state |
| text-edit-view-010 | applies-theme-styling | Construct the component, then trigger a theme change | The text field's font equals the theme's body-role font and its text color equals the theme's primary-text color, both immediately after construction and again after the theme change |
| text-edit-view-011 | restyles-existing-placeholder | After construction, set the field's placeholder text to "Enter value", then trigger a theme change | The placeholder's color equals the theme's placeholder-text color and its font equals the theme's body-role font |
| text-edit-view-012 | exposes-constituent-views | Construct the component, then access its label and its text field from outside the component | Both properties are accessible and return the same instances built during construction |
| text-edit-view-017 | claims-sole-onchange-observer | Register an observer callback on the view model's change notification, then construct a component against that same view model | The view model's change notification now points at the component's own handler; invoking it no longer calls the previously registered callback |

## Edge Cases

- Null/empty input: the view model is a required, non-optional construction
  parameter; there is no null case to handle for the component's one
  initializer parameter. An empty title or value produces an empty label or
  field with no crash.
- Boundary values: Not applicable — the bound value is a string with no
  minimum or maximum length enforced anywhere in the component; any length
  is accepted and displayed as-is.
- Concurrent access: Not applicable — the component is confined to
  construction and mutation from a single, serialized execution context
  (see Platform Notes).
- Error states: Not applicable — every operation (the field's commit path
  and the committed-value write) is a synchronous, non-throwing call; no
  error-producing path exists.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process view
  model.
- Overwritten external observer: the view model's change notification is a
  single callback property. Construction unconditionally assigns the
  component's own handler to it, replacing whatever handler (if any) was
  previously registered on that view model (see **claims-sole-onchange-
  observer**). Constructing a second row (plain, secure, or any other
  observer) against the same view model silently drops the earlier handler.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | View model | — (required) | Supplies the row's title and current string value; receives committed edits. The initializer also overwrites this view model's change-notification callback with the component's own sync handler (see Edge Cases). An explanation field the view model may carry is accepted but never read or displayed by this component. |

## Deep Linking

Not applicable: the component is a row inside a settings panel, not a
navigable screen; no URL scheme, route, or deep-link handler applies.

## Localization

Not applicable: the component defines no user-facing string literal of its
own. The row's title comes entirely from the view model's title, a value
the caller provides, so there is nothing for this component to localize
itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component performs no animation or transition; every state change is an instantaneous property assignment (the label's text, the field's value, the field's font/color). |
| Increase Contrast | Not applicable to this component directly: it sets no literal color; text/label color comes from the theme's primary-text/placeholder-text roles, whose actual resolved contrast (including the placeholder role's 1.6:1 floor — see Design Decisions and the Accessibility section's Contrast note) is the theme layer's responsibility, not this component's; the text field's bezel/border follow the platform's own default rendering. |
| Differentiate Without Color | Not applicable: the field's content is the plain typed text itself; no state in this component is communicated by color alone. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate applies; the row
always renders once constructed.

## Analytics

Not applicable: the component performs no analytics or telemetry.

## Privacy

- **Data collected**: Whatever the field's typed value is — an arbitrary
  string supplied and read by the caller through the view model. The
  component does not classify, mask, or redact this value; it displays it
  in full as plain text (unlike its secure variant) and holds it in the
  view model's committed value, passing it through unchanged.
- **Storage**: Not applicable within this component — it holds the value
  only in the text field and the view model's committed value for the
  component's lifetime. Persistence, when it happens, is owned entirely by
  the caller-supplied view model's backing setting, outside this
  component's own concern.
- **Transmission**: Not applicable — no networking occurs here. Where the
  committed value goes afterward is entirely owned by whatever consumes the
  view model's committed value.
- **Retention**: The value lives only in the text field and the view
  model's committed value for as long as the row is on screen and its view
  model is retained. No explicit zeroing or secure-erasure is performed on
  the string; the value is released along with the component and its view
  model like any other property.

## Logging

Not applicable: the component performs no logging.

## Platform Notes

- **SwiftUI**: Replace with an `HStack` pairing `Text(viewModel.title)`
  leading and a trailing `TextField("", text: $value)`, tracked through a
  local editing state. Commit the value back into the underlying setting
  on `.onSubmit` (Return) or when a `@FocusState` boolean bound to the
  field transitions from `true` to `false` (focus loss) — not on every
  keystroke via the binding setter — with an equality guard before
  assigning, mirroring skips-redundant-commits and the platform's own
  commit points. Give the field an explicit
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
  writing, mirroring skips-redundant-commits and the platform's own commit
  points. Give it `Modifier.semantics { contentDescription = title }` (the
  missing accessibility link's Compose analog).
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title
  and an `<input type="text">` whose `aria-labelledby` points at the
  title `<label>`'s `id` — the web analog of the accessibility link this
  recipe flags as missing from the source. Track the typed value locally
  and commit the new value to the parent's setter only on the input's
  `blur` handler or Enter via `onKeyDown`, not on every `onChange` call —
  an `<input>` fires `onChange` per keystroke — comparing against the
  previous value before calling the parent's setter, mirroring
  skips-redundant-commits and the platform's own commit points; style the
  input's font/color and any placeholder from theme tokens equivalent to
  `.body`/`primaryText`/`placeholderText`, mirroring applies-theme-styling.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextEditView.swift`:
  a macOS-only, `@MainActor` `NSView` subclass inside the
  `ComposableSettings` namespace, `open` to subclassing through its
  `makeTextField(initialValue:)` factory — the mechanism
  `SecureTextEditView.swift` (in the same directory) uses to substitute
  `NSSecureTextField`. `textField.target` is set to the view itself and
  `textField.action` to `Selector("textFieldChanged:")`, its private
  `@objc` handler that performs the commit (see wires-text-field-action).
  The component is constructed only via `init(viewModel:)`: the
  fatal-erroring `init?(coder:)` and the frame-only `init(frame:)` are
  overridden to trap, so a caller cannot construct one without a view
  model. `@MainActor` confines construction and mutation to the main actor
  under Swift's concurrency checking. `TextEditView` conforms to
  `SettingsViewProtocol`, a marker protocol
  (`.../Views/SettingsViewProtocol.swift`) that `ComposableSettings` uses to
  type its row views; the protocol adds no requirements of its own beyond
  `NSView` conformance. The file is macOS-only (`import AppKit`); there is
  no UIKit code path in source. A UIKit port would replace `NSTextField`
  with a `UITextField` and the target/action pattern with
  `.addTarget(_:action:for: .editingDidEndOnExit)`. Known source bug: the
  frame-only initializer's fatal-error message string is malformed
  (`fatalError("init(frame frameRect: NSRect")`, missing its closing
  parenthesis) — the trap still fires correctly; only the printed message
  text is wrong.
- **WinUI 3**: Build the row as a `Grid` with column definitions `Auto,*`:
  a `TextBlock` for the title in column 0 (`Auto`, sized to its content,
  the WinUI analog of the row's label), and a `TextBox` — the direct
  analog of the plain text field this class constructs — in column 1
  (the `*` column, which claims the row's leftover space), with
  `HorizontalAlignment="Stretch"` so the field, not the title, takes the
  leftover width the way expands-text-field-to-fill-row does. Set
  `AutomationProperties.LabeledBy` on the `TextBox` to the `TextBlock` —
  the WinUI analog of the accessibility link this recipe flags as missing
  from the AppKit source; add it in the port even though the source itself
  omits it. Commit on the `TextBox.LostFocus` event (or `KeyDown` on
  Enter, mirroring the platform's own commit-firing points), writing
  through a property setter that skips the assignment (and so skips
  raising `INotifyPropertyChanged`) when the incoming value already equals
  the current one, mirroring skips-redundant-commits. Bind
  `TextBox.Foreground` and `PlaceholderForeground`/`PlaceholderText` to
  theme resource brushes equivalent to `primaryText`/`placeholderText`
  rather than hardcoded colors, mirroring
  applies-theme-styling/restyles-existing-placeholder. For a secure
  variant, a `PasswordBox` is the WinUI analog to build against instead,
  the way the Secure Text Edit View overrides this class's factory.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextEditView.swift` |

## Design Decisions

- **Decision**: Give the text field a horizontal content-hugging priority
  (AppKit: `NSLayoutConstraint.Priority(1)`) one step below the row
  spacer's, rather than leaving it at its default hugging.
  **Rationale**: per the source's own inline comment, this is "below the
  row spacer's hugging, so the field — not the gap — takes the width left
  over after the label. An empty field sized to its own content is a few
  points wide and unclickable." Without it, an empty text field would
  shrink to its own tiny intrinsic width and the spacer would absorb the
  row's slack instead. (AppKit source.)
  **Approved**: pending
- **Decision**: Declare the text-field construction point as an overridable
  factory (AppKit: `open class func makeTextField(initialValue:)`) instead
  of returning a fixed text field inline in the initializer.
  **Rationale**: this is the one seam the component designs in for
  variation — the secure variant overrides only this method to substitute
  a secure text-entry control, reusing every other line of the initializer
  (row layout, content-hugging, theme observation, commit wiring)
  unmodified.
  **Approved**: pending
- **Decision**: Attach theme-change styling inside the initializer rather
  than by returning an already-themed field type from the construction
  point.
  **Rationale**: per the source's own inline comment, "subclasses
  substitute their own field ... so the theme is attached here rather than
  by returning a `ThemedTextField` from the factory" — keeping theming in
  one place regardless of which control type the construction point
  returns. (AppKit source.)
  **Approved**: pending
- **Decision**: Restyle an existing placeholder only on a theme change that
  occurs *after* construction, never on the initial apply.
  **Rationale**: the theme-observation mechanism (AppKit:
  `ThemePaletteObserver.init`) applies its closure immediately upon
  registration, which happens inside the initializer before any caller can
  reach the newly-created text field to set a placeholder — so that first,
  construction-time apply always finds no placeholder set, and the
  restyling guard skips it. The placeholder is only ever styled by a later,
  caller-triggered theme change. This is a non-obvious consequence of
  initialization order, not a bug being idealized away.
  **Approved**: pending
- **Decision**: Accept that placeholder text is guaranteed only a 1.6:1
  contrast floor against the background.
  **Rationale**: the theme layer's derivation for the placeholder-text role
  dims the theme's foreground toward its background with `minContrast:
  1.6` — below WCAG 2.1 SC 1.4.3's 4.5:1 floor for normal text. This is a
  theme-layer choice inherited by every themed field, including this one;
  the component neither sets nor can override it. Recorded here as
  technical debt affecting accessibility correctness, per source-fidelity's
  requirement to document such debt rather than idealize it away.
  **Approved**: pending
- **Decision**: Whether the component should link the text field's
  accessible title to the label for a screen reader, the way the sibling
  checkbox row links its switch's accessibility title (AppKit:
  `setAccessibilityTitleUIElement(label)`).
  **Rationale**: Not implemented in source (see Accessibility's Label
  requirements gap) — the component never links the text field to the
  label, so a screen reader announces the text field as an unnamed text
  field rather than by the row's title. Recording the proposal here lets a
  port choose to copy the gap or fix it, since the Platform Notes already
  direct every port besides the AppKit source to add the link.
  **Approved**: pending
- **Decision**: Unconditionally overwrite the view model's change
  notification with the component's own handler during initialization,
  rather than chaining it after any previously registered handler.
  **Rationale**: the view model's change notification is a single callback
  property with no built-in multicast support; chaining would require a
  broader change to the shared view-model type, which is out of scope for
  this row component. The source accepts the tradeoff that one row (or
  other observer, including the secure variant) per view model instance is
  the supported usage (see **claims-sole-onchange-observer**).
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
