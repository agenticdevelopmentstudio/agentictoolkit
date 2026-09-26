---
id: c0e95399-ddab-4445-a22a-566d07339f9b
title: ColorPickerView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/color-picker-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row pairing a title label with an NSColorWell,
  syncing a caller-supplied ColorViewModel's color two-way.
platforms:
- swift
- macos
tags:
- settings
- form-control
- color
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/captioned-slider-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/checkbox-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/number-field-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/popup-menu-choice-view
references: []
approved-by: ''
approved-date: ''
---

# ColorPickerView

## Overview

`ColorPickerView` is an AppKit `NSView` from the ComposableSettingsWindow
system integration
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ColorPickerView.swift`)
that pairs a title label with an `NSColorWell` as one settings row and
conforms to `SettingsViewProtocol`. Its title and color are driven by a
caller-supplied `ColorViewModel`: the view reflects the view model's
title/color on construction and whenever the view model reports an
external change, and it writes the user's color-well interactions back
into `viewModel.color`.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange `label` and `colorWell`
  into a single horizontal row via `ComposableSettings.makeRow`, and MUST
  pin that row to all four edges of the view via
  `ComposableSettings.pinToEdges` with no additional constant.
- **initializes-from-view-model**: Component MUST, during initialization,
  build `label` from `viewModel.title` (via `createLabel(title:)`, which
  calls `ComposableSettings.makeRowLabel`) and set `colorWell.color` to
  `viewModel.color`.
- **commits-color-value**: Component MUST set `viewModel.color` to
  `sender.color` every time `colorChanged(_:)` — the color well's
  target-action — is invoked, unconditionally, with no comparison against
  the current value.
- **delegates-color-clamping**: Component MUST NOT perform its own
  clamping or validation of `sender.color` before writing it to
  `viewModel.color`; normalizing an out-of-gamut or malformed color is
  `RGBAColor`'s responsibility, one layer below this component.
- **syncs-on-external-change**: Component MUST re-set `label.stringValue`
  to `viewModel.title` and `colorWell.color` to `viewModel.color` whenever
  `viewModel.onChange` fires.
- **owns-on-change**: Component MUST assign its own closure to
  `viewModel.onChange` during initialization, unconditionally replacing
  any handler already registered on that `ColorViewModel` instance;
  callers MUST NOT share a single `ColorViewModel` across more than one
  observer (for example, two `ColorPickerView` instances, or a
  `ColorPickerView` and another registered `onChange` handler), because
  constructing the later observer silently drops whichever handler was
  registered first.
- **exposes-constituent-views**: Component MUST expose `label` and
  `colorWell` as public, directly-accessible, read-only (`let`)
  properties.
- **rejects-coder-initialization**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes a stock `NSTextField`/`ThemedLabel`
  and a stock `NSColorWell` into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer
  between `label` and `colorWell` (`[label, spacer, colorWell]`) and sets
  the `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` =
  8pt, which applies to the label→spacer gap; `makeRow` explicitly zeroes
  the spacer→colorWell gap (`setCustomSpacing(0, after: spacer)`), so the
  spacer's own width is the only thing between the label and the color
  well. `pinToEdges` pins the row's top/leading/trailing/bottom directly
  to `ColorPickerView`'s edges with no additional constant, so the
  component contributes 0pt of its own outer padding beyond that internal
  8pt / 0pt spacing.
- **Font**: `label` (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight,
  proportional system font, scaling with the active theme's `sizeScale`
  and repainting on a theme change via `ThemePaletteObserver`. `colorWell`
  has no text of its own — not applicable.
- **Background**: None (transparent) for `label` —
  `ThemedLabel.init` sets `drawsBackground = false`, `isBordered = false`,
  and `isBezeled = false` — and neither `ColorPickerView` nor the row
  `NSStackView` sets `wantsLayer` or a background color of its own.
  `colorWell`'s swatch chrome is `NSColorWell`'s own default AppKit
  rendering, not customized in source (no `colorWellStyle` is set).
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change. `colorWell` is not a
  text control; the color it displays is the edited value itself, not a
  foreground/text color, so "Foreground/Text" is not applicable to it.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in `ColorPickerView.swift`; `colorWell`'s border is `NSColorWell`'s
  stock chrome, not custom to this file.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `ColorPickerView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `ColorPickerView.swift`; sizing is governed
  entirely by `label` and `colorWell`'s own intrinsic sizes inside the
  `makeRow` stack view.

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `colorWell` shows `viewModel.color`. |
| Pressed | Not applicable / inherited: clicking `colorWell` opens the system color panel through `NSColorWell`'s own default AppKit interaction; no custom presentation code exists in `ColorPickerView.swift`. |
| Disabled | Not applicable: `isEnabled` is never set on `colorWell` or `label` in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; `colorWell` uses AppKit's default `NSControl` focus-ring behavior when tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call
  appears in source. `NSColorWell` and `NSTextField` each carry AppKit's
  built-in accessibility role (color well, static text) automatically.
- **Label requirements**: `label` and `colorWell` are laid out as sibling
  views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on
  `colorWell` linking it to `label` — confirmed by comparison with sibling
  row views in the same directory: `CheckboxView`, `NumberFieldView`, and
  `PopupMenuChoiceView` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their control,
  but `ColorPickerView` does not do so for `colorWell`. `colorWell` relies
  entirely on `NSColorWell`'s own default AppKit accessibility role, with
  no explicit, programmatic link from the color well to the row's title
  text.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| color-picker-view-001 | arranges-row-layout | Construct `ColorPickerView` with any `viewModel` | `label` and `colorWell` are arranged (with an internal spacer) in a single row view that is pinned to the component's edges; no other layout container appears |
