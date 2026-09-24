---
id: 7774cbd3-4883-43f0-aef0-f49a29389b98
title: RadioButtonChoiceView
domain: agentictoolkit://recipes/radio-button-choice-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row stacking a title label above a set of native
  NSButton radio buttons, one per ChoiceViewModel choice.
platforms:
- swift
- macos
tags:
- settings
- form-control
- choice
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/choice-slider-view
references: []
approved-by: ''
approved-date: ''
---

# RadioButtonChoiceView

## Overview

`RadioButtonChoiceView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/RadioButtonChoiceView.swift`):
a title label sitting above a stack of native `NSButton` radio buttons, one
per entry in a `ChoiceViewModel<Value>`'s `choices` array, each button's own
title text set to that choice's `label`. Unlike its sibling row views over the
same `ChoiceViewModel` (`ChoiceSliderView`, `PopupMenuChoiceView`),
`RadioButtonChoiceView` does not use `ComposableSettings.makeRow`'s single
horizontal `[label, spacer, control]` layout; it composes two nested
`NSStackView`s instead — an outer vertical stack of `[label, controlsStack]`,
and an inner `controlsStack` holding the radio buttons themselves, oriented by
the constructor's `axis` parameter (`.vertical` by default). The row is driven
by `ChoiceViewModel<Value>`: the view reflects the view model's title/value on
construction and whenever the view model reports an external change, and it
writes the user's radio-button selection back into the view model's
`settingObserver`. `ChoiceViewModel.Choice` also carries an optional
`imageSystemName`, but `RadioButtonChoiceView` never reads that field — only
`PopupMenuChoiceView`, a sibling row over the same view model, renders it.

## Behavioral Requirements

- **arranges-heading-above-controls-stack**: Component MUST arrange the title
  label above a `controlsStack` of radio buttons in a single outer, vertical
  `NSStackView` (`[label, controlsStack]`), and MUST pin that outer stack to
  the edges of the view.
- **builds-one-radio-button-per-choice**: Component MUST create one `NSButton`
  configured as a radio button (`NSButton(radioButtonWithTitle:target:action:)`)
  for each entry in `viewModel.choices`, in the same order, using that
  choice's `label` as the button's own title text.
- **lays-out-controls-along-axis**: Component MUST arrange the created radio
  buttons, in order, inside a single `NSStackView` (`controlsStack`) whose
  `orientation` is set to the constructor's `axis` parameter (default
  `.vertical`).
- **aligns-controls-stack-by-axis**: Component MUST set `controlsStack`'s
  `alignment` to `.leading` when `axis` is `.vertical`, and to
  `.firstBaseline` when `axis` is not `.vertical`.
- **spaces-stacks-by-row-spacing**: Component MUST set both the outer stack's
  and `controlsStack`'s `spacing` to `SettingsLayout.default[.rowSpacing]`.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title`, and set each
  radio button's `state` to `.on` when its associated choice's `value` equals
  `viewModel.value`, and to `.off` otherwise.
