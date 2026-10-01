---
id: 67a314b9-d324-4d0c-b9c1-86e27c01537d
title: Font Picker View
domain: agentictoolkit://cookbook/ui/settings/rows/font-picker-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row binding a font view model to a font chooser button - the
  chosen font, named and drawn in itself, opening the platform's font-selection
  UI when clicked.
platforms:
- swift
- macos
tags:
- settings
- form-control
- font
depends-on:
- agentictoolkit://cookbook/ui/settings/rows/font-chooser-button
related:
- agentictoolkit://cookbook/ui/settings/rows/color-picker-view
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
- agentictoolkit://cookbook/ui/settings/rows/number-field-view
- agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view
references: []
approved-by: ''
approved-date: ''
---

# Font Picker View

## Overview

The font picker view pairs a title label with a font chooser button as one
settings row. Its title and font are driven by a caller-supplied font view
model: the row builds its label from the view model's title and shows the
view model's current font (with an "installed"/"not installed" qualifier)
on the button, keeps both in sync whenever the view model reports an
external change, and writes the font the user picks back into the view
model. The row is the binding and nothing else - the font-picker plumbing
lives once, in the font chooser button, so this row and any other caller
of that button cannot drift apart.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the label and the button
  into a single horizontal row, and MUST pin that row to all four edges of
  the view with no additional constant.
- **initializes-label-from-view-model-title**: Component MUST, during
  initialization, build the label from the view model's title.
- **initializes-button-without-fixed-width**: Component MUST construct the
  button without an explicit fixed width, so no width constraint is added
  on the button's behalf.
- **tags-button-with-a-fixed-accessibility-identifier**: Component MUST set
  the button's accessibility identifier to the literal
  `"settings.font-picker.choose"` during initialization.
- **commits-picked-font-through-view-model**: WHEN the button's change
  callback fires with the font the user picked, the component MUST commit
  that font to the view model.
- **resyncs-synchronously-after-a-pick**: WHEN the button's change callback
  fires, the component MUST resynchronize its display synchronously,
  immediately after committing the picked font to the view model,
  regardless of whether that commit actually changed the view model's
  stored name or size.
- **observes-external-view-model-changes**: Component MUST register a
  handler with the view model's external-change notification that
  resynchronizes its display; that handler MUST discard the font value it
  receives and let resynchronization re-read state from the view model
  directly.
- **overwrites-existing-view-model-observer**: Component MUST register that
  handler unconditionally at construction, replacing whatever handler (if
  any) was already registered on that view model instance.
- **syncs-once-at-construction**: Component MUST resynchronize its display
  exactly once at the end of initialization, after the label, the button,
  the row, and both change-notification handlers are all wired up.
- **redraws-label-text-on-every-sync**: WHEN the component resynchronizes,
  it MUST set the label's displayed text to the view model's title,
  unconditionally, even though the view model's title cannot change after
  construction.
- **updates-button-sample-on-every-sync**: WHEN the component
  resynchronizes, it MUST give the button the view model's current font
  and a title built from the font's name and installed status.
- **describes-font-name-and-rounded-point-size**: WHEN the component
  resynchronizes, the button's title MUST read `"<name> — <size> pt"`,
  where `<name>` is the font's display name (falling back to its
  underlying font name) and `<size>` is the font's point size rounded to
  the nearest integer (see the source platform's note for the mechanism
  that computes this string).
- **flags-an-uninstalled-font-in-its-title**: WHEN the component
  resynchronizes and the view model reports the font as not installed, the
  button's title MUST end with the literal suffix `" (not installed)"`.
- **delegates-font-resolution-fallback**: Component MUST NOT perform its
  own validation, clamping, or fallback substitution on the view model's
  underlying stored font name or size before giving it to the button;
  resolving an uninstalled font name or an out-of-range stored size to a
  fallback font is the view model's responsibility, one layer below this
  component.
- **dims-and-disables-the-row**: WHEN the row is disabled, the component
  MUST disable the button and dim the label to 40% opacity. WHEN the row is
  enabled, the component MUST enable the button and restore the label to
  full opacity.
- **defaults-to-enabled**: Component MUST initialize itself enabled.
- **exposes-constituent-views**: Component MUST expose the label and the
  button as public, directly-accessible, read-only properties.
- **requires-view-model-at-construction**: Component MUST support
  construction only through its designated initializer, which requires a
  view model; construction via a bare/default construction path or a
  serialization/decoding-based construction path MUST both trigger a fatal
  error.

## Appearance

- **Corner radius**: Not applicable - the component adds no custom layer or
  drawing code of its own; it only composes a label and a font chooser
  button into a row (see
  `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button` for the button's own
  corner treatment).