| color-picker-view-002 | initializes-from-view-model | `viewModel.title = "Accent"`, `viewModel.color = NSColor.red` | After init, `label.stringValue == "Accent"` and `colorWell.color == NSColor.red` |
| color-picker-view-003 | commits-color-value | Set `colorWell.color = NSColor.blue` and invoke `colorChanged(colorWell)` | `viewModel.color == NSColor.blue` after the call |
| color-picker-view-004 | commits-color-value | Construct with a counting/spy `ColorViewModel` stub whose `color` setter increments a call counter; set `colorWell.color = NSColor.blue` and invoke `colorChanged(colorWell)` twice in a row with the same color | The setter's call counter increments on both invocations (the second, redundant-value write is not skipped) |
| color-picker-view-005 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.color`, then invoke `viewModel.onChange(newColor)` | `label.stringValue` and `colorWell.color` both update to reflect the new `viewModel` state |
| color-picker-view-006 | exposes-constituent-views | Construct the component, then access `.label` and `.colorWell` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSColorWell` instances built during init (`label` is a `ThemedLabel` instance, declared as `NSTextField`) |
| color-picker-view-007 | rejects-coder-initialization | Attempt `ColorPickerView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| color-picker-view-008 | rejects-frame-only-initialization | Attempt `ColorPickerView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| color-picker-view-009 | owns-on-change | Construct two `ColorPickerView` instances in turn against the same `ColorViewModel` instance, then invoke `viewModel.onChange(someColor)` | Only the second view's `label`/`colorWell` update; the first view's handler was silently replaced and is never invoked |
| color-picker-view-010 | delegates-color-clamping | Set `colorWell.color` to an out-of-gamut `NSColor` and invoke `colorChanged(colorWell)` | `ColorPickerView` writes `sender.color` into `viewModel.color` unchanged — no clamping call appears in `ColorPickerView.swift`; any normalization happens inside `RGBAColor`'s initializer, one layer below |

## Edge Cases

- Null/empty input: `viewModel` (`ColorViewModel`) is a non-optional
  parameter; nil is ruled out by the type system. The component provides,
  and needs, no nil-handling path for its one initializer parameter.
- Boundary values — out-of-range or out-of-gamut color: `ColorPickerView`
  performs no clamping or validation of `sender.color` before writing it
  to `viewModel.color`. Clamping happens one layer down: `ColorViewModel`'s
  `color` setter converts the incoming `NSColor` to `RGBAColor(newValue)`,
  and `RGBAColor.init(red:green:blue:alpha:)` clamps each channel to
  `[0, 1]` via a private `Double.clamped()` helper — so an out-of-gamut or
  malformed `NSColor` is always normalized before it reaches storage, but
  that normalization is `RGBAColor`'s behavior, not `ColorPickerView`'s.
  See **delegates-color-clamping**.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated,
  so Swift's concurrency checker serializes all access to the main actor;
  there is no code path by which two threads can mutate the view
  simultaneously.
- Error states: Not applicable — every operation in this file (the color
  well's target-action and the `viewModel.color` write) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ColorViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `ColorPickerView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in ... }`, replacing whatever
  handler (if any) was previously registered on that `viewModel`. See
  **owns-on-change**.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ColorViewModel` | — (required) | Supplies the row's title and current color; receives committed color-well changes via `viewModel.color`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see **owns-on-change**). |

## Deep Linking

Not applicable: `ColorPickerView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in `ColorPickerView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes from `viewModel.title`, a value the caller
provides, so there is nothing for this component to localize itself.

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext` call; every state change is an
  instantaneous property assignment.
- **Increase Contrast**: Not applicable — `ColorPickerView.swift` sets no
  custom `NSColor` anywhere; `label`'s coloring comes from the active
  theme's `primaryText` role and `colorWell`'s swatch chrome comes
  entirely from AppKit's default control rendering, both of which follow
  system Increase Contrast automatically.
- **Differentiate Without Color**: Not applicable — the color `colorWell`
  displays is the control's own edited value, not a color-coded status
  signal that needs a redundant non-color cue; no other state in this
  component is communicated through color alone.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in `ColorPickerView.swift`; the row always renders once
constructed.

## Analytics

Not applicable: `ColorPickerView.swift` contains no analytics or
telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a color value supplied by `viewModel` and
  reports color-well changes back through `viewModel.color`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `ColorViewModel`/`UserSettingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own subviews
  and its reference to `viewModel` for its own lifetime; it persists
  nothing beyond that.

## Logging

Not applicable: `ColorPickerView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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
  split to fatal-error on both the way `rejects-coder-initialization`
  and `rejects-frame-only-initialization` do.
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

- **Decision**: Write `sender.color` into `viewModel.color` inside
  `colorChanged(_:)` on every invocation, with no comparison against the
  current value.
  **Rationale**: `colorChanged(_:)` only fires from `NSColorWell`'s
  target-action in response to a user-driven change committed in the
  system color panel, so a redundant same-value write is user-caused and
  harmless; unlike the sibling `CaptionedSliderView`, whose slider fires
  continuously during a drag and needs an equality guard to avoid a flood
  of redundant writes on every pixel of motion, a color well's action
  fires once per committed selection, so no guard was added here.
  **Approved**: pending
- **Decision**: Overwrite `viewModel.onChange` unconditionally in the
  initializer, replacing any handler already registered on that
  `ColorViewModel`.
  **Rationale**: Mirrors the same closure-property-assignment pattern used
  across the ComposableSettingsWindow row family; the view provides no
  way to compose with an existing observer. This constraint on callers is
  now captured as the **owns-on-change** requirement.
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