- **commits-radio-selection**: Component MUST write the value paired with the
  radio button that fired the action into `viewModel.settingObserver.value`
  whenever that value differs from the current `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the firing button's paired value
  equals the current `settingObserver.value`.
- **ignores-unmatched-sender**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the button that fired the action is
  not present in the component's recorded button-value pairs.
- **syncs-on-external-change**: Component MUST re-set the label's text from
  `viewModel.title`, and re-set every radio button's `state` to reflect
  `viewModel.value`, whenever `viewModel.onChange` fires.
- **exposes-constituent-views**: Component MUST expose `label` and
  `radioButtons` as public, directly-accessible properties; `radioButtons`
  MUST NOT be publicly replaceable as a whole (`private(set)`).
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes a stock `NSTextField` label and stock
  `NSButton` radio buttons into two nested stacks.
- **Padding**: Component does not use `ComposableSettings.makeRow` (no
  spacer, no forced content-hugging priorities). The outer `NSStackView`
  (`[label, controlsStack]`) is vertical, `alignment = .leading`, `spacing =
  SettingsLayout.default[.rowSpacing]` = 8pt. `controlsStack` itself uses the
  same 8pt `spacing`, applied between each radio button along whichever axis
  it is laid out on. `pinToEdges` pins the outer stack's
  top/leading/trailing/bottom directly to `RadioButtonChoiceView`'s edges
  with no additional constant, so the component contributes 0pt of its own
  outer padding beyond that internal 8pt spacing.
- **Font**: The heading label (`ComposableSettings.makeRowLabel`, via
  `Self.createLabel(title:)`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight, proportional
  system font, scaling with the active theme's `sizeScale` and repainting
  automatically on a theme change (`ThemePaletteObserver`). Each radio
  button's own title text, by contrast, comes from AppKit's stock
  `NSButton(radioButtonWithTitle:)` factory, not from `ThemedLabel` — it
  renders in AppKit's native control font and does not participate in the
  app's theme `sizeScale` or repaint-on-theme-change path the heading label
  uses.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, `isBezeled = false` on the
  heading label; neither `RadioButtonChoiceView` nor either `NSStackView`
  sets `wantsLayer` or a background color of its own. Each radio button's
  background is AppKit's native, unthemed `NSButton` rendering.
- **Foreground/Text**: The heading label (`role: .primaryText`) resolves to
  the active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change. Each radio button's title
  text color is AppKit's own system rendering; `RadioButtonChoiceView` sets
  no color on any `radioButtons` element.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `RadioButtonChoiceView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `RadioButtonChoiceView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `RadioButtonChoiceView.swift`; sizing is governed
  entirely by the label's and each `NSButton`'s own intrinsic content size,
  the two stacks' 8pt spacing, and `pinToEdges`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; each radio button's `state` reflects whether its paired choice value equals `viewModel.value`. |
| Selected (per button) | `state == .on`, drawn as `NSButton`'s system filled-radio-dot appearance; set on init, on a user click that changes the value, and on any external `viewModel.onChange` that resolves to that choice. |
| Unselected (per button) | `state == .off`, drawn as `NSButton`'s system empty-radio-circle appearance; set on init and re-synced by `syncSelection()` for every button whose paired value does not equal `viewModel.value`. |
| Pressed | Not styled by this file; `NSButton`'s own mouse-down/press visual for a radio-type button is AppKit's default rendering, not custom to this file. |
| Disabled | Not implemented in `RadioButtonChoiceView`; `isEnabled` is never read or set on `label` or any element of `radioButtons` in source. A caller may set an individual `radioButtons[i].isEnabled` directly (the array elements are mutable `NSButton` references even though the array property itself is `private(set)`), at which point `NSButton`'s native disabled dimming applies to that one button. |
| Focused | Not styled by `RadioButtonChoiceView`; any focus ring when a button is tabbed to is `NSButton`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized beyond AppKit's own defaults — no
  `setAccessibilityRole` call appears anywhere in source. Each `NSButton`
  produced by `radioButtonWithTitle:target:action:` carries AppKit's built-in
  radio-button accessibility role and reports its own visible title text
  (the choice's `label`) as its accessible name automatically — unlike a
  bare, title-less control, each button here is already individually named.
- **Label requirements**: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. Source sets no accessibility API at all on `label`,
  `controlsStack`, or any `radioButtons` element — no
  `setAccessibilityTitleUIElement`, no accessibility group role, no
  `accessibilityChildren` linkage tying the heading `label` (e.g. "Theme")
  to the set of radio buttons beneath it as one named group. This is
  confirmed by comparison with `CheckboxView`, a sibling row, which does
  call `toggle.setAccessibilityTitleUIElement(self.label)` for its single
  control. What is missing: whether VoiceOver announces the heading's text
  as part of each radio button's context (e.g. "Theme, Light, radio button,
  1 of 3") or only the individual button title with no group name. What
  would settle it: a VoiceOver pass over an instantiated row, or an explicit
  decision to expose `controlsStack` (or `self`) as an
  `NSAccessibilityGroupRole`/radio-group element whose name derives from
  `label`.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself in source (see
  States); a selection change is announced by `NSButton`'s own native
  accessibility value reporting when `state` changes, which
  `RadioButtonChoiceView` does not override.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement. `RadioButtonChoiceView` sets no
  `controlSize` on any `radioButtons` element, so each keeps `NSButton`'s
  regular system click-target metrics.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| radio-button-choice-view-001 | arranges-heading-above-controls-stack | Construct `RadioButtonChoiceView` with any `viewModel` | `label` and `controlsStack` are the only two arranged subviews of a single outer stack that is pinned to the component's edges, with `label` first |
| radio-button-choice-view-002 | builds-one-radio-button-per-choice | `viewModel.choices` has 3 entries with labels `"A"`, `"B"`, `"C"` | After init, `radioButtons.count == 3` and `radioButtons[0].title == "A"`, `radioButtons[1].title == "B"`, `radioButtons[2].title == "C"`, in that order |
| radio-button-choice-view-003 | lays-out-controls-along-axis | Construct with `axis: .horizontal` | `controlsStack.orientation == .horizontal` and every `radioButtons` element is an arranged subview of `controlsStack` |
| radio-button-choice-view-004 | aligns-controls-stack-by-axis | Construct with `axis: .vertical` (default) | `controlsStack.alignment == .leading` |
| radio-button-choice-view-004b | aligns-controls-stack-by-axis | Construct with `axis: .horizontal` | `controlsStack.alignment == .firstBaseline` |
| radio-button-choice-view-005 | spaces-stacks-by-row-spacing | Construct the component | Both the outer stack's `spacing` and `controlsStack.spacing` equal `SettingsLayout.default[.rowSpacing]` (8pt) |
| radio-button-choice-view-006 | initializes-from-view-model | `viewModel.title = "Theme"`, `viewModel.choices = [(label: "Light", value: .light), (label: "Dark", value: .dark)]`, `viewModel.value = .dark` | After init, `label.stringValue == "Theme"`, the button paired with `.dark` has `state == .on`, the button paired with `.light` has `state == .off` |
| radio-button-choice-view-007 | commits-radio-selection | `viewModel.settingObserver.value == choices[0].value`; invoke `radioChanged(radioButtons[1])` | `viewModel.settingObserver.value == choices[1].value` after the call |
| radio-button-choice-view-008 | skips-redundant-commits | `viewModel.settingObserver.value == choices[0].value`; invoke `radioChanged(radioButtons[0])` (same value) | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| radio-button-choice-view-009 | ignores-unmatched-sender | Invoke `radioChanged(_:)` with an `NSButton` instance that is not one of `radioButtons` | `viewModel.settingObserver.value` is unchanged; no crash occurs |
| radio-button-choice-view-010 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value` to a value present in `choices`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` updates to the new title, and exactly the radio button paired with `newValue` has `state == .on` while every other button has `state == .off` |
| radio-button-choice-view-011 | exposes-constituent-views | Construct the component, then access `.label` and `.radioButtons` from outside the type | Both properties are accessible and return the same `NSTextField`/`[NSButton]` instances built during init; `radioButtons` has no public setter |
| radio-button-choice-view-012 | requires-designated-initializer | Attempt `RadioButtonChoiceView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| radio-button-choice-view-013 | rejects-frame-only-initialization | Attempt `RadioButtonChoiceView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| radio-button-choice-view-014 | confines-to-main-actor | Attempt to construct or mutate a `RadioButtonChoiceView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- Null/empty input: `viewModel` (`ChoiceViewModel<Value>`) is a non-optional,
  typed constructor parameter; Swift's type system rules out `nil`. This is
  a MUST: the component provides, and needs, no nil-handling path for its
  one required initializer parameter.
