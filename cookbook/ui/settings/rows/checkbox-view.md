---
id: e9c10ff7-4e13-4007-a963-d2a9e4006745
title: Checkbox View
domain: agentictoolkit://cookbook/ui/settings/rows/checkbox-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A settings row pairing a title label with a trailing toggle bound to a boolean view model.'
platforms:
- swift
- macos
tags:
- settings
- form-control
- toggle
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view
- agentictoolkit://cookbook/ui/settings/rows/stepper-view
references: []
approved-by: ''
approved-date: ''
---

# Checkbox View

## Overview

The Checkbox View is a settings row: a title label leading and a toggle
trailing, in the same row shape a system settings surface uses for a boolean
setting. Despite the name, the control it draws is a switch, not a checkbox
button — the concept exists because a checkbox puts its control on the left,
the one row shape that cannot line up with the popups, steppers, and sliders
beside it in the same settings card (see Design Decisions). The row is driven
by a boolean view model: the view reflects the view model's title/value on
construction and whenever the view model reports an external change, and it
writes the user's switch interactions back into the view model's setting
observer.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label and the
  toggle in a single horizontal row (label, then toggle), MUST place the
  toggle at the row's trailing edge with a flexible spacer absorbing the
  leftover width between the label and the toggle, and MUST pin that row to
  the edges of the view.
- **links-toggle-accessibility-title**: Component MUST link the toggle's
  accessible name to the label, so the toggle is announced with the label's
  text rather than as an unlabelled control.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to the view model's title and the
  toggle's state to on when the view model's value is true and off when it
  is false.
- **commits-toggle-value**: Component MUST write the toggle's new boolean
  value into the view model's setting observer whenever the toggle is
  activated and the new value differs from the current setting-observer
  value.
- **skips-redundant-commits**: Component MUST NOT write to the setting
  observer when the toggle's new value equals the current setting-observer
  value.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  the view model's title and the toggle's state to reflect the view model's
  value whenever the view model reports an external change.
- **exposes-constituent-views**: Component MUST expose the label and the
  toggle as public, directly-accessible properties.
- **requires-view-model-at-construction**: Component MUST be constructible
  only with a view model supplied at construction time; construction paths
  that could produce an instance without one (e.g. a bare/default
  construction path or a serialization/decoding-based construction path)
  MUST be rejected (see Platform Notes for the mechanism the source uses).
- **confines-to-ui-thread**: Component MUST be usable only on the UI
  thread.
- **claims-sole-onchange-observer**: Component MUST assign its own handler
  to the view model's external-change notification during initialization,
  superseding any handler already registered on that view model instance
  (see **overwritten external observer** in Edge Cases).
- **inherits-native-keyboard-focus**: Component MUST NOT override the
  toggle's or the label's default focus, tabbing, or key-handling behavior;
  no custom first-responder, key-handling, or focus-ring override appears in
  source, so keyboard operability follows the platform's native toggle
  control behavior unchanged.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes a stock label and a stock toggle control
  into a row.
