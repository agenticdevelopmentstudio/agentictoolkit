---
id: 67a314b9-d324-4d0c-b9c1-86e27c01537d
title: FontPickerView
domain: agentictoolkit://recipes/font-picker-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row binding a FontViewModel to a FontChooserButton
  - the chosen font, named and drawn in itself, opening the system font panel when
  clicked.
platforms:
- swift
- macos
tags:
- settings
- form-control
- font
- macos
- appkit
depends-on:
- agentictoolkit://recipes/font-chooser-button
related:
- agentictoolkit://recipes/color-picker-view
- agentictoolkit://recipes/checkbox-view
- agentictoolkit://recipes/number-field-view
- agentictoolkit://recipes/popup-menu-choice-view
references: []
approved-by: ''
approved-date: ''
---

# FontPickerView

## Overview

`FontPickerView` (`ComposableSettings.FontPickerView`) is a macOS `NSView`
from the ComposableSettingsWindow system integration
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontPickerView.swift`)
that pairs a title label with a `FontChooserButton` as one settings row and
conforms to `SettingsViewProtocol`. Its title and font are driven by a
caller-supplied `FontViewModel`: the row builds its label from the view
model's title and shows the view model's current font (with an
"installed"/"not installed" qualifier) on the button, keeps both in sync
whenever the view model reports an external change, and writes the font the
user picks in the button's font panel back into `viewModel.setFont(_:)`. Per
the source's own doc comment, the row is "the binding and nothing else" -
the font-panel plumbing lives once, in `FontChooserButton`, so this row and
any other caller of that button cannot drift apart.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange `label` and `button` into
  a single horizontal row via `ComposableSettings.makeRow`, and MUST pin
  that row to all four edges of the view via `ComposableSettings.pinToEdges`
  with no additional constant.
- **initializes-label-from-view-model-title**: Component MUST, during
  initialization, build `label` from `viewModel.title` via
  `ComposableSettings.makeRowLabel`.
- **initializes-button-without-fixed-width**: Component MUST construct
  `button` via the plain `FontChooserButton()` initializer, never
  `FontChooserButton(width:)`, so no width constraint is added on the
  button's behalf.
- **tags-button-with-a-fixed-accessibility-identifier**: Component MUST set
  the button's accessibility identifier to the literal
  `"settings.font-picker.choose"` during initialization.
- **commits-picked-font-through-view-model**: WHEN `button.onChange` fires
  with the font the user picked, the component MUST call
  `viewModel.setFont(_:)` with that font.
- **resyncs-synchronously-after-a-pick**: WHEN `button.onChange` fires, the
  component MUST call its own `sync()` routine synchronously, immediately
  after calling `viewModel.setFont(_:)`, regardless of whether that call
  actually changed the view model's stored name or size.
- **observes-external-view-model-changes**: Component MUST assign
  `viewModel.onChange` to a closure that calls `sync()`; the closure MUST
  discard the font value it receives and let `sync()` re-read state from
  `viewModel` directly.
- **overwrites-existing-view-model-observer**: Component MUST assign that
  closure to `viewModel.onChange` unconditionally in `init`, replacing
  whatever handler (if any) was already registered on that `FontViewModel`
  instance.
- **syncs-once-at-construction**: Component MUST call `sync()` exactly once
  at the end of initialization, after `label`, `button`, the row, and the
  `button.onChange`/`viewModel.onChange` closures are all wired up.
- **redraws-label-text-on-every-sync**: WHEN `sync()` runs, the component
  MUST set `label.stringValue` to `viewModel.title`, unconditionally, even
  though `viewModel.title` cannot change after construction (`title` is a
  `let` on `AbstractViewModel`).
- **updates-button-sample-on-every-sync**: WHEN `sync()` runs, the component
  MUST call `button.show(_:title:)`, passing `viewModel.font` as the font
  and the result of the private `describe(_:installed:)` helper as the
  title.
- **describes-font-name-and-rounded-point-size**: WHEN `sync()` runs,
  `button`'s title MUST read `"<name> — <size> pt"`, where `<name>` is
  `font.displayName ?? font.fontName` and `<size>` is `font.pointSize`
  rounded to the nearest integer (see the `AppKit / UIKit` platform note for
  the private helper that computes this string).
- **flags-an-uninstalled-font-in-its-title**: WHEN `sync()` runs and
  `viewModel.isInstalled == false`, `button`'s title MUST end with the
  literal suffix `" (not installed)"`.
- **delegates-font-resolution-fallback**: Component MUST NOT perform its own
  validation, clamping, or fallback substitution on `viewModel.font`'s
  underlying stored name or size before passing it to `button.show(_:title:)`;
  resolving an uninstalled font name or an out-of-range stored size to a
  fallback font is `FontViewModel.font`'s responsibility, one layer below
  this component.
- **dims-and-disables-the-row**: WHEN `isEnabled` is set to `false`, the
  component MUST set `button.isEnabled` to `false` and `label.alphaValue` to
  `0.4`. WHEN `isEnabled` is set to `true`, the component MUST set
  `button.isEnabled` to `true` and `label.alphaValue` to `1.0`.
- **defaults-to-enabled**: Component MUST initialize `isEnabled` to `true`.
- **exposes-constituent-views**: Component MUST expose `label` and `button`
  as public, directly-accessible, read-only (`let`) properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.

## Appearance

- **Corner radius**: Not applicable - the component adds no custom layer or
  drawing code of its own; it only composes a `ThemedLabel` (via
  `makeRowLabel`) and a `FontChooserButton` into a row (see
  `agentictoolkit://recipes/font-chooser-button` for the button's own
  corner treatment).
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer
  between `label` and `button` (`[label, spacer, button]`) and sets the
  `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` = 8pt,
  which applies to the label-to-spacer gap; `makeRow` explicitly zeroes the
  spacer-to-button gap (`setCustomSpacing(0, after: spacer)`), so the
  spacer's own width is the only thing between the label and the button.
  `pinToEdges` pins the row's top/leading/trailing/bottom directly to
  `FontPickerView`'s edges with no additional constant, so the component
  contributes 0pt of its own outer padding beyond that internal 8pt / 0pt
  spacing.