- Boundary values — empty `choices`: when `viewModel.choices.isEmpty`, the
  `for choice in viewModel.choices` loop never runs, `radioButtons` and
  `buttonValues` stay empty, and `NSStackView(views: [])` produces a
  zero-arranged-subview `controlsStack`. `syncSelection()`'s loop over
  `buttonValues` also never runs. No crash occurs; the row renders only its
  heading label. This is a MUST: source performs no guard against, or
  special-casing for, an empty `choices` array.
- Boundary values — single choice: when `viewModel.choices.count == 1`,
  exactly one radio button is created. Per AppKit's own radio-button
  behavior, once that button is selected (either at init, from
  `syncSelection()`, or by a user click) it cannot be deselected back to "no
  selection" by clicking it again — a `.radio`-type `NSButton` has no
  user-driven path back to `.off` once `.on`, and source never sets `.off`
  from anywhere except a `syncSelection()` pass that finds a *different*
  choice's value equal to `viewModel.value`.
- Boundary values — `viewModel.value` absent from `choices`: `syncSelection()`
  performs the `(value == current) ? .on : .off` comparison independently
  for every button, so a `viewModel.value` matching none of them leaves
  every radio button `.off`; source performs no fallback selection and no
  "at least one must be selected" invariant.
- Concurrent access: Not applicable — the class is `@MainActor` and `Value`
  is constrained to `Sendable`, so all construction and mutation is
  serialized to the main actor (see confines-to-main-actor).
