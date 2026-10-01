---
id: c0e95399-ddab-4445-a22a-566d07339f9b
title: Color Picker View
domain: agentictoolkit://cookbook/ui/settings/rows/color-picker-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a title label with a color-well control, syncing
  a caller-supplied color view model's color two-way.
platforms:
- swift
- macos
tags:
- settings
- form-control
- color
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/captioned-slider-view
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
- agentictoolkit://cookbook/ui/settings/rows/number-field-view
- agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view
references: []
approved-by: ''
approved-date: ''
---

# Color Picker View

## Overview

The Color Picker View is a settings row that pairs a title label with a
color-well control. Its title and color are driven by a caller-supplied
color view model: the view reflects the view model's title/color on
construction and whenever the view model reports an external change, and
it writes the user's color-well interactions back into the view model's
color.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the label and the color
  well into a single horizontal row, and MUST pin that row to all four
  edges of the view with no additional constant.
- **initializes-from-view-model**: Component MUST, during initialization,
  build the label from the view model's title and set the color well's
  color to the view model's color.
- **commits-color-value**: Component MUST set the view model's color to
  the color well's reported color every time the color well is changed,
  unconditionally, with no comparison against the current value.
- **delegates-color-clamping**: Component MUST NOT perform its own
  clamping or validation of the reported color before writing it to the
  view model's color; normalizing an out-of-gamut or malformed color is
  the color storage type's responsibility, one layer below this
  component.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  the view model's title and the color well's color to the view model's
  color whenever the view model reports an external change.
- **owns-on-change**: Component MUST assign its own handler to the view
  model's external-change notification during initialization,
  unconditionally replacing any handler already registered on that view
  model instance; callers MUST NOT share a single view model across more
  than one observer (for example, two instances of this component, or an
  instance of this component and another registered external-change
  handler), because constructing the later observer silently drops
  whichever handler was registered first.
- **exposes-constituent-views**: Component MUST expose the label and the
  color well as public, directly-accessible, read-only properties.
- **requires-view-model-at-construction**: Component MUST be constructible
  only with a view model supplied at construction time; construction paths
  that could produce an instance without one (e.g. a bare/default
  construction path or a serialization/decoding-based construction path)
  MUST be rejected (see Platform Notes for the mechanism the source uses).

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes a stock label and a stock color-well
  control into a row.
- **Padding**: The row inserts a flexible spacer between the label and the
  color well and sets the row's spacing to 8pt, which applies to the
  label-to-spacer gap; the spacer-to-color-well gap is explicitly zeroed,
  so the spacer's own width is the only thing between the label and the
  color well. The row is pinned directly to the component's edges with no
  additional constant, so the component contributes 0pt of its own outer
  padding beyond that internal 8pt / 0pt spacing.
- **Font**: The label (button text role) resolves to 13pt, medium weight,
  proportional system font, scaling with the active theme's size scale and
  repainting on a theme change. The color well has no text of its own —
  not applicable.
- **Background**: None (transparent) for the label — it draws no
  background, border, or bezel of its own — and neither the component nor
  the row container sets a background color of its own. The color well's
  swatch chrome is the platform's own default rendering, not customized in
  source.
- **Foreground/Text**: The label (primaryText color role) resolves to the
  active theme's foreground color at full strength, recomputed live on a
  theme change. The color well is not a text control; the color it
  displays is the edited value itself, not a foreground/text color, so
  "Foreground/Text" is not applicable to it.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in source; the color well's border is the platform's stock chrome, not
  custom to this file.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in source.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in source; sizing is governed entirely by the label's
  and the color well's own intrinsic sizes inside the row container.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; color well shows the view model's color. |
| Pressed | Not applicable / inherited: clicking the color well opens the system color panel through the platform's own default interaction; no custom presentation code exists in source. |
| Disabled | Not applicable: an enabled flag is never set on the color well or label in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the color well uses the platform's default focus-ring behavior when tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults — no
  custom accessibility-role or accessibility-element call appears in
  source. The color well and text elements each carry the platform's
  built-in accessibility role (color well, static text) automatically.
- **Label requirements**: The label and the color well are laid out as
  sibling elements in the same row, but source sets no accessible-name
  link (or equivalent) on the color well linking it to the label —
  confirmed by comparison with several sibling row controls in this
  system, which each link their control's accessible name to their label,
  but this component does not do so for the color well. The color well
  relies entirely on the platform's own default accessibility role, with
  no explicit, programmatic link from the color well to the row's title
  text.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-driven
  composition (no touch input path in source); a touch-target minimum is
  touch-interface guidance, not a pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| color-picker-view-001 | arranges-row-layout | Construct the component with any view model | The label and color well are arranged (with an internal spacer) in a single row that is pinned to the component's edges; no other layout container appears |