- **Font**: `label` (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight, proportional
  system font, scaling with the active theme's `sizeScale` and repainting on
  a theme change via `ThemePaletteObserver`. `button`'s own font is dynamic
  and drawn at a fixed 12pt sample size regardless of the stored font's real
  size - see `draws-sample-at-fixed-size` in
  `agentictoolkit://recipes/font-chooser-button`.
- **Background**: None (transparent) for `label` - `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false` -
  and neither `FontPickerView` nor the row `NSStackView` sets `wantsLayer`
  or a background color of its own. `button`'s bezel chrome is
  `FontChooserButton`'s own concern, not set here.
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the active
  theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change, then dimmed to 40% alpha
  when `isEnabled == false` (see **dims-and-disables-the-row**). `button`'s
  title color is not set in this file; it is `FontChooserButton`'s stock
  bezel text color.
- **Border**: Not applicable - no border is drawn or configured anywhere in
  `FontPickerView.swift`.
- **Shadow**: Not applicable - no shadow is drawn or configured anywhere in
  `FontPickerView.swift`.
- **Min/Max size**: Not applicable - no explicit min/max width or height
  constraint is set in `FontPickerView.swift`; sizing is governed entirely
  by `label` and `button`'s own intrinsic sizes inside the `makeRow` stack
  view (`button`'s own compression/hugging behavior when built without a
  fixed width is documented in `agentictoolkit://recipes/font-chooser-button`).

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `button` shows `viewModel.font`'s sample, titled with `describe(viewModel.font, installed: viewModel.isInstalled)`. |
| Pressed | Not applicable / inherited: clicking `button` opens the system font panel through `FontChooserButton`'s own default interaction; no custom presentation code exists in `FontPickerView.swift`. |
| Disabled | `button.isEnabled == false` and `label.alphaValue == 0.4` (see **dims-and-disables-the-row**). |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; `button` uses `NSButton`'s default focus-ring behavior when tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults - no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call appears
  in `FontPickerView.swift`. `button` carries `NSButton`'s native button
  role (see `agentictoolkit://recipes/font-chooser-button`); `label` is a
  plain static-text control.
- **Label requirements**: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. `label` and `button` are laid out as sibling views in the same
  row, but `FontPickerView.swift` sets no
  `accessibilityLabel`/`setAccessibilityTitleUIElement` (or equivalent)
  linking `button` to `label` - confirmed by comparison with sibling row
  views in the same directory: `CheckboxView`, `NumberFieldView`, and
  `PopupMenuChoiceView` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their control,
  but `FontPickerView` does not do so for `button`. The `accessibilityID`
  call in source (`button.accessibilityID("settings.font-picker.choose")`)
  sets a UI-testing identifier, not an accessible name or label linkage.
  What is missing: whether VoiceOver announces the row's title (e.g.
  "Terminal Font") when focus lands on the button, or only the button's own
  title text (e.g. "Menlo-Regular — 14 pt"). What would settle it: a VoiceOver pass
  over an instantiated row, or an explicit decision to call
  `button.setAccessibilityTitleUIElement(label)` in `init`/`sync()`,
  matching the pattern the other control-with-label rows already use.