- **Padding**: The row inserts a flexible spacer between the label and the
  toggle and sets the row's spacing to 8pt, which applies to the
  label-to-spacer gap; the spacer-to-toggle gap is explicitly zeroed, so the
  spacer's own width is the only thing between the label and the toggle. The
  toggle keeps its own default higher expansion priority (higher than the
  spacer's), so the spacer, not the toggle, absorbs the row's leftover
  width. The row is pinned directly to the component's edges with no
  additional constant, so the component contributes 0pt of its own outer
  padding beyond that internal 8pt / 0pt spacing.
- **Font**: The label (button text role) resolves to 13pt, medium weight,
  proportional system font. The size scales with the active theme's size
  scale (1.0 by default) and the label repaints automatically on a theme
  change. The toggle draws no text of its own.
- **Background**: None (transparent) — the label draws no background,
  border, or bezel, and neither the component nor the row container sets a
  background color of its own.
- **Foreground/Text**: The label (primaryText color role) resolves to the
  active theme's foreground color at full strength, recomputed live on a
  theme change. The toggle's on/off track and thumb colors are the
  platform's own system rendering; the component sets no color on the
  toggle.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in source; sizing is governed entirely by the label's
  and the toggle's own intrinsic content sizes, the row's 8pt spacing, and
  the row's edge pinning.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; toggle state reflects the view model's value. |
| On | Toggle is on, drawn as the platform's system on-track appearance; set on init when the view model's value is true, and on any user or external change that sets the value true. |
| Off | Toggle is off, drawn as the platform's system off-track appearance; set on init when the view model's value is false, and on any user or external change that sets the value false. |
| Pressed | Not applicable: the component renders no button; the toggle's own drag/press animation while switching on or off is the platform's default rendering, not custom to this file. |
| Disabled | Not implemented in the component; an enabled flag is never read or set on the label or toggle in source. A caller may set the toggle's enabled state directly through the public toggle property, at which point the platform's native disabled dimming applies. |
| Focused | Not styled by the component; any focus ring when the toggle is tabbed to is the platform's own native focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized beyond the title-element link below — no
  custom accessibility-role call appears in source; the toggle carries the
  platform's own built-in accessibility role for a switch/toggle control.
- **Label requirements**: Component MUST link the toggle's accessible name
  to the label — a bare switch otherwise has no name, so an assistive
  technology would announce it as an unlabelled control; the visible label
  supplies the accessible name instead of a separate accessibility-label
  string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself in source (see
  States); on/off is announced by the toggle's own native accessibility
  value reporting when its state changes, which the component does not
  override.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-driven
  composition (no touch input path in source); a touch-target minimum is
  touch-interface guidance, not a pointer-interface requirement. The
  component sets no custom control size on the toggle, so it keeps the
  platform's regular system click-target metrics.
- **Keyboard operability**: The component sets no custom first-responder,
  key-handling, or focus-ring override on the toggle or label in source, so
  the toggle keeps its inherited tab order and its native Space/Return
  activation (see **inherits-native-keyboard-focus**).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| checkbox-view-001 | arranges-row-layout | Construct the component with any view model | The label and the toggle are both part of a single row that is pinned to the component's edges; a flexible spacer sits between the label and the toggle, so the toggle sits at the row's trailing edge; no other layout container appears |
| checkbox-view-002 | links-toggle-accessibility-title | Construct the component with any view model | The toggle's accessible name is linked to the label |
| checkbox-view-003 | initializes-from-view-model | View model title = "Enable Sync", value = true | After init, the label reads "Enable Sync" and the toggle is on |
| checkbox-view-004 | initializes-from-view-model | View model value = false | After init, the toggle is off |
| checkbox-view-005 | commits-toggle-value | Setting-observer value = false; set the toggle on and activate it | The setting-observer value is true after the call |
| checkbox-view-006 | skips-redundant-commits | Wrap the setting-observer value's setter with a spy; set the value to true, then set the toggle on (same value) and activate it | The spy records zero calls: the setter is not invoked, and the value remains true |
| checkbox-view-007 | syncs-on-external-change | After construction, externally change the view model's title and value, then trigger an external-change notification | The label and toggle both update to reflect the new view-model state |
| checkbox-view-008 | exposes-constituent-views | Construct the component, then access its label and toggle properties from outside the type | Both properties are accessible and return the same instances built during init |
| checkbox-view-009 | requires-view-model-at-construction | Attempt construction via a bare/default construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| checkbox-view-010 | requires-view-model-at-construction | Attempt construction via a serialization/decoding-based construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| checkbox-view-011 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | Rejected by the platform's UI-thread confinement enforcement (compile-time on platforms with static isolation checking such as Swift's `@MainActor`, runtime-checked otherwise) |
| checkbox-view-012 | claims-sole-onchange-observer | Register an observer on the view model's external-change notification, then construct the component against that same view model | The notification now points at the component's own handler; invoking it no longer calls the previously registered observer |
| checkbox-view-013 | inherits-native-keyboard-focus | Construct the component in a running app, tab focus to the toggle, then press Space | The toggle receives keyboard focus in the window's tab order and its state flips on Space, per the platform's native toggle-control behavior (unmodified by source) |

Vector checkbox-view-011 is a static, code-inspection check (a
compile-/runtime-enforced thread confinement), not a vector observed by
running the program; a port lacking equivalent enforcement should document
the gap rather than fabricate a runtime trap.

## Edge Cases

- Null/empty input: the view model is a non-optional, typed constructor
  parameter, ruled out from being missing by the platform's type system, so
  the component needs no nil-handling path for its one initializer
  parameter. The view model's title as an empty string produces a label
  with an empty string and no crash.
- Boundary values: Not applicable — the bound value is boolean, a two-value
  type with no minimum/maximum or intermediate range to bound.