| color-picker-view-002 | initializes-from-view-model | View model title = "Accent", color = red | After init, the label reads "Accent" and the color well shows red |
| color-picker-view-003 | commits-color-value | Set the color well to blue and activate it | The view model's color is blue after the call |
| color-picker-view-004 | commits-color-value | Construct with a counting/spy view model stub whose color setter increments a call counter; set the color well to blue and activate it twice in a row with the same color | The setter's call counter increments on both invocations (the second, redundant-value write is not skipped) |
| color-picker-view-005 | syncs-on-external-change | After construction, externally change the view model's title and color, then trigger an external-change notification | The label and color well both update to reflect the new view-model state |
| color-picker-view-006 | exposes-constituent-views | Construct the component, then access its label and color-well properties from outside the type | Both properties are accessible and return the same instances built during init |
| color-picker-view-007 | requires-view-model-at-construction | Attempt construction via a bare/default construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| color-picker-view-008 | requires-view-model-at-construction | Attempt construction via a serialization/decoding-based construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| color-picker-view-009 | owns-on-change | Construct two instances of this component in turn against the same view model instance, then trigger an external-change notification | Only the second instance's label/color-well update; the first instance's handler was silently replaced and is never invoked |
| color-picker-view-010 | delegates-color-clamping | Set the color well to an out-of-gamut color and activate it | The component writes the reported color into the view model's color unchanged — no clamping call appears in source; any normalization happens inside the color storage type's initializer, one layer below |

## Edge Cases

- Null/empty input: the view model is a non-optional parameter; nil is
  ruled out by the platform's type system. The component provides, and
  needs, no nil-handling path for its one initializer parameter.
- Boundary values — out-of-range or out-of-gamut color: the component
  performs no clamping or validation of the reported color before writing
  it to the view model's color. Clamping happens one layer down: the view
  model's color setter converts the incoming color to the storage type,
  and that type's initializer clamps each channel to [0, 1] — so an
  out-of-gamut or malformed color is always normalized before it reaches
  storage, but that normalization is the storage type's behavior, not
  this component's. See **delegates-color-clamping**.
- Concurrent access: Not applicable — the component is confined to the UI
  thread, so all access is serialized to that thread; there is no code
  path by which two threads can mutate the view simultaneously.