- **Padding**: The row inserts a flexible spacer between the label and the
  button and sets the row's spacing to the button role's default row
  spacing (8pt), which applies to the label-to-spacer gap; the
  spacer-to-button gap is explicitly zeroed, so the spacer's own width is
  the only thing between the label and the button. The row is pinned to
  the component's top/leading/trailing/bottom edges with no additional
  constant, so the component contributes 0pt of its own outer padding
  beyond that internal 8pt / 0pt spacing.
- **Font**: The label (button text role) resolves to that role's default
  style: 13pt, medium weight, proportional system font, scaling with the
  active theme's size scale and repainting on a theme change. The button's
  own font is dynamic and drawn at a fixed 12pt sample size regardless of
  the stored font's real size - see the sample-size requirement in
  `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button`.
- **Background**: None (transparent) for the label, and neither the
  component nor its row sets a background color of its own. The button's
  chrome is the font chooser button's own concern, not set here.
- **Foreground/Text**: The label (primaryText role) resolves to the active
  theme's foreground color at full strength, recomputed live on a theme
  change, then dimmed to 40% opacity when the row is disabled (see
  **dims-and-disables-the-row**). The button's title color is not set in
  this file; it is the font chooser button's stock text color.
- **Border**: Not applicable - no border is drawn or configured anywhere in
  source.
- **Shadow**: Not applicable - no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: Not applicable - no explicit min/max width or height
  constraint is set in source; sizing is governed entirely by the label
  and button's own intrinsic sizes inside the row (the button's own
  compression/hugging behavior when built without a fixed width is
  documented in `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button`).

## States

| State | Appearance change |
|-------|------------------|
| Default | The label shows the view model's title; the button shows the view model's font sample, titled from the font's name and installed status. |
| Pressed | Not applicable / inherited: clicking the button opens the platform's font-selection UI through the button's own default interaction; no custom presentation code exists in source. |
| Disabled | Button disabled and label at 40% opacity (see **dims-and-disables-the-row**). |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the button uses its platform's default focus-ring behavior when tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults - no
  custom accessibility role or element grouping call appears in source.
  The button carries its platform's native button role (see
  `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button`); the label is a plain
  static-text control.
- **Label requirements**: The label and the button are laid out as sibling
  views in the same row, but source sets no accessibility linkage between
  them - confirmed by comparison with several sibling row controls in this
  system, which each link their control to its label, but this component
  does not do so for the button. The fixed accessibility identifier set in
  source is a UI-testing identifier, not an accessible name or label
  linkage. As a result, the screen reader announces only the button's own
  title text (e.g. "Menlo-Regular — 14 pt") when focus lands on it, not
  the row's title (e.g. "Terminal Font").
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The label's opacity is set to a hardcoded 40% when the row is disabled (**dims-and-disables-the-row**), local to this file (no sibling row control in this system uses this value or a shared "disabled opacity" constant); whether the label's text at 40% opacity against the active theme's surface color still meets a specific contrast ratio (e.g. WCAG 2.1 AA's 4.5:1) cannot be determined from this file alone since it depends on the resolved theme colors, which live outside this source - settled by auditing each shipped theme's resolved foreground/surface pairing at 40% opacity.
- **Announce state changes (e.g., loading, disabled)**: Source performs no
  explicit accessibility notification when the row's enabled state
  changes; the button's own enabled state is exposed automatically through
  its platform's native accessibility, but no proactive announcement is
  posted by this file. There is no loading state to announce (see
  States).
- **Minimum tap target**: Not applicable - this is a pointer/
  trackpad-driven composition on its source platform (no touch input path
  in source); the 44x44pt minimum is touch-platform guidance, not a
  pointer-interface requirement on the source platform.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| font-picker-view-001 | arranges-row-layout | Construct the component with any view model | The label and button are arranged (with an internal spacer) in a single row view that is pinned to the component's edges; no other layout container appears |
