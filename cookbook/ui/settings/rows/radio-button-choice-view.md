---
id: 7774cbd3-4883-43f0-aef0-f49a29389b98
title: Radio Button Choice View
domain: agentictoolkit://cookbook/ui/settings/rows/radio-button-choice-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row stacking a title label above a set of native radio
  buttons, one per choice in a choice view model.
platforms:
- swift
- macos
tags:
- settings
- form-control
- choice
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/choice-slider-view
references: []
approved-by: ''
approved-date: ''
---

# Radio Button Choice View

## Overview

The Radio Button Choice View is a settings row: a title label sitting above
a stack of native radio-button controls, one per entry in a choice view
model's ordered choices, each button's own title text set to that choice's
label. Unlike its sibling row views over the same choice view model (the
choice slider row, the popup menu choice row), this component does not use
the single horizontal [label, spacer, control] row layout its siblings
share; it composes two nested vertical/axis-driven groups instead — an
outer vertical group of [label, controls group], and an inner controls
group holding the radio buttons themselves, oriented by the constructor's
axis parameter (vertical by default). The row is driven by the view model:
it reflects the view model's title/value on construction and whenever the
view model reports an external change, and it writes the user's
radio-button selection back into the view model. A choice also carries an
optional symbol image, but this component never reads that field — only the
popup menu choice row, a sibling row over the same view model, renders it.

## Behavioral Requirements

- **arranges-heading-above-controls-stack**: Component MUST arrange the
  title label above a group of choice controls in a single outer, vertical
  container (label, then controls group), and MUST pin that outer
  container to the edges of the view.
- **builds-one-radio-button-per-choice**: Component MUST create one
  radio-type choice control for each entry in the view model's choices, in
  the same order, using that choice's label as the control's own visible
  text.
- **lays-out-controls-along-axis**: Component MUST arrange the created
  choice controls, in order, inside a single controls group whose layout
  orientation is set to the constructor's axis parameter (default
  vertical).
- **aligns-controls-stack-by-axis**: Component MUST align the controls
  group along its leading edge when axis is vertical, and along a shared
  first baseline when axis is not vertical.
- **spaces-stacks-by-row-spacing**: Component MUST set both the spacing
  between the label and the controls group, and the spacing between each
  control within the group, to the layout system's standard row spacing.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to the view model's title, and
  select the choice control whose associated value equals the view
  model's value while deselecting every other choice control.
- **commits-radio-selection**: Component MUST write the value paired with
  the choice control that fired the selection action into the view
  model's value whenever that value differs from the current value.
- **skips-redundant-commits**: Component MUST NOT write to the view
  model's value when the firing control's paired value equals the current
  value.
- **ignores-unmatched-sender**: Component MUST NOT write to the view
  model's value when the control that fired the selection action is not
  present in the component's recorded control-value pairs.
- **syncs-on-external-change**: Component MUST re-set the label's text
  from the view model's title, and re-select the choice control matching
  the view model's value while deselecting the rest, whenever the view
  model's change-notification callback fires.
- **exposes-constituent-views**: Component MUST expose the heading label
  and the ordered list of choice controls as public, directly-accessible
  properties; the choice-controls list MUST NOT be publicly replaceable as
  a whole (readable from outside the type, but not externally settable).
- **confines-to-ui-thread**: Component MUST be usable only on the UI
  thread of execution.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes a stock label and stock radio-button
  controls into two nested groups.
- **Padding**: Component does not use the shared row-composition helper
  its sibling rows use (no spacer, no forced content-hugging priorities).
  The outer group ([label, controls group]) is vertical, aligned to its
  leading edge, with spacing set to the layout system's standard row
  spacing (8pt). The controls group itself uses the same 8pt spacing,
  applied between each radio button along whichever axis it is laid out
  on. The outer group's top/leading/trailing/bottom edges are pinned
  directly to the component's edges with no additional constant, so the
  component contributes 0pt of its own outer padding beyond that internal
  8pt spacing.