- **Minimum contrast ratio**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. `label.alphaValue` is set to a hardcoded `0.4` when
  the row is disabled (**dims-and-disables-the-row**); this literal is
  local to `FontPickerView.swift` (no other file in
  `ComposableSettingsWindow/Views` uses this value or a shared "disabled
  alpha" constant). Whether `label`'s text at 40% alpha against the active
  theme's surface color still meets a specific contrast ratio (e.g. WCAG
  2.1 AA's 4.5:1) cannot be determined from this file alone - it depends on
  the resolved theme colors, which live outside this source. This would be
  settled by auditing each shipped theme's resolved `primaryText`/surface
  pairing at 40% alpha.
- **Announce state changes (e.g., loading, disabled)**: `FontPickerView.swift`
  performs no explicit accessibility notification (no `NSAccessibility.post`
  call) when `isEnabled` changes; `button.isEnabled`'s own state is exposed
  automatically through `NSButton`'s native accessibility, but no proactive
  announcement is posted by this file. There is no loading state to
  announce (see States).
- **Minimum tap target**: Not applicable - this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44x44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| font-picker-view-001 | arranges-row-layout | Construct `FontPickerView` with any `viewModel` | `label` and `button` are arranged (with an internal spacer) in a single row view that is pinned to the component's edges; no other layout container appears |
| font-picker-view-002 | initializes-label-from-view-model-title | `viewModel.title = "Terminal Font"` | After init, `label.stringValue == "Terminal Font"` |
| font-picker-view-003 | initializes-button-without-fixed-width | Construct `FontPickerView` | `button` has no width constraint added by `FontPickerView` itself (it is built via `FontChooserButton()`, not `FontChooserButton(width:)`) |
| font-picker-view-004 | tags-button-with-a-fixed-accessibility-identifier | Construct `FontPickerView` | `button`'s accessibility identifier equals `"settings.font-picker.choose"` |
| font-picker-view-005 | commits-picked-font-through-view-model | Invoke `button.onChange(newFont)` | `viewModel.setFont(newFont)` is called |
| font-picker-view-006 | resyncs-synchronously-after-a-pick | Invoke `button.onChange(newFont)` where `newFont`'s name and size equal the view model's current stored values | `label.stringValue` and `button`'s displayed sample/title are re-set synchronously to match `viewModel`'s state, with no dependency on any later asynchronous callback |
| font-picker-view-007 | observes-external-view-model-changes | After construction, directly invoke the closure assigned to `viewModel.onChange` with an arbitrary font argument | `label.stringValue` and `button`'s displayed sample/title update to reflect `viewModel.title`/`viewModel.font` as they currently stand, independent of the argument passed |
| font-picker-view-008 | overwrites-existing-view-model-observer | Assign a closure to `viewModel.onChange`, then construct `FontPickerView(viewModel:)` against that same `viewModel`, then invoke `viewModel.onChange` | Only `FontPickerView`'s sync-calling closure runs; the original closure does not run |
| font-picker-view-009 | syncs-once-at-construction | Construct `FontPickerView` | `label.stringValue` and `button`'s displayed title already reflect `viewModel.title`/`viewModel.font` immediately after `init` returns, with no further call needed |
| font-picker-view-010 | redraws-label-text-on-every-sync | Trigger `sync()` twice (once via construction, once via `button.onChange` or `viewModel.onChange`) | `label.stringValue` is reassigned to `viewModel.title` on both occasions (verifiable via a spy on the label's `stringValue` setter recording at least two invocations) |
| font-picker-view-011 | updates-button-sample-on-every-sync | Trigger `sync()` | `button.show(_:title:)` is called with `viewModel.font` and `describe(viewModel.font, installed: viewModel.isInstalled)` |
| font-picker-view-012 | describes-font-name-and-rounded-point-size | Construct `FontPickerView` with a `viewModel` whose `font` resolves to `NSFont(name: "Menlo-Regular", size: 14.4)!` and whose `isInstalled == true` | `button.show(_:title:)`'s title equals `"\(font.displayName ?? font.fontName) — 14 pt"` — an em dash separator and the point size rounded to the nearest integer, with no `(not installed)` suffix |
| font-picker-view-013 | flags-an-uninstalled-font-in-its-title | Construct `FontPickerView` with a `viewModel` whose `isInstalled == false` | `button.show(_:title:)`'s title ends with the literal suffix `" (not installed)"` |
| font-picker-view-014 | dims-and-disables-the-row | Set `isEnabled = false`, then `isEnabled = true` | After `false`: `button.isEnabled == false`, `label.alphaValue == 0.4`. After `true`: `button.isEnabled == true`, `label.alphaValue == 1.0` |
| font-picker-view-015 | defaults-to-enabled | Construct `FontPickerView` | `isEnabled == true`, `button.isEnabled == true`, `label.alphaValue == 1.0`, before any explicit assignment |
| font-picker-view-016 | exposes-constituent-views | Construct the component, then access `.label` and `.button` from outside the type | Both properties are accessible and return the same `NSTextField`/`FontChooserButton` instances built during init (`label` is a `ThemedLabel` instance, declared as `NSTextField`) |
| font-picker-view-017 | requires-designated-initializer | Attempt `FontPickerView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| font-picker-view-018 | rejects-frame-only-initialization | Attempt `FontPickerView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| font-picker-view-019 | delegates-font-resolution-fallback | Construct `viewModel` whose stored font name/size combination is invalid (so `FontViewModel.font` falls back to `.monospacedSystemFont(ofSize:weight: .regular)`), then trigger `sync()` | `button.show(_:title:)` is called with exactly the `NSFont` that `viewModel.font` returns (the fallback font); `FontPickerView` performs no validation, clamping, or substitution of its own on this value |

## Edge Cases

- **Null/empty input**: `viewModel` (`FontViewModel`) is a non-optional,
  non-escaping-typed constructor parameter; Swift's type system rules out
  `nil`. The component provides, and needs, no nil-handling path for its
  one initializer parameter.
- **Boundary values**: Neither `FontPickerView.swift` nor `FontViewModel.swift`
  clamps or validates `sizeObserver.value` (a plain `Double` persisted via
  `UserSetting<Double>`) before constructing `NSFont(name:size:)` in
  `FontViewModel.font`. An arbitrary stored size (including zero, negative,
  or extremely large values) is passed straight through with no validation
  in either file. If `NSFont(name:size:)` returns `nil` for that
  combination, `FontViewModel.font` falls back to
  `.monospacedSystemFont(ofSize:weight: .regular)` - the same fallback path
  used for an uninstalled font name (see next item). That fallback is
  `FontViewModel.font`'s responsibility, not `FontPickerView`'s -
  `FontPickerView.sync()` reads `viewModel.font` unconditionally and passes
  it straight to `button.show(_:title:)`. See
  **delegates-font-resolution-fallback**.
- **Concurrent access**: Not applicable - the class is `@MainActor`-isolated,
  so Swift's concurrency checker serializes all access to the main actor;
  there is no code path by which two threads can mutate the view
  simultaneously.
- **Error states**: Not applicable - every operation in
  `FontPickerView.swift` (the button's target-action, `viewModel.setFont`,
  and the `sync()` reads) is a synchronous, non-throwing call; no `try`,
  `Result`, or error-producing API appears in source.
- **Offline/disconnected**: Not applicable - the component performs no
  networking of its own; it only reads from and writes to an in-process
  `FontViewModel`.
- **Overwritten external observer**: `viewModel.onChange` is a single
  closure property. `FontPickerView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.sync() }`, replacing
  whatever handler (if any) was previously registered on that
  `FontViewModel` instance (see **overwrites-existing-view-model-observer**).
- **Repeated sync after a single font pick**: Picking a font that changes
  both the stored name and size fires `sync()` more than once for one user
  action. `button.onChange`'s closure calls `viewModel.setFont(font)` then
  `self.sync()` synchronously. `FontViewModel.setFont(_:)` writes
  `nameObserver.value` and `sizeObserver.value` only when each differs from
  its current value; each write that actually occurs independently triggers
  that observer's `UserSettingObserver.onChange` on the *next main-queue
  turn* (the `.receive(on: DispatchQueue.main)` hop documented in
  `UserSetting.swift`), which calls `FontViewModel.onChange?(self.font)`,
  i.e. `FontPickerView`'s `sync()`-calling closure, again. So picking a
  font that changes both name and size results in one synchronous `sync()`
  call plus up to two further asynchronous `sync()` calls; picking the
  exact font already stored (both guards fail) results in exactly one
  `sync()` call. The component performs no debouncing or deduplication of
  these repeated calls; because `sync()` always re-reads current state
  rather than accumulating it, the redundant calls are observably
  idempotent (see **resyncs-synchronously-after-a-pick**).
- **Reassigning an unchanged label**: `sync()` unconditionally reassigns
  `label.stringValue = viewModel.title` on every call, even though
  `viewModel.title` is a `let` on `AbstractViewModel` and can never change
  after construction. The component performs no early-exit/equality check
  before this reassignment (see **redraws-label-text-on-every-sync**).
- **Toggling `isEnabled` to its current value**: `isEnabled`'s `didSet`
  reassigns `button.isEnabled` and `label.alphaValue` on every assignment,
  including a reassignment to the value `isEnabled` already holds; Swift's
  `didSet` carries no built-in equality guard, and source adds none (see
  **dims-and-disables-the-row**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `FontViewModel` | - (required) | Supplies the row's title and current font; receives committed font-panel picks via `viewModel.setFont(_:)`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). |
| `isEnabled` | `Bool` | `true` | Dims and disables the row's `button` and `label` when set to `false` (see **dims-and-disables-the-row**). |

## Deep Linking

Not applicable: `FontPickerView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `FontPickerView.swift`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none - hardcoded literal fragments) | `" — %@ pt"` / `" (not installed)"` | Built by the private `describe(_:installed:)` helper and passed as `button`'s title on every `sync()` call. |

`label`'s text comes from `viewModel.title`, a value the caller provides, so
there is nothing for this component to localize there. The `" — "`, `" pt"`,
and `" (not installed)"` fragments inside `describe(_:installed:)`,
however, are hardcoded English string-interpolation literals assigned to
`button`'s AppKit `title` (a plain `String`, not a `LocalizedStringKey`) -
not wrapped in `String(localized:)` or any string-catalog key anywhere in
`FontPickerView.swift`. NEEDS REVIEW: Not implemented in source. Behavior
undefined. What is missing: a localization key (with pluralization/unit
handling for "pt" and a localizable qualifier for "not installed") for
these fragments. What would settle it: a design decision to route
`describe(_:installed:)`'s output through a String Catalog format string
instead of raw interpolation.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call anywhere in `FontPickerView.swift`; the `isEnabled` dimming (`button.isEnabled` / `label.alphaValue`) is an instantaneous property assignment, not an animated transition. |
| Increase Contrast | Not applicable to this file directly: `FontPickerView.swift` reads no system contrast setting and sets no custom `NSColor`; `label`'s coloring comes from the active theme's `primaryText` role (tracks Increase Contrast automatically) and `button`'s title color is AppKit's own default control rendering. Whether the `0.4`-alpha disabled dimming remains sufficiently contrasted is tracked once under Accessibility above ("Minimum contrast ratio"), not duplicated here. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone; `isEnabled` is communicated through both `button.isEnabled` (which changes the button's interactive/bezel appearance, not merely a color) and `label.alphaValue`, and the font name/installed-status is communicated through text (`describe(_:installed:)`), not color. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `FontPickerView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `FontPickerView.swift` contains no analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable - the component collects no data of
  its own; it only displays a font supplied by `viewModel` and reports
  font-panel picks back through `viewModel.setFont(_:)`.
- **Storage**: Not applicable - source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `FontViewModel`/`UserSettingObserver`/`UserSetting`, which are not part of
  this file.
- **Transmission**: Not applicable - no networking call appears anywhere in
  source.
- **Retention**: The view retains only its own subviews and its reference
  to `viewModel` for its own lifetime; it persists nothing beyond that.

## Logging

Not applicable: `FontPickerView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)` and a
  trailing font-sample button (an `NSViewRepresentable` wrapping
  `FontChooserButton`, per `agentictoolkit://recipes/font-chooser-button`'s
  own SwiftUI note, or an equivalent custom `Button` that opens a font
  picker) bound to a `Binding` that reads and writes through the same
  view-model font, mirroring **commits-picked-font-through-view-model** and
  **observes-external-view-model-changes**; drive both the label's opacity
  and the button's `disabled(_:)` from one `isEnabled` boolean, mirroring
  **dims-and-disables-the-row**.
- **Compose**: Use a `Row` with a leading `Text(title)` and a trailing
  sample `Button` whose label is drawn in the currently selected
  `FontFamily` at a fixed sample size, opening a custom
  `AlertDialog`/`ModalBottomSheet` listing available font families and
  sizes on click (there is no Android system font panel to defer to, per
  `agentictoolkit://recipes/font-chooser-button`'s Compose note); commit the
  picked family/size back to the view model unconditionally on selection,
  and gate both children's `enabled`/alpha from one boolean, mirroring
  **dims-and-disables-the-row**.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<span>` for the title and a trailing `<button>` styled with
  `style.fontFamily` set to the current selection at a fixed sample
  `font-size`, opening a custom popover/dialog listing available fonts (the
  CSS Font Loading API's `document.fonts`, or a fixed app-defined list) on
  click; forward the picked family/size through a callback prop mirroring
  **commits-picked-font-through-view-model**, and toggle a `disabled`
  attribute plus a reduced-opacity class on both children together,
  mirroring **dims-and-disables-the-row**.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontPickerView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews - a `ThemedLabel` from
  `ComposableSettings.makeRowLabel` and a `FontChooserButton` - into one row
  via `ComposableSettings.makeRow` and `pinToEdges`. `button`'s title text is
  computed by a private static `describe(_:installed:)` helper, which formats
  `"<name> — <size> pt"` and appends `" (not installed)"` when the font is
  not installed - see **describes-font-name-and-rounded-point-size** and
  **flags-an-uninstalled-font-in-its-title**. There is no UIKit code
  path in source; a UIKit port has no `NSFontPanel` equivalent to defer to
  (see `agentictoolkit://recipes/font-chooser-button`'s own AppKit/UIKit
  note for the button's side of that gap) and would need its own
  `isEnabled`-driven dimming, since UIKit has no direct `alphaValue`
  analogue on `UILabel` beyond its inherited `UIView.alpha`.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*`: a `TextBlock` bound to `viewModel.title`
  in column 0, and in column 1 the font-sample `Button` described in
  `agentictoolkit://recipes/font-chooser-button`'s own WinUI 3 note (its
  `Content` `TextBlock` bound to the selected font's family/size at a fixed
  sample `FontSize`, opening a `ContentDialog`/`Flyout` for selection since
  WinUI ships no system font panel). Wire that dialog's confirm/selection
  event to call an equivalent of `viewModel.setFont` unconditionally on
  every pick, then re-read the view model's current font/title back into
  both the `TextBlock` and the sample `Button` - mirroring
  **commits-picked-font-through-view-model** and
  **resyncs-synchronously-after-a-pick** in one step, since WinUI has no
  separate `UserSettingObserver` Combine hop to produce a second,
  asynchronous re-sync the way this source's `sizeObserver`/`nameObserver`
  do (see Edge Cases, "Repeated sync after a single font pick" - a WinUI
  port that binds both the `TextBlock` and the sample `Button`'s content to
  the same `INotifyPropertyChanged` font property gets the same
  eventually-consistent redraw without needing to replicate the double
  callback). Drive both children's `Opacity`/`IsEnabled` from one bound
  boolean to mirror **dims-and-disables-the-row**'s all-or-nothing row
  dimming, and append a not-installed qualifier to the `TextBlock`'s bound
  display string (via an `IValueConverter`) mirroring
  **flags-an-uninstalled-font-in-its-title**.

## Design Decisions

**Decision**: `viewModel.onChange` is overwritten unconditionally in `init`,
replacing any handler already registered on that `FontViewModel` instance.
**Rationale**: Mirrors the same closure-property-assignment pattern
documented at `agentictoolkit://recipes/color-picker-view#requirements/owns-on-change`;
the view provides no way to compose with an existing observer.
**Approved**: pending

**Decision**: A single font pick can trigger `sync()` up to three times (one
synchronous call from `button.onChange`, and up to two further asynchronous
calls from `FontViewModel`'s `nameObserver`/`sizeObserver`, each hopping to
the next main-queue turn) with no debouncing or deduplication.
**Rationale**: `sync()` always re-reads current state from `viewModel` rather
than accumulating deltas, so the repeated calls are redundant but
observably idempotent; the source accepts that redundancy rather than
adding a guard, consistent with `UserSettingObserver`'s own documented
choice to hop to the main queue for every mouse-drag-safe update rather than
coalescing them.
**Approved**: pending

**Decision**: The disabled-state dimming uses a hardcoded `0.4` alpha on
`label`, local to this file, rather than a shared "disabled alpha" token
used elsewhere in the row family.
**Rationale**: No other file under `ComposableSettingsWindow/Views` sets this
exact value or references a shared constant for it; this recipe documents
the value as-is rather than inventing a token the source does not use (see
the "Minimum contrast ratio" open question under Accessibility).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

`native-controls-preference` and `platform-design-language` pass because the
component defers to `FontChooserButton`'s own use of the system font panel
rather than building a second font browser. `keyboard-navigable` passes on
`NSButton`'s inherited Tab/Space/Return handling. `screen-reader-support` is
`partial`: `button`'s own accessible name (its `title`) is meaningful, but
the row's descriptive `label` is not linked to it (see the open question
under Accessibility). `contrast-ratio` is `partial`: the resolved contrast
of the 40%-alpha disabled label cannot be determined from this file alone
(see the "Minimum contrast ratio" open question under Accessibility).
`idempotent-operations` passes because repeated `sync()` calls always
converge to the same observable state (see Edge Cases).
`separation-of-concerns` passes because the component stores no font of its
own beyond its reference to `viewModel`, and delegates all font-resolution
fallback to `FontViewModel.font` (see **delegates-font-resolution-fallback**).
`string-externalization` fails because `describe(_:installed:)`
builds its output from hardcoded, unlocalized string fragments (see
Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for FontPickerView, covering the row's view-model binding, the synchronous-plus-asynchronous re-sync path after a font pick, the isEnabled dimming, and two open accessibility/localization questions for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: added a delegates-font-resolution-fallback requirement and vector so the boundary-values edge case points at FontViewModel instead of taking on its fallback behavior here; restated describes-font-name-and-rounded-point-size and flags-an-uninstalled-font-in-its-title against button's observable title instead of the private describe(_:installed:) helper, and moved that helper's name into the AppKit/UIKit platform note; fixed vector 012's font/literal and the Localization row to match source's em dash separator exactly; bolded Design Decision labels and cited color-picker-view's owns-on-change requirement in Decision 1's rationale instead of naming it vaguely; dropped the meta decision comparing this recipe's requirement count to ColorPickerView's and the leftover "helper-tracing rule" aside; trimmed Edge Cases so they cite named requirements instead of re-asserting "This is a MUST"; fixed contrast-ratio's status from the disallowed needs-review to partial; populated related with the sibling row recipes it's compared against; and remapped the meaningful-labels compliance check (not in the catalog) to its screen-reader-support synonym. |