| font-picker-view-002 | initializes-label-from-view-model-title | View model title is "Terminal Font" | After init, the label's displayed text is "Terminal Font" |
| font-picker-view-003 | initializes-button-without-fixed-width | Construct the component | The button has no width constraint added by the component itself (it is built without an explicit fixed width) |
| font-picker-view-004 | tags-button-with-a-fixed-accessibility-identifier | Construct the component | The button's accessibility identifier equals `"settings.font-picker.choose"` |
| font-picker-view-005 | commits-picked-font-through-view-model | Invoke the button's change callback with a new font | The view model receives that font |
| font-picker-view-006 | resyncs-synchronously-after-a-pick | Invoke the button's change callback with a font whose name and size equal the view model's current stored values | The label and the button's displayed sample/title are re-set synchronously to match the view model's state, with no dependency on any later asynchronous callback |
| font-picker-view-007 | observes-external-view-model-changes | After construction, directly invoke the view model's external-change handler with an arbitrary font argument | The label and the button's displayed sample/title update to reflect the view model's title/font as they currently stand, independent of the argument passed |
| font-picker-view-008 | overwrites-existing-view-model-observer | Register a handler on the view model's external-change notification, then construct the component against that same view model, then trigger that notification | Only the component's own resync handler runs; the original handler does not run |
| font-picker-view-009 | syncs-once-at-construction | Construct the component | The label and the button's displayed title already reflect the view model's title/font immediately after construction returns, with no further call needed |
| font-picker-view-010 | redraws-label-text-on-every-sync | Trigger a resync twice (once via construction, once via the button's change callback or the view model's external-change notification) | The label's displayed text is reassigned to the view model's title on both occasions (verifiable via a spy recording at least two invocations) |
| font-picker-view-011 | updates-button-sample-on-every-sync | Trigger a resync | The button is given the view model's current font and a title built from the font's name and installed status |
| font-picker-view-012 | describes-font-name-and-rounded-point-size | Construct the component with a view model whose font resolves to Menlo Regular at 14.4pt and whose installed status is true | The button's title equals "Menlo Regular — 14 pt" — an em dash separator and the point size rounded to the nearest integer, with no "(not installed)" suffix |
| font-picker-view-013 | flags-an-uninstalled-font-in-its-title | Construct the component with a view model whose installed status is false | The button's title ends with the literal suffix `" (not installed)"` |
| font-picker-view-014 | dims-and-disables-the-row | Disable the row, then re-enable it | After disabling: button disabled, label at 40% opacity. After re-enabling: button enabled, label at full opacity |
| font-picker-view-015 | defaults-to-enabled | Construct the component | The row is enabled, the button is enabled, and the label is at full opacity, before any explicit assignment |
| font-picker-view-016 | exposes-constituent-views | Construct the component, then access the label and button from outside the type | Both properties are accessible and return the same instances built during initialization |
| font-picker-view-017 | requires-view-model-at-construction | Attempt construction via a bare/default construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| font-picker-view-018 | requires-view-model-at-construction | Attempt construction via a serialization/decoding-based construction path | The call traps with a fatal error; no instance is returned (a platform-level runtime trap, not an ordinary in-process assertion) |
| font-picker-view-019 | delegates-font-resolution-fallback | Construct a view model whose stored font name/size combination is invalid (so the view model's font falls back to a fixed system monospace font), then trigger a resync | The button is given exactly the font that the view model's font property returns (the fallback font); the component performs no validation, clamping, or substitution of its own on this value |

## Edge Cases

- **Null/empty input**: The view model is a non-optional constructor
  parameter; the type system rules out nil. The component provides, and
  needs, no nil-handling path for its one initializer parameter.
- **Boundary values**: Neither this component nor the view model clamps
  or validates the stored point size (a plain persisted numeric value)
  before resolving the actual font. An arbitrary stored size (including
  zero, negative, or extremely large values) is passed straight through
  with no validation in either place. If that combination cannot resolve
  to a real font, the view model falls back to a fixed system monospace
  font - the same fallback path used for an uninstalled font name (see
  next item). That fallback is the view model's responsibility, not this
  component's - a resync reads the view model's font unconditionally and
  gives it straight to the button. See
  **delegates-font-resolution-fallback**.
- **Concurrent access**: Not applicable - the component is confined to the
  UI thread, so all access is serialized to that thread; there is no code
  path by which two threads can mutate the view simultaneously.
- **Error states**: Not applicable - every operation in this file (the
  button's activation, committing the picked font, and the resync reads)
  is a synchronous, non-throwing call; no error-producing path appears in
  source.
- **Offline/disconnected**: Not applicable - the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- **Overwritten external observer**: The view model's external-change
  handler is a single property. The component's initializer
  unconditionally assigns its own resync-calling handler, replacing
  whatever handler (if any) was previously registered on that view model
  instance (see **overwrites-existing-view-model-observer**).
- **Repeated sync after a single font pick**: Picking a font that changes
  both the stored name and size fires a resync more than once for one user
  action. The button's change-callback handler commits the font to the
  view model, then resynchronizes synchronously. The view model writes its
  underlying stored name and size only when each differs from its current
  value; each write that actually occurs independently triggers the view
  model's own change notification on the next turn of the platform's main
  work queue, which invokes this component's resync handler again. So
  picking a font that changes both name and size results in one
  synchronous resync plus up to two further asynchronous resyncs; picking
  the exact font already stored (both guards fail) results in exactly one
  resync. The component performs no debouncing or deduplication of these
  repeated calls; because a resync always re-reads current state rather
  than accumulating it, the redundant calls are observably idempotent (see
  **resyncs-synchronously-after-a-pick**).
- **Reassigning an unchanged label**: A resync unconditionally reassigns
  the label's displayed text to the view model's title on every call, even
  though the view model's title cannot change after construction. The
  component performs no early-exit/equality check before this
  reassignment (see **redraws-label-text-on-every-sync**).
- **Toggling the enabled state to its current value**: The enabled-state
  handler reassigns the button's enabled state and the label's opacity on
  every assignment, including a reassignment to the value already held;
  the platform's property-observation mechanism carries no built-in
  equality guard, and source adds none (see **dims-and-disables-the-row**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | font view model object | - (required) | Supplies the row's title and current font; receives committed font picks. The initializer also overwrites this view model's external-change handler with the component's own resync handler (see Edge Cases). |
| `isEnabled` | boolean | `true` | Dims and disables the row's button and label when set to `false` (see **dims-and-disables-the-row**). |

## Deep Linking

Not applicable: the font picker view is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none - hardcoded literal fragments) | `" — %@ pt"` / `" (not installed)"` | Built by a private helper and given as the button's title on every resync. |

The label's text comes from the view model's title, a value the caller
provides, so there is nothing for this component to localize there. The
`" — "`, `" pt"`, and `" (not installed)"` fragments inside that private
helper, however, are hardcoded English string-interpolation literals
assigned to the button's title (a plain string) - not wrapped in any
localization mechanism anywhere in source.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation or transition call anywhere; the enabled-state dimming (button state / label opacity) is an instantaneous property assignment, not an animated transition. |
| Increase Contrast | Not applicable to this file directly: source reads no system contrast setting and sets no custom color; the label's coloring comes from the active theme's primaryText role (tracks Increase Contrast automatically) and the button's title color is the platform's own default control rendering. Whether the 40%-opacity disabled dimming remains sufficiently contrasted is tracked once under Accessibility above (the open question on minimum-contrast-ratio), not duplicated here. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone; the enabled state is communicated through both the button's own interactive appearance (not merely a color) and the label's opacity, and the font name/installed-status is communicated through text, not color. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in source; the row always renders once constructed.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable - the component collects no data of
  its own; it only displays a font supplied by the view model and reports
  font picks back to it.
- **Storage**: Not applicable - source performs no read/write to disk or
  any other store; persistence, if any, is owned by the view model and
  its setting observer, which are not part of this file.
- **Transmission**: Not applicable - no networking call appears anywhere in
  source.
- **Retention**: The view retains only its own constituent elements and
  its reference to the view model for its own lifetime; it persists
  nothing beyond that.

## Logging

Not applicable: the source contains no logging call.

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)` and a
  trailing font-sample button (an `NSViewRepresentable` wrapping
  `FontChooserButton`, per `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button`'s
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
  `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button`'s Compose note); commit the
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
  **flags-an-uninstalled-font-in-its-title**. `init?(coder:)` and
  `init(frame:)` are both overridden to call `fatalError` (the mechanism
  behind **requires-view-model-at-construction**), leaving the designated
  `init(viewModel:)` as the only surviving construction path. There is no
  UIKit code path in source; a UIKit port has no `NSFontPanel` equivalent to defer to
  (see `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button`'s own AppKit/UIKit
  note for the button's side of that gap) and would need its own
  `isEnabled`-driven dimming, since UIKit has no direct `alphaValue`
  analogue on `UILabel` beyond its inherited `UIView.alpha`.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*`: a `TextBlock` bound to `viewModel.title`
  in column 0, and in column 1 the font-sample `Button` described in
  `agentictoolkit://cookbook/ui/settings/rows/font-chooser-button`'s own WinUI 3 note (its
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontPickerView.swift` |

## Design Decisions

**Decision**: `viewModel.onChange` is overwritten unconditionally in `init`,
replacing any handler already registered on that `FontViewModel` instance.
**Rationale**: Mirrors the same closure-property-assignment pattern
documented at `agentictoolkit://cookbook/ui/settings/rows/color-picker-view#requirements/owns-on-change`;
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
the open question on minimum-contrast-ratio under Accessibility).
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
`FontPickerView.swift` sets no `accessibilityLabel`/`setAccessibilityTitleUIElement`
linking `button` to the row's descriptive `label`, unlike the sibling
`CheckboxView`/`NumberFieldView`/`PopupMenuChoiceView` rows (see Label
requirements under Accessibility). `contrast-ratio` is `partial`: the
resolved contrast of the 40%-alpha disabled label cannot be determined
from this file alone (see the open question on minimum-contrast-ratio
under Accessibility).
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
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