- Error states: Not applicable — every operation in this file (each button's
  target-action and the `settingObserver.value` write) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ChoiceViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `RadioButtonChoiceView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.syncSelection() }`,
  replacing whatever handler (if any) was previously registered on that
  `ChoiceViewModel` instance. This is a MUST-level, source-traceable
  consequence of plain closure-property assignment: the component MUST NOT
  be assumed to coexist with another `onChange` observer already registered
  on the same view model instance.
- Native mutual exclusion races the observer round trip: `NSButton(
  radioButtonWithTitle:)` configures each button with AppKit's `.radio`
  button type; multiple such buttons sharing the same immediate superview
  (here, `controlsStack`) natively enforce mutual exclusivity — clicking one
  turns off its siblings in that stack synchronously, as part of the click,
  before `radioChanged(_:)`'s action even fires. `UserSettingObserver`
  delivers `viewModel.onChange` (which drives `syncSelection()`) on a later
  main-queue turn, not synchronously with the write (per its own documented
  `.receive(on: DispatchQueue.main)` behavior). Between the click and that
  later turn, the visually-selected button is the one AppKit toggled
  natively, not one `RadioButtonChoiceView` set directly; `syncSelection()`'s
  later pass is authoritative and will override that native toggle if
  `viewModel.value` does not end up matching it (e.g., another party rejects
  or transforms the write before it reaches `settingObserver.value`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ChoiceViewModel<Value>` | — (required) | Supplies the row's title, the ordered `choices` list, and the current value; receives committed radio-button changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `syncSelection` handler (see Edge Cases). `Choice.imageSystemName` is accepted by the type but never read by `RadioButtonChoiceView` (see Overview). |
| `axis` | `NSUserInterfaceLayoutOrientation` | `.vertical` | Sets `controlsStack.orientation` and, through the `(axis == .vertical) ? .leading : .firstBaseline` ternary, `controlsStack.alignment`. Has no effect on the outer `[label, controlsStack]` stack, which is always vertical. |

## Deep Linking

Not applicable: `RadioButtonChoiceView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `RadioButtonChoiceView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its own.
The heading text comes from `viewModel.title` and each radio button's title
comes from the matching `Choice.label`; both are values the caller provides
as plain `String`s to AppKit APIs (`NSTextField`/`NSButton`), so there is
nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `button.state`). |
| Increase Contrast | Not applicable — `RadioButtonChoiceView.swift` sets no custom `NSColor` on any `radioButtons` element; the heading label's color comes from the theme's `.primaryText` role, and `NSButton`'s radio-dot/track colors follow AppKit's default rendering, which tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable — the selected choice is communicated through `NSButton`'s own filled-vs-empty radio-dot iconography and each button's own visible title text, not through a color-only signal introduced by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `RadioButtonChoiceView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `RadioButtonChoiceView.swift` contains no analytics or
telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only displays a value supplied by `viewModel` and reports radio
  selections back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `ChoiceViewModel`/`settingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `radioButtons`, the two `NSStackView`s) and its reference to
  `viewModel` for its own lifetime; it persists nothing beyond that.

## Logging

Not applicable: `RadioButtonChoiceView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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
  direct web analog of the heading-to-group linkage that is the open question
  in Accessibility — wrapping a flex container (`flex-direction: column` or
  `row` per axis) of `<input type="radio" name={groupName} value=...
  checked={...}>` elements, each paired with its own `<label>` set from
  `choice.label`. Giving every input the same `name` attribute is the web's
  own native mutual-exclusivity mechanism, the direct analog of AppKit's
  same-superview radio exclusivity noted in Edge Cases. Commit the new value
  on each input's `onChange`, comparing against the previous value first to
  mirror skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/RadioButtonChoiceView.swift`.
  A macOS-only (`import AppKit`), generic-over-`Value` `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, conforming to
  `SettingsViewProtocol`. It composes a `ThemedLabel` heading (via
  `ComposableSettings.makeRowLabel`) and one native `.radio`-type `NSButton`
  per choice into two nested `NSStackView`s and `pinToEdges` — unlike its
  sibling row views, it does not use `ComposableSettings.makeRow`. There is
  no UIKit code path in source; UIKit has no native radio-button control, so
  a port would need `UIButton`s manually toggled in a target/action handler
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
  component's own source leaves unimplemented (see the open question in
  Accessibility). Bind `ItemsSource="{x:Bind Choices}"` with
  `DisplayMemberPath="Label"`, and `SelectedItem="{x:Bind SelectedChoice,
  Mode=TwoWay}"` through a property setter that skips the assignment (and so
  skips raising `INotifyPropertyChanged`) when the incoming value already
  equals the current one, mirroring skips-redundant-commits. `RadioButtons`'
  built-in `SelectionChanged` event is the WinUI analog of `radioChanged(_:)`.