- **Font**: The heading label uses the button text role, resolving to
  13pt, medium weight, proportional system font, scaling with the active
  theme's size scale and repainting automatically on a theme change. Each
  radio button's own title text, by contrast, comes from the platform's
  stock radio-button factory, not from the app's themed label — it renders
  in the platform's native control font and does not participate in the
  app's theme size-scale or repaint-on-theme-change path the heading label
  uses.
- **Background**: None (transparent) — the heading label draws no
  background or border of its own; neither the view nor either group sets
  a background color of its own. Each radio button's background is the
  platform's native, unthemed rendering.
- **Foreground/Text**: The heading label (`.primaryText` role) resolves to
  the active theme's foreground color at full strength, recomputed live on
  a theme change. Each radio button's title text color is the platform's
  own system rendering; this component sets no color on any radio button.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in this component.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in this component.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in source; sizing is governed entirely by the label's
  and each radio button's own intrinsic content size, the two groups' 8pt
  spacing, and the outer group's edge pinning.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; each radio button's selected state reflects whether its paired choice value equals the view model's value. |
| Selected (per button) | On, drawn as the platform's system filled-radio-dot appearance; set on init, on a user click that changes the value, and on any external change-notification that resolves to that choice. |
| Unselected (per button) | Off, drawn as the platform's system empty-radio-circle appearance; set on init and re-synced for every button whose paired value does not equal the view model's value. |
| Pressed | Not styled by this component; the platform's own mouse-down/press visual for a radio-type button is its default rendering, not custom to this component. |
| Disabled | Not implemented in this component; the enabled state is never read or set on the label or any radio button in source. A caller may set an individual button's enabled state directly (the array elements are mutable references even though the array property itself is read-only from outside), at which point the platform's native disabled dimming applies to that one button. |
| Focused | Not styled by this component; any focus ring when a button is tabbed to is the platform's own native focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized beyond the platform's own defaults — no
  explicit accessibility role override appears anywhere in source. Each
  radio button produced by the platform's own factory carries the
  platform's built-in radio-button accessibility role and reports its own
  visible title text (the choice's label) as its accessible name
  automatically — unlike a bare, title-less control, each button here is
  already individually named.
- **Label requirements**: Not implemented in source. Source sets no
  accessibility API at all on the label, the controls group, or any radio
  button — no accessible-name link, no accessibility group role, no child
  linkage tying the heading label (e.g. "Theme") to the set of radio
  buttons beneath it as one named group. This is confirmed by comparison
  with the checkbox row, a sibling row, which does link its single
  control's accessible name to its label; a screen reader has no
  source-declared link between the heading's text and the radio-button
  group, so each button's own visible title is the only accessible name
  it reports.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself in source
  (see States); a selection change is announced by the platform's own
  native accessibility value reporting when the selected state changes,
  which this component does not override.
- **Minimum tap target**: Not applicable — this is a pointer/
  trackpad-driven control composition (no touch input path in source); the
  44×44pt minimum is touch guidance, not a pointer-interface requirement.
  This component sets no reduced control size on any radio button, so each
  keeps the platform's regular system click-target metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The heading label text color resolves from the active theme's `.primaryText` role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this component's definition — settled by a theme-level contrast audit of `.primaryText` against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| radio-button-choice-view-001 | arranges-heading-above-controls-stack | Construct the component with any view model | The label and the controls group are the only two arranged elements of a single outer group that is pinned to the component's edges, with the label first |
| radio-button-choice-view-002 | builds-one-radio-button-per-choice | View model's choices has 3 entries with labels "A", "B", "C" | After init, there are 3 radio buttons and their titles == "A", "B", "C", in that order |
| radio-button-choice-view-003 | lays-out-controls-along-axis | Construct with axis: horizontal | The controls group's orientation is horizontal and every radio button is an arranged element of that group |
| radio-button-choice-view-004 | aligns-controls-stack-by-axis | Construct with axis: vertical (default) | The controls group aligns along its leading edge |
| radio-button-choice-view-005 | aligns-controls-stack-by-axis | Construct with axis: horizontal | The controls group aligns along a shared first baseline |
| radio-button-choice-view-006 | spaces-stacks-by-row-spacing | Construct the component | Both the outer group's spacing and the controls group's spacing equal the layout system's standard row spacing (8pt) |
| radio-button-choice-view-007 | initializes-from-view-model | View model's title = "Theme", choices = [(label: "Light", value: .light), (label: "Dark", value: .dark)], value = .dark | After init, the label's text == "Theme", the button paired with .dark is selected, the button paired with .light is not |
| radio-button-choice-view-008 | commits-radio-selection | View model's value == the first choice's value; trigger the selection action on the second radio button | The view model's value == the second choice's value after the call |
| radio-button-choice-view-009 | skips-redundant-commits | View model's value == the first choice's value; trigger the selection action on the first radio button (same value) | No write to the view model's value is recorded (e.g. a spy wrapping the view model that counts value-writes/notifications reports zero additional writes after the call) |
| radio-button-choice-view-010 | ignores-unmatched-sender | Trigger the selection action with a control instance that is not one of the component's radio buttons | The view model's value is unchanged; no crash occurs |
| radio-button-choice-view-011 | syncs-on-external-change | After construction, externally change the view model's title and value to a value present in the choices, then invoke its change-notification callback directly | The label's text updates to the new title, and exactly the radio button paired with the new value is selected while every other button is not |
| radio-button-choice-view-012 | syncs-on-external-change, commits-radio-selection | Click the second radio button (currently unselected, paired value differs from the first choice's value); then, on a later turn, the view model delivers the accepted write and its change-notification callback fires | Synchronously after the click, the view model's value == the second choice's value (per commits-radio-selection); after the callback fires, the second button is selected and every other button is not |
| radio-button-choice-view-013 | syncs-on-external-change, commits-radio-selection | Click the second radio button; before the next turn, an intermediary rejects/transforms the write so the view model's value ends up equal to the first choice's value instead; the change-notification callback then fires with that value | After the callback fires, the sync pass overrides the native click toggle: the first button is selected and the second is not, matching the actual view-model value rather than the clicked button |
| radio-button-choice-view-014 | exposes-constituent-views | Construct the component, then access the label and radio-buttons properties from outside the type | Both properties are accessible and return the same instances built during init; the radio-buttons list has no public setter |
| radio-button-choice-view-017 | confines-to-ui-thread | Attempt to construct or mutate the component from off the UI thread | This is a static/compile-time check, not a runtime conformance test, on platforms that enforce it statically — see Platform Notes |

## Edge Cases

- Null/empty input: The view model is a non-optional, required constructor
  parameter, so a missing value is not possible; the component provides,
  and needs, no nil-handling path for its one required initializer
  parameter.
- Boundary values — empty choices: When the view model's choices are
  empty, no radio buttons are created; the controls group ends up with
  zero arranged elements. The sync pass also has nothing to iterate. No
  crash occurs; the row renders only its heading label. Source performs no
  guard against, or special-casing for, an empty choices list.
- Boundary values — single choice: When the view model has exactly one
  choice, exactly one radio button is created. Per the platform's own
  radio-button behavior, once that button is selected (either at init,
  from a sync pass, or by a user click) it cannot be deselected back to
  "no selection" by clicking it again — a radio-type control has no
  user-driven path back to unselected once selected, and source never
  deselects it from anywhere except a sync pass that finds a different
  choice's value equal to the view model's value.
- Boundary values — current value absent from choices: The sync pass
  performs the selected/not-selected comparison independently for every
  button, so a view-model value matching none of them leaves every radio
  button unselected; source performs no fallback selection and no "at
  least one must be selected" invariant.
- Concurrent access: Not applicable — the component is confined to a
  single execution context (**confines-to-ui-thread**) and its value type
  is required to be safely shareable across contexts, so all construction
  and mutation is serialized to that context.
- Error states: Not applicable — every operation in this component (each
  control's selection action and the committed write) is a synchronous,
  non-throwing call; no error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- Overwritten external observer: The view model's change-notification
  callback is a single property. This component's initializer
  unconditionally assigns its own sync handler, replacing whatever handler
  (if any) was previously registered on that view model instance (see
  Design Decisions for this as a known limitation).
- Native mutual exclusion races the observer round trip: The platform's
  own radio-type control configures each button so that multiple such
  buttons sharing the same immediate parent group natively enforce mutual
  exclusivity — clicking one turns off its siblings in that group
  synchronously, as part of the click, before the component's own
  selection handler even fires. The view model's change-notification
  callback (which drives the sync pass) is delivered on a later turn, not
  synchronously with the write (per the underlying observer's own
  documented dispatch behavior). Between the click and that later turn,
  the visually-selected button is the one the platform toggled natively,
  not one this component set directly; the later sync pass is
  authoritative and will override that native toggle if the view model's
  value does not end up matching it (e.g., another party rejects or
  transforms the write before it reaches the view model).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | choice view model | — (required) | Supplies the row's title, the ordered choices list, and the current value; receives committed radio-button changes. The initializer also overwrites this view model's change-notification callback with the component's own sync handler (see Edge Cases). A choice's optional symbol-image field is accepted by the type but never read by this component (see Overview). |
| `axis` | layout orientation | vertical | Sets the controls group's orientation and, through a vertical/non-vertical branch, its alignment. Has no effect on the outer [label, controls group] group, which is always vertical. |

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in source.

## Localization

Not applicable: the component defines no user-facing string literals of
its own. The heading text comes from the view model's title and each radio
button's title comes from the matching choice's label; both are values the
caller provides as plain text, so there is nothing for this component to
localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — source contains no animation or transition call; every state change is an instantaneous property assignment (the label's text, a button's selected state). |
| Increase Contrast | Not applicable — this component sets no custom color of its own on any radio button; the heading label's color comes from the theme's `.primaryText` role, and each radio button's dot/track colors follow the platform's default rendering, which tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable — the selected choice is communicated through the platform's own filled-vs-empty radio-dot iconography and each button's own visible title text, not through a color-only signal introduced by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in this component; the row always renders once constructed.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by the view model and reports
  radio selections back through it.
- **Storage**: Not applicable — source performs no read/write to disk, or
  any other persistent store; persistence, if any, is owned by the view
  model layer, which is not part of this component.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own child
  views (the label, the radio buttons, the two groups) and its reference
  to the view model for its own lifetime; it persists nothing beyond
  that.

## Logging

Not applicable: this component contains no logging call (no print, log,
or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: `Picker("", selection: $value) { ForEach(choices) { Text($0
  .label).tag($0.value) } }.pickerStyle(.radioGroup).labelsHidden()`,
  preceded by its own `Text(viewModel.title)` heading, is the closest native
  analog — `.radioGroup` is a macOS-only `Picker` style that renders one
  native radio button per case, matching `builds-one-radio-button-per-choice`
  directly. SwiftUI has no first-class axis toggle on `.radioGroup`, so
  matching `axis` requires composing custom `Toggle`-styled radio rows inside
  a `VStack`/`HStack` chosen by `axis`, rather than relying on the built-in
  style, when a horizontal layout is required. Commit the selection to the
  backing view model from the `Binding`'s setter with an equality guard,
  mirroring skips-redundant-commits.
- **Compose**: There is no Material 3 "radio group" composable; build a
  `Column`/`Row` (chosen by axis) of `RadioButton(selected = choice.value ==
  value, onClick = { ... })` each paired with a trailing `Text(choice.label)`,
  wrapped in `Modifier.selectableGroup()` on the container — the Compose
  analog of the group-to-heading accessibility linkage this component's
  source does not implement (see Accessibility). Guard the write with an
  equality check before calling the parent's setter, mirroring
  skips-redundant-commits.
- **React/Web**: A `<fieldset>` with a `<legend>{title}</legend>` — the
  direct web analog of the heading-to-group linkage this component's source
  does not implement (see Accessibility) — wrapping a flex container (`flex-direction: column` or
  `row` per axis) of `<input type="radio" name={groupName} value=...
  checked={...}>` elements, each paired with its own `<label>` set from
  `choice.label`. Giving every input the same `name` attribute is the web's
  own native mutual-exclusivity mechanism, the direct analog of the source
  platform's same-parent radio exclusivity noted in Edge Cases. Commit the
  new value on each input's `onChange`, comparing against the previous
  value first to mirror skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/RadioButtonChoiceView.swift`.
  A macOS-only (`import AppKit`), generic-over-`Value` `NSView` subclass,
  isolated to the main actor via Swift's `@MainActor`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes a `ThemedLabel` heading (via `ComposableSettings.makeRowLabel`)
  and, for each choice, one native `.radio`-type `NSButton` built from
  `NSButton(radioButtonWithTitle:target:action:)` wired to the
  `radioChanged(_:)` action, into two nested `NSStackView`s
  (`controlsStack.orientation`/`.alignment` driven by `axis`) pinned via
  `pinToEdges` — unlike its sibling row views, it does not use
  `ComposableSettings.makeRow`. It supports construction only through the
  `viewModel`-taking initializer: both `init?(coder:)` and the frame-only
  `init(frame:)` trigger a fatal error rather than producing an instance
  (the frame-only override's message is the truncated string `init(frame
  frameRect: NSRect`, missing its closing parenthesis — see Design
  Decisions). Selection state is AppKit's `NSButton.state`
  (`.on`/`.off`); the `radioButtons` array is exposed as `public
  private(set)` so callers can read but not replace it. There is no UIKit
  code path in source; UIKit has no native radio-button control, so a port
  would need `UIButton`s manually toggled in a target/action handler
  (clearing every sibling's selected state before setting the tapped one),
  or a `UISegmentedControl`/checkmarked table rows as an alternate native
  composition.
- **WinUI 3** (the reason this recipe exists): Use the
  `Microsoft.UI.Xaml.Controls.RadioButtons` control directly — it is a
  near 1:1 analog of this component: its `Orientation` property
  (`Vertical`/`Horizontal`) is the direct WinUI equivalent of the `axis`
  parameter (mirroring lays-out-controls-along-axis and
  aligns-controls-stack-by-axis in one property, since `RadioButtons`
  handles the alignment difference between orientations internally), and its
  `Header` property is the direct analog of this component's heading
  `label` — critically, `RadioButtons.Header` is exposed to `UIA` as the
  group's accessible name automatically, which is the exact linkage this
  component's own source leaves unimplemented (see Accessibility). Bind
  `ItemsSource="{x:Bind Choices}"` with
  `DisplayMemberPath="Label"`, and `SelectedItem="{x:Bind SelectedChoice,
  Mode=TwoWay}"` through a property setter that skips the assignment (and so
  skips raising `INotifyPropertyChanged`) when the incoming value already
  equals the current one, mirroring skips-redundant-commits. `RadioButtons`'
  built-in `SelectionChanged` event is the WinUI analog of `radioChanged(_:)`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/RadioButtonChoiceView.swift` |

## Design Decisions

- **Decision**: Compose two nested vertical/axis-driven groups (an outer
  vertical group of [label, controls group] plus an inner controls group)
  rather than using the single horizontal [label, spacer, control] row
  layout every other row in this family uses (AppKit/UIKit source: not
  calling `ComposableSettings.makeRow`).
  **Rationale**: a multi-choice radio group needs to grow along its own axis
  independent of the heading, unlike a single trailing control (a switch,
  slider, or popup) that fits beside the label in one row's height; source
  never calls the shared row-composition helper anywhere in this file.
  **Approved**: pending
- **Decision**: Switch the controls group's alignment between leading
  (vertical axis) and first baseline (horizontal axis) via the source's own
  branch, rather than using one alignment for both orientations.
  **Rationale**: stacked buttons of possibly different widths want a common
  left edge when arranged vertically, while buttons placed side by side want
  their title text sitting on one shared line, which first-baseline
  alignment provides and leading alignment does not.
  **Approved**: pending
- **Decision**: Build each choice's control from the platform's stock
  radio-button factory (AppKit/UIKit source: `NSButton(radioButtonWithTitle:)`)
  rather than pairing a bare radio control with a separate themed label per
  choice, the way the heading label is built.
  **Rationale**: this factory is the standard platform mechanism that
  bundles a radio control and its title into one control; source builds no
  second themed label per row, at the traceable cost that per-choice titles
  do not follow the app's theme size-scale or repaint-on-theme-change path
  the way the heading label does (see Appearance).
  **Approved**: pending
- **Decision**: Leave every radio button unselected when the view model's
  value matches no choice's value, rather than falling back to a default
  selection.
  **Rationale**: the sync pass's selected/not-selected comparison is
  evaluated independently per button with no fallback branch in source; the
  component makes no attempt to guarantee "exactly one selected" when the
  view model's value is not representable by any choice.
  **Approved**: pending
- **Decision**: Both the coder-based initializer and the frame-only
  initializer trigger a fatal error (AppKit/UIKit source: `init(coder:)`,
  `init(frame:)`), leaving the view-model-taking initializer as the only
  usable one.
  **Rationale**: The view has no meaningful default state — it cannot
  render a title, choice set, or value without a view model — so both
  inherited initializers that could construct it without one are
  intentionally disabled.
  **Approved**: pending
  Known defect: the frame-only override's fatal-error message is the
  truncated string `"init(frame frameRect: NSRect"` (missing its closing
  parenthesis); it is reproduced here exactly as written in source, not
  corrected.
- **Decision**: The initializer unconditionally assigns the view model's
  change-notification callback, replacing whatever handler (if any) was
  previously registered on that view model instance, rather than composing
  with an existing handler.
  **Rationale**: that callback is a single property; a plain assignment is
  the simplest way to route external changes into the component's sync
  pass, at the traceable cost that another party's previously registered
  callback on the same view-model instance is silently discarded (see Edge
  Cases).
  **Approved**: pending
- **Decision**: Leave the heading label with no accessibility group or
  title-link to the radio buttons beneath it, unlike the sibling checkbox
  row, which does link its single control to its label.
  **Rationale**: Not yet decided; see Accessibility (Label requirements) for
  what the source does and does not implement. The WinUI, Compose, and web
  notes already assume a named accessibility group as the eventual target
  for this component.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference` and `platform-design-language` pass because every
control is a stock AppKit `NSButton`/`NSTextField`; `keyboard-navigable` is
`partial` because source sets no explicit key-view-loop or Full Keyboard
Access handling of its own (only AppKit's default `NSControl` tab behavior);
`semantic-markup` stays `partial` because Accessibility documents that
source implements no accessibility group linkage between the heading label
and the radio buttons beneath it (see Label requirements);
`idempotent-operations` passes on `skips-redundant-commits`; and
`separation-of-concerns` passes because Behavioral Requirements now state
platform-neutral behavior, with the AppKit-specific mechanics confined to
Platform Notes.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded Behavioral Requirements as platform-neutral behavior and moved the AppKit mechanics (NSButton/NSStackView factories, `.on`/`.off` state, `private(set)`, `@MainActor`) into the AppKit/UIKit platform note; replaced the unsupported "copied forward" guess in the fatal-error Design Decision with a factual known-defect note; reformatted all Design Decisions into the three-line bold form and added decisions for the onChange-overwrite limitation and the open accessibility group-heading question; removed false MUST framing from descriptive Edge Cases and pointed the onChange-overwrite edge case at its Design Decision; downgraded the `keyboard-navigable` compliance row to partial and added the compliance status sentence; renumbered the conformance test vectors sequentially, reworded vector 009 (formerly 008) to assert "no write is recorded", marked vector 017 (formerly 014) as a static/compile-time check, and added vectors for the click-to-async-`syncSelection()` round trip including a rejected-write case; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