- Error states: Not applicable — every operation in this file (the color
  well's activation and the view-model write) is a synchronous,
  non-throwing call; no error-producing path appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- Overwritten external observer: the view model's external-change handler
  is a single property. The component's initializer unconditionally
  assigns its own handler, replacing whatever handler (if any) was
  previously registered on that view model. See **owns-on-change**.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | color view model object | — (required) | Supplies the row's title and current color; receives committed color-well changes via the view model's color. The initializer also overwrites this view model's external-change handler with the component's own sync handler (see **owns-on-change**). |

## Deep Linking

Not applicable: the component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in source.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes from the view model's title, a value the
caller provides, so there is nothing for this component to localize
itself.

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation or
  transition call; every state change is an instantaneous property
  assignment.
- **Increase Contrast**: Not applicable — this component sets no custom
  color anywhere; the label's coloring comes from the active theme's
  primaryText role and the color well's swatch chrome comes entirely from
  the platform's default control rendering, both of which follow system
  Increase Contrast automatically.
- **Differentiate Without Color**: Not applicable — the color the color
  well displays is the control's own edited value, not a color-coded
  status signal that needs a redundant non-color cue; no other state in
  this component is communicated through color alone.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in source; the row always renders once constructed.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a color value supplied by the view model and
  reports color-well changes back through the view model's color.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store; persistence, if any, is owned by the view model and
  its setting observer, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the component retains only its own
  constituent elements and its reference to the view model for its own
  lifetime; it persists nothing beyond that.

## Logging

Not applicable: the source contains no logging call.

## Platform Notes

- **SwiftUI**: Compose a `ColorPicker(viewModel.title, selection: $color)`
  bound to a `Binding<Color>` that reads and writes through the same
  view-model color — passing `viewModel.title` as the picker's own label
  parameter (rather than `ColorPicker("", …)` with `.labelsHidden()` next
  to a separate `Text`) keeps the visual title programmatically linked to
  the control's accessible name, mirroring `commits-color-value`'s
  unconditional, no-equality-check write on every change.
- **Compose**: Use a `Row` with a leading `Text(title)` and a trailing
  color swatch `Box` (a fixed-size, rounded-rect `Modifier.background`)
  that on click opens a color-selection dialog or bottom sheet; commit
  the picked color back to the view model's state on every selection
  callback, again with no equality guard, mirroring `commits-color-value`.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<label htmlFor="…">` wrapping (or `for`-linked to) the
  title text and a trailing `<input type="color" id="…" value>` given a
  fixed width — the `<label for>` association replaces a bare `<span>`
  so the title is programmatically tied to the control; update the bound
  value on the input's `onInput`/`onChange` handler unconditionally,
  mirroring `commits-color-value`.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ColorPickerView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside
  the `ComposableSettings` namespace, conforming to `SettingsViewProtocol`.
  It composes two subviews — a `ThemedLabel` from
  `ComposableSettings.makeRowLabel` and a stock `NSColorWell` — into one
  row via `ComposableSettings.makeRow` and `pinToEdges`. There is no
  UIKit code path in source, and UIKit has no direct `NSColorWell`
  equivalent; a UIKit port would replace it with a custom swatch
  `UIButton` that presents a `UIColorPickerViewController` and receives
  the chosen color through `UIColorPickerViewControllerDelegate` rather
  than target/action. UIKit also has no `NSCoder`-vs-frame initializer
  split to fatal-error on both the way the source's designated
  initializer does (the mechanism behind
  **requires-view-model-at-construction**): `init?(coder:)` and
  `init(frame:)` are both overridden to call `fatalError`, so the only
  surviving construction path is the designated
  `init(viewModel: ColorViewModel)`.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column
  0, given the star-sized column so it absorbs the row's leftover width,
  and a `Button` styled as a swatch pinned in column 1 whose `Background`
  is a `SolidColorBrush` converted from the bound color (an
  `IValueConverter` mirroring the `NSColor`↔stored-value bridge
  `ColorViewModel.color` performs) — the star/auto split mirrors the
  AppKit row's flexible spacer between `label` and `colorWell`, keeping
  the swatch pinned to the row's trailing edge instead of hugging the
  title. The swatch `Button`'s `Click` handler
  opens a `Microsoft.UI.Xaml.Controls.ColorPicker` inside a `Flyout` — the
  WinUI analog of `NSColorWell` opening the system color panel, mirroring
  the Pressed state's inherited open-a-picker behavior. Wire the
  `ColorPicker`'s `ColorChanged` event to write the new color straight
  into the bound view-model property on every event, with no equality
  check before the write, mirroring `commits-color-value`'s unconditional
  commit; drive the swatch's `Background` from the same bound property so
  an external change (mirroring `syncs-on-external-change`) repaints the
  swatch without any additional code.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ColorPickerView.swift` |

## Design Decisions

- **Decision**: Write the reported color into the view model's color on
  every invocation of the color-well handler, with no comparison against
  the current value.
  **Rationale**: The handler only fires in response to a user-driven
  change committed in the system color picker, so a redundant same-value
  write is user-caused and harmless; unlike the sibling captioned slider
  row, whose slider fires continuously during a drag and needs an
  equality guard to avoid a flood of redundant writes on every pixel of
  motion, a color well's action fires once per committed selection, so no
  guard was added here.
  **Approved**: pending
- **Decision**: Overwrite the view model's external-change handler
  unconditionally in the initializer, replacing any handler already
  registered on that view model.
  **Rationale**: Mirrors the same handler-assignment pattern used across
  this row family; the view provides no way to compose with an existing
  observer. This constraint on callers is now captured as the
  **owns-on-change** requirement.
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

`native-controls-preference`, `platform-design-language`, `idempotent-operations`,
and `separation-of-concerns` rest on the source review of
`ColorPickerView.swift` and `ComposableSettings.makeRow`/`pinToEdges`, which
compose stock AppKit controls with no ad hoc state or cross-cutting logic;
`keyboard-navigable` and `semantic-markup` are `partial` because the file
supplies no explicit VoiceOver labeling or keyboard-focus verification of its
own — it relies entirely on `NSColorWell`/`NSTextField`'s built-in AppKit
accessibility and focus behavior, unconfirmed by any recorded keyboard or
VoiceOver pass.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ColorPickerView, covering row layout, unguarded color-well commit behavior, and one open accessibility question (color well/title label association) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: promoted the color-clamping and onChange-ownership edge cases to named MUST requirements with test vectors; renamed `requires-designated-initializer` to `rejects-coder-initialization`; fixed the WinUI grid columns and the SwiftUI/React platform notes to stop copying the color-well/title accessibility gap onto new platforms; bolded Design Decision labels, rewrote Decision 1's rationale, and dropped the meta decision about requirement count; populated `related` with the sibling row recipes; marked `keyboard-navigable` partial pending a keyboard/VoiceOver pass; removed the source-typo edge case; fixed the `AppKit / UIKit` platform-notes label. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