## Design Decisions

- Decision: Compose two nested `NSStackView`s (an outer vertical
  `[label, controlsStack]` plus an inner `controlsStack`) rather than using
  `ComposableSettings.makeRow`'s single horizontal `[label, spacer,
  control...]` layout that every other `ComposableSettings` row view uses.
  Rationale: a multi-choice radio group needs to grow along its own axis
  independent of the heading, unlike a single trailing control (a switch,
  slider, or popup) that fits beside the label in one row's height; source
  never calls `makeRow` anywhere in this file.
  Approved: pending
- Decision: Switch `controlsStack.alignment` between `.leading` (vertical
  axis) and `.firstBaseline` (horizontal axis) via the source's own
  ternary, rather than using one alignment for both orientations.
  Rationale: stacked buttons of possibly different widths want a common left
  edge when arranged vertically, while buttons placed side by side want
  their title text sitting on one shared line, which `.firstBaseline`
  provides and `.leading` does not.
  Approved: pending
- Decision: Build each choice's control from AppKit's stock
  `NSButton(radioButtonWithTitle:)` factory rather than pairing a bare radio
  `NSButton` with a separate `ThemedLabel` per choice, the way the heading
  label is built.
  Rationale: `radioButtonWithTitle:` is the standard AppKit factory that
  bundles a radio control and its title into one control; source builds no
  second `ThemedLabel` per row, at the traceable cost that per-choice titles
  do not follow the app's theme `sizeScale` or repaint-on-theme-change path
  the way the heading label does (see Appearance).
  Approved: pending
- Decision: Leave every radio button `.off` when `viewModel.value` matches no
  choice's `value`, rather than falling back to a default selection.
  Rationale: `syncSelection()`'s `(value == current) ? .on : .off` comparison
  is evaluated independently per button with no fallback branch in source;
  the component makes no attempt to guarantee "exactly one selected" when the
  view model's value is not representable by any choice.
  Approved: pending
- Decision: Both `init(coder:)` and the frame-only `init(frame:)` trigger a
  fatal error, leaving `init(viewModel:axis:)` as the only usable
  initializer; the frame-only override's message string is the identical,
  truncated `"init(frame frameRect: NSRect"` literal (missing its closing
  parenthesis) used by this file's sibling row views.
  Rationale: The view has no meaningful default state — it cannot render a
  title, choice set, or value without a `viewModel` — so both inherited
  `NSView` initializers that could construct it without one are
  intentionally disabled. The shared, truncated message text across sibling
  files indicates the string was copied forward from an earlier row view
  rather than authored fresh for this one; it is reproduced here as written
  rather than corrected, per source fidelity.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