- Concurrent access: Not applicable — the component is confined to the UI
  thread, so all construction and mutation is serialized to that thread
  (see **confines-to-ui-thread**).
- Error states: Not applicable — every operation in this file (the
  toggle's activation and the setting-observer write) is a synchronous,
  non-throwing call; no error-producing path appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- Overwritten external observer: the view model's external-change handler
  is a single property. The component's initializer unconditionally
  assigns its own handler, replacing whatever handler (if any) was
  previously registered on that view model (see
  **claims-sole-onchange-observer**). Constructing a second instance of
  this component (or any other observer) against the same view model
  silently drops the earlier handler.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | boolean view model object | — (required) | Supplies the row's title and current boolean value; receives committed toggle changes via its setting observer. The initializer also overwrites this view model's external-change handler with the component's own update handler (see **claims-sole-onchange-observer**). An inherited explanation field is accepted by the initializer chain but never read or rendered anywhere in source. |

## Deep Linking

Not applicable: the component is a row inside a composable settings window,
not a navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in source.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes entirely from the view model's title, a value
the caller provides, so there is nothing for this component to localize
itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation or transition call; every state change is an instantaneous property assignment. |
| Increase Contrast | Not verified for the label: this component sets no custom color of its own on the toggle, and the label's color comes from the theme's primaryText color role, but nothing in this source, or in the theme code searched, shows that role responding to the system Increase Contrast setting. The toggle's own track/thumb colors are unmodified system rendering, which does track Increase Contrast automatically. |
| Differentiate Without Color | Not applicable: the on/off state is communicated through the toggle's own track position and system iconography, not through a color-only signal introduced by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in source; the row always renders once constructed.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by the view model and reports
  toggle changes back through the view model's setting observer.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store; persistence, if any, is owned by the view model and its
  setting observer, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the component retains only its own
  constituent elements (label, toggle) and its reference to the view model
  for its own lifetime; it persists nothing beyond that.

## Logging

Not applicable: the source contains no logging call.

## Platform Notes

- **SwiftUI**: Replace with an `HStack` containing `Text(viewModel.title)`
  and a trailing `Toggle("", isOn: $isOn).labelsHidden()`, giving the
  `Toggle` an `.accessibilityLabel(viewModel.title)` (SwiftUI's analog of
  `setAccessibilityTitleUIElement`) so the switch announces the row's title
  rather than being unlabelled. Write the user's flips back into the
  underlying setting from the `Binding`'s setter with an equality guard,
  mirroring skips-redundant-commits.
- **Compose**: Use a `Row` with `Text(title)` leading and a trailing
  `Switch(checked = value, onCheckedChange = { ... })`. Give the `Switch` a
  `Modifier.semantics { contentDescription = title }` (the Compose analog
  of the title-element link), and commit to the backing state/view-model
  from `onCheckedChange` with an equality check before writing, mirroring
  skips-redundant-commits.
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title and
  an `<input type="checkbox" role="switch">` (or a styled switch component)
  whose `aria-labelledby` points at the title `<label>`'s `id` — the web
  analog of `setAccessibilityTitleUIElement`. Commit the new value on the
  input's `onChange` handler, comparing against the previous value before
  calling the parent's setter to mirror skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CheckboxView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`-isolated
  (the mechanism behind confines-to-ui-thread), inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and an `NSSwitch` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`, links the switch's
  accessibility title to the label
  (`toggle.setAccessibilityTitleUIElement(label)`), and wires the switch's
  target/action (`toggle.target = self`, `toggle.action =
  #selector(toggleChanged(_:))`) — the AppKit plumbing behind
  **commits-toggle-value** — to `toggleChanged(_:)`. Both inherited `NSView`
  initializers that could construct the view without a `viewModel` —
  `init(coder:)` and the frame-only `init(frame:)` — are forced to
  fatal-error, leaving `init(with:)` as the only usable initializer; this is
  the mechanism behind requires-view-model-at-construction. There is no
  UIKit code path in source; a UIKit port would replace `NSSwitch` with
  `UISwitch` and the `target`/`action` pattern with
  `.addTarget(_:action:for: .valueChanged)` — UIKit has no `NSCoder`-vs-frame
  initializer split to fatal-error on both the way the source's two
  initializers do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column 0
  (the `*` column lets the title claim the row's leading space, the WinUI
  analog of `makeRow`'s flexible spacer sitting between the label and the
  control); a `ToggleSwitch` (or `ToggleSwitch` restyled with
  `OnContent=""`/`OffContent=""` to read as a plain switch, matching
  `NSSwitch`'s minimal chrome) bound `IsOn="{x:Bind IsOn, Mode=TwoWay}"` in
  column 1, `HorizontalAlignment="Right"`. Set
  `AutomationProperties.LabeledBy` on the `ToggleSwitch` to the `TextBlock`
  — the WinUI analog of `setAccessibilityTitleUIElement` linking a bare
  control's name to its visible label. Write the committed value through a
  property setter that skips the assignment (and so skips raising
  `INotifyPropertyChanged`) when the incoming value already equals the
  current value, mirroring skips-redundant-commits. `ToggleSwitch`'s
  built-in `Toggled` event is the WinUI analog of `toggleChanged(_:)`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CheckboxView.swift` |

## Design Decisions

- **Decision** (AppKit): Draw the row's control as an `NSSwitch`, not a
  checkbox button, despite the type being named `CheckboxView`.
  **Rationale**: Per the source's own doc comment, the switch replaced a
  checkbox-with-title button because a checkbox puts its control on the
  left, "the one row shape that cannot line up with the popups, steppers
  and sliders beside it in the same card — and left every group looking
  like two different lists interleaved."
  **Approved**: pending
- **Decision** (AppKit): Name the public property `toggle`, not
  `checkbox`.
  **Rationale**: Per the source's own doc comment, the control "has not
  been a checkbox since the row was restyled, and a name that lies about a
  control's class is the kind that gets `state = .on` written against the
  wrong API."
  **Approved**: pending
- **Decision**: Link the toggle's accessible name to the label rather than
  setting a separate accessibility-label string.
  **Rationale**: Per the source's own comment, a bare switch has no name
  of its own, so an assistive technology would announce it as an
  unlabelled control; the visible label is its title element.
  **Approved**: pending
- **Decision** (AppKit): Force a fatal error from both `init(coder:)` and
  the frame-only `init(frame:)`, leaving `init(with:)` as the only usable
  initializer.
  **Rationale**: The view has no meaningful default state — it cannot
  render a title or value without a view model — so both inherited
  `NSView` initializers that could construct it without one are
  intentionally disabled rather than left to produce a half-configured
  row.
  **Approved**: pending
- **Decision** (AppKit): Keep the public type name `CheckboxView` even
  though it draws a switch, not a checkbox.
  **Rationale**: The type is `SettingsViewProtocol`-conforming API surface
  read by callers across `ComposableSettingsWindow`; renaming it (e.g. to
  `SwitchRowView`) is a breaking rename with no behavioral upside, while the
  file's own doc comments already correct the mismatch at the
  `toggle`-vs-`checkbox` property level (see the `toggle` naming decision
  above) — callers and tests all read `toggle`, not the type name, so the
  outer name causes no runtime confusion today.
  **Approved**: pending
- **Decision**: Unconditionally overwrite the view model's external-change
  handler with the component's own handler during initialization, rather
  than chaining it after any previously registered handler.
  **Rationale**: The source's external-change property is a single
  closure/callback slot with no built-in multicast support; chaining would
  require a broader change to the shared view-model type, which is out of
  scope for this row view. The source accepts the tradeoff that one
  instance of this component (or other observer) per view model instance
  is the supported usage (see **claims-sole-onchange-observer**).
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`keyboard-navigable` and `screen-reader-support` rest on `toggle` being an
unmodified `NSSwitch`/`NSControl` with `setAccessibilityTitleUIElement` set
(no focus, key-handling, or accessibility-role override anywhere in
source — see **inherits-native-keyboard-focus** and
**links-toggle-accessibility-title**); `idempotent-operations` is `partial`
because repeated commits of the same toggle value are a no-op
(**skips-redundant-commits**), but constructing a second observer against
the same `viewModel` is not idempotent — it silently overwrites the prior
`onChange` handler (**claims-sole-onchange-observer**).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: shorten summary; add related sibling recipes; split target/action wiring into Platform Notes and add trailing-edge/spacer detail to arranges-row-layout; add claims-sole-onchange-observer and inherits-native-keyboard-focus requirements with test vectors; move normative language out of Edge Cases; mark Increase Contrast label color as not verified; drop the non-decision explanation entry from Design Decisions; downgrade idempotent-operations to partial and add compliance evidence sentence; backfill initial Change History row |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
