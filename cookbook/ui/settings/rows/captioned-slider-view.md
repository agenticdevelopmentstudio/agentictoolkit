---
id: 64825f85-8b4d-4406-befc-aa08ce55cc8b
title: Captioned Slider View
domain: agentictoolkit://cookbook/ui/settings/rows/captioned-slider-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings-row control pairing a slider with a title label and a live,
  formatter-derived trailing caption showing the current value.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/slider-view
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
- agentictoolkit://cookbook/ui/settings/rows/number-field-view
- agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view
references: []
approved-by: ''
approved-date: ''
---

# Captioned Slider View

## Overview

The Captioned Slider View is a settings row: a title label, a slider, and
a trailing caption label in one horizontal row. The caption shows the
slider's current value rendered through a caller-supplied formatter (e.g.
"multiply by 100 and append a percent sign" or "append the letter s"), for
use when the slider's handle position alone doesn't identify the current
value. The row is driven by a range view model: the component reflects
the view model's title/min/max/value on construction and whenever the
view model reports an external change, and it writes the user's slider
interactions back into the view model's setting observer.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, the
  slider, and the caption label in a single horizontal row, and MUST pin
  that row to the edges of the component.
- **sets-slider-range**: Component MUST set the slider's minimum and
  maximum from the view model's minimum and maximum at initialization.
- **does-not-validate-range**: Component MUST NOT validate or correct the
  view model's minimum/maximum before assigning them to the slider; an
  inverted or zero-width range is passed through unmodified.
- **slider-expands-to-fill-remaining-width**: Component MUST let the
  slider take up whatever width the row has left over after the title
  label and caption are laid out, rather than that leftover width going to
  the inter-item spacing (see Platform Notes for the mechanism the source
  uses).
- **caption-never-compressed**: Component MUST never compress the caption
  label below the width its text needs.
- **caption-uses-monospaced-digits**: Component MUST render the caption
  label with monospaced digit glyphs, so the caption's width does not
  jitter as its digits change.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the title label's text to the view model's title,
  the slider's value to the view model's value, and the caption label's
  text to the formatter applied to the view model's value.
- **updates-caption-live**: Component MUST update the caption label's text
  to the formatter applied to the new value immediately whenever the
  slider reports a new value, independent of any round trip through the
  view model.
- **commits-slider-value**: Component MUST write the slider's new value
  into the view model's setting observer whenever the slider reports a new
  value that differs from the setting observer's current value.
- **skips-redundant-commits**: Component MUST NOT write to the view
  model's setting observer when the slider's new value equals the setting
  observer's current value.
- **syncs-on-external-change**: Component MUST re-synchronize the title
  label's text, the slider's value, and the caption label's text — by
  re-reading the view model's title and value — whenever the view model
  reports an external change.
- **overwrites-view-model-onchange**: Component MUST register its own sync
  handler as the view model's external-change handler during
  initialization, replacing whatever handler, if any, was previously
  registered on that view model (see Platform Notes for the mechanism the
  source uses).
- **exposes-constituent-views**: Component MUST expose the title label,
  the slider, and the caption label as public, directly-accessible
  properties.
- **requires-view-model-and-formatter-at-construction**: Component MUST
  require both a view model and a formatter to construct a usable
  instance; no construction path may produce a usable instance without
  both (see Platform Notes for how the source enforces this on
  this platform).

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes stock text and slider controls into a
  row.
- **Padding**: The row's layout inserts a flexible gap between the title
  label and the remaining controls, using the settings row-spacing design
  token (currently 8pt) between label and gap and between slider and
  caption, while zeroing the gap between the flexible spacer and the
  slider — so the spacer's own width is the only space between the label
  and the slider. The row is pinned to all four edges of the component
  with no additional constant, so the component contributes 0pt of its own
  outer padding beyond that internal spacing (see Platform Notes for the
  mechanism the source uses).
- **Font**: Title label uses the button text role; caption label uses the
  code text role. Neither role's size or weight is set by this component
  — the theme's typography owns the resolved point size and weight per
  role, currently 13pt medium, proportional system font for the button
  role, and 12pt regular, monospaced for the code role. Both sizes scale
  with the active theme's size scale (1.0 by default) and both labels
  repaint automatically on a theme change.
- **Background**: None (transparent) — neither the title nor caption
  label draws a background, border, or bezel of its own, and the
  component draws no background color of its own either.
- **Foreground/Text**: Title label uses the primaryText color role;
  caption label uses the secondaryText color role. Neither color is
  computed by this component — the theme's palette owns both:
  primaryText currently resolves to the active theme's foreground color
  at full strength, and secondaryText currently resolves to that same
  foreground dimmed 32% toward the background color with a minimum
  contrast ratio of 3.0 enforced. Both recompute live on a theme change.
- **Border**: Not applicable — no border is drawn or configured anywhere.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set; sizing is governed entirely by the slider expanding
  to fill remaining width and the caption never being compressed (see
  **slider-expands-to-fill-remaining-width** and
  **caption-never-compressed**).

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; slider is at the view model's value; caption shows the formatter applied to the view model's value. |
| Dragging | Caption updates live to the formatter applied to the new value as the slider reports it, ahead of any view-model round trip (see updates-caption-live). |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are the platform's default rendering, not custom to this file. |
| Disabled | Not applicable: an enabled/disabled state is never set on the slider or text fields in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and labels use the platform's default focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults — no
  custom accessibility role or element grouping is set in source. The
  slider and text elements each carry the platform's built-in
  accessibility role (slider, static text) automatically.
- **Label requirements**: The title label and the slider are laid out as
  sibling elements in the same row, but source sets no accessibility link
  (equivalent to a label/title-element association) on the slider linking
  it to the title text — confirmed by comparison with sibling row
  controls in this system, several of which do set that link on their
  control, but neither this component nor the plain slider row it's
  modeled on does so. Without that link, a screen reader announces the
  slider on its own when focus lands on it, with no route to the row's
  title text, unlike the sibling control-with-label rows.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — the component's interactive
  element is a continuous drag control (the slider) sized to the row's
  available width and the platform's own control metrics, not a small
  fixed-size tap target to check against a minimum (see Platform Notes
  for platform-specific minimum-control-size guidance).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| captioned-slider-view-001 | arranges-row-layout | Construct with any view model/formatter | The title label, slider, and caption label are all part of a single row that is pinned to the component's edges; no other layout container appears |
| captioned-slider-view-002 | sets-slider-range | View model minimum is 0, maximum is 1 | After construction, the slider's minimum is 0 and its maximum is 1 |
| captioned-slider-view-014 | does-not-validate-range | View model minimum is 10, maximum is 5 (inverted) | After construction, the slider's minimum is 10 and its maximum is 5, unmodified — no validation or correction is applied |
| captioned-slider-view-003 | slider-expands-to-fill-remaining-width | Construct the component | After construction, the slider claims all the row's leftover width rather than the inter-item spacing (verified as a layout-priority/weight check specific to the platform's layout system) |
| captioned-slider-view-004 | caption-never-compressed | Construct the component | After construction, the caption label is never sized below the width its text needs (verified as a layout-priority/weight check specific to the platform's layout system) |
| captioned-slider-view-005 | caption-uses-monospaced-digits | Construct the component | The caption label's font includes the monospaced-digit font feature |
| captioned-slider-view-006 | initializes-from-view-model | View model title "Volume", value 42, formatter that converts a value straight to its integer string | After construction, the title label reads "Volume", the slider's value is 42, and the caption label reads "42" |
| captioned-slider-view-007 | updates-caption-live | Set the slider's value to 75 and simulate the slider reporting that value, with a formatter that appends a percent sign | The caption label becomes "75%" immediately, without any external-change notification firing from the view model |
| captioned-slider-view-008 | commits-slider-value | The view model's setting observer value is 10; set the slider's value to 30 and simulate the slider reporting that value | The setting observer's value is 30 after the call |
| captioned-slider-view-009 | skips-redundant-commits | The view model's setting observer value is 50; set the slider's value to 50 (same value) and simulate the slider reporting that value | Using a spy/counting setting observer in place of the real one, the write count recorded before the call equals the write count recorded after — the setting observer's value is not written a second time |
| captioned-slider-view-010 | syncs-on-external-change | After construction, externally change the view model's title and value, then trigger the view model's external-change notification with the new value | The title label, the slider's value, and the caption label all update to reflect the new view-model state |
| captioned-slider-view-015 | overwrites-view-model-onchange | Register a counting handler as the view model's external-change handler before constructing the component, then trigger that notification after construction | The pre-registered handler is never invoked; only the component's own sync handler runs |
| captioned-slider-view-011 | exposes-constituent-views | Construct the component, then access its title label, slider, and caption label from outside the type | All three properties are accessible and return the same instances built during construction |
| captioned-slider-view-012 | requires-view-model-and-formatter-at-construction | Attempt to construct via a serialization/decoding-based construction path that supplies neither a view model nor a formatter | Construction is rejected; no usable instance is produced. Not testable as an ordinary in-process assertion on every platform — where the failure mode is a runtime trap rather than a thrown/returned error, this requires a crash-test harness or a compile-time/unavailable check instead. |
| captioned-slider-view-013 | requires-view-model-and-formatter-at-construction | Attempt to construct via a bare/default construction path that supplies neither a view model nor a formatter | Construction is rejected; no usable instance is produced. Same testing caveat as above. |

## Edge Cases

- Null/empty input: the view model and formatter are both required
  constructor parameters, ruled out from being missing by the platform's
  type system, so the component needs no nil-handling path for either.
- Boundary values — inverted/zero-width range: source performs no
  minimum-less-than-maximum validation before assigning the slider's
  minimum/maximum from the view model (see **does-not-validate-range**).
  If the view model's minimum is greater than or equal to its maximum, the
  resulting slider behavior is whatever the platform's slider control does
  for an equal-or-inverted range.
- Concurrent access: Not applicable — the component and the formatter are
  both confined to the UI thread, so all construction and mutation is
  serialized to that thread; there is no code path by which two threads
  can mutate the component simultaneously.
- Error states: Not applicable — every operation in this file (reading the
  slider's reported value, calling the formatter, and writing the setting
  observer's value) is a synchronous, non-throwing call; no error-producing
  path appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- Overwritten external observer: the view model's external-change handler
  is a single property, and the component's initializer unconditionally
  overwrites it (see **overwrites-view-model-onchange**). Constructing a
  second instance of this component (or any other observer) against the
  same view model silently drops the earlier handler; the component MUST
  NOT be assumed to coexist with another external-change observer already
  registered on the same view model instance.
- Caption can change a second time after release: the component sets the
  caption optimistically from the slider's reported value before writing
  to the setting observer. If that write causes the setting observer to
  clamp or otherwise transform the value and re-report an external change,
  the component's sync logic then overwrites the caption with the
  formatter applied to the view model's value — the view model's actual
  accepted value, not the optimistic reported value. This is inferred from
  the interaction between the live-update and sync logic rather than
  stated as a single line in source; it is a SHOULD-level note for
  implementors: the caption SHOULD be expected to update a second time,
  after slider release, without further user action, whenever the view
  model does not accept a value as-given.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | range view model object | — (required) | Supplies the row's title and min/max/current value; receives committed slider changes via its setting observer. The initializer also overwrites this view model's external-change handler with the component's own sync handler (see Edge Cases). |
| `formatter` | a value-to-text formatting function | — (required) | Maps the current or in-progress slider value to the caption text shown at the trailing edge of the row (e.g. a percentage or seconds string). |

## Deep Linking

Not applicable: the component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in source.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes from the view model's title and its caption
text comes from the caller-supplied formatter; both are values the caller
provides, so there is nothing for this component to localize itself. The
example formatters in Overview are illustrative and are not locale-aware; a
caller building a locale-correct caption should format the formatter's
output with the platform's own number/percent formatting facility rather
than raw string interpolation — this component neither performs nor
enforces that choice.

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation or
  transition call; every state change is an instantaneous property
  assignment.
- **Increase Contrast**: This component itself sets no custom color; both
  labels get their color from theme color roles (primaryText for the
  title, secondaryText for the caption), not from unstyled control
  defaults (see Appearance → Foreground/Text). The theme's palette does
  not read the system's Increase Contrast signal, so the row's contrast
  does not change when a user turns that system setting on; whatever the
  active theme's colors resolve to is what both labels show either way.
- **Differentiate Without Color**: Not applicable — the current value is
  communicated through the slider's thumb position and the caption's
  text, not through any color-only signal; no color-coded state exists in
  source.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in source; the row always renders once constructed.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by the view model and
  reports slider changes back through the view model's setting observer.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store; persistence, if any, is owned by the view model and
  its setting observer, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the component retains only its own
  constituent elements and its reference to the view model/formatter for
  its own lifetime; it persists nothing beyond that.

## Logging

Not applicable: the source contains no logging call.

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)`, a
  `Slider(value:in:)` bound to the current value, and a trailing
  `Text(formatter(value)).monospacedDigit()`. SwiftUI has no direct
  analog to `contentHuggingPriority`/`contentCompressionResistancePriority`
  as raw numbers; give the `Slider` no fixed frame (it already expands to
  fill the `HStack`'s remaining space, mirroring
  slider-expands-to-fill-remaining-width) and apply `.fixedSize()` (or
  `.layoutPriority(1)`) to the caption `Text` to mirror
  caption-never-compressed. Drive the caption from the `Binding`'s
  setter — called on every drag tick as the `Slider` writes through it —
  to mirror updates-caption-live; `onEditingChanged` fires only at the
  start and end of a drag, so it is the analog of the commit step
  (mirroring commits-slider-value/skips-redundant-commits), not of the
  live update.
- **Compose**: Use a `Row` with `Modifier.weight(1f)` on the `Slider` (the
  Compose analog of the low hugging priority) between a leading
  `Text(title)` and a trailing `Text(formatter(value))` styled with a
  tabular/monospace-figure font feature. Drive the trailing caption from
  the `Slider`'s `onValueChange` callback immediately (mirroring
  updates-caption-live), and commit to the backing state/view-model from
  the same callback with an equality check before writing, mirroring
  skips-redundant-commits.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<span>` for the title, an `<input type="range" min max
  value>` given `flex: 1` (mirroring slider-expands-to-fill-remaining-width),
  and a trailing `<span>` for the caption given `flex: 0 0 auto;
  white-space: nowrap` plus a tabular-nums font (mirroring
  caption-never-compressed and caption-uses-monospaced-digits). Update the
  caption text on the range input's `onInput` handler immediately, and
  commit the value upward via a controlled `value`/`onChange` prop pair,
  comparing against the previous value before calling the parent's setter
  to mirror skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CaptionedSliderView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`-isolated
  (the mechanism behind confines-to-ui-thread), inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`.
  It composes three subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel`, an `NSSlider`, and a monospaced-digit
  `NSTextField` caption from `ComposableSettings.makeValueLabel
  (monospacedDigits: true)` — into one row via `ComposableSettings.makeRow`
  and `pinToEdges`, with the slider's horizontal content-hugging priority
  set to `1` (the mechanism behind
  slider-expands-to-fill-remaining-width) and the caption's horizontal
  compression resistance set to `.required` (the mechanism behind
  caption-never-compressed). Both inherited `NSView` initializers that
  could construct the view without a `viewModel`/`formatter` —
  `init(coder:)` and the frame-only `init(frame:)` — are forced to
  fatal-error, leaving `init(viewModel:formatter:)` as the only usable
  initializer; this is the mechanism behind
  requires-view-model-and-formatter-at-construction. There is no UIKit
  code path in source; a UIKit port would replace `NSSlider`/`NSTextField`
  with `UISlider`/`UILabel` and the `target`/`action` pattern with
  `.addTarget(_:action:for: .valueChanged)` — UIKit has no `NSCoder`-vs-frame
  initializer split to fatal-error on both the way the source's two
  initializers do.
- **WinUI 3**: Build the row as a `Grid`
  with column definitions `Auto,*,Auto`: a `TextBlock` for the title in
  column 0; a `Slider Minimum="{min}" Maximum="{max}"
  Value="{x:Bind Value, Mode=TwoWay}" HorizontalAlignment="Stretch"` in
  column 1 (the `*` column is the WinUI analog of the `1`-priority
  hugging — it lets the `Slider` claim the width left over after the
  `Auto`-sized title and caption columns); a trailing `TextBlock` bound to
  a formatted string (via an `IValueConverter` mirroring `formatter`) in
  column 2, whose `Auto` column width is the WinUI analog of
  caption-resists-compression (the column, and so the `TextBlock`, is
  never compressed below its content). Use the `Slider`'s `ValueChanged`
  event handler — not only the two-way `x:Bind` — to update the caption
  `TextBlock` immediately on every drag tick, mirroring
  updates-caption-live; write the committed value through a property
  setter that skips the assignment (and so skips raising
  `INotifyPropertyChanged`) when the incoming value already equals the
  current value, mirroring skips-redundant-commits.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CaptionedSliderView.swift` |

## Design Decisions

- **Decision** (AppKit): Update the caption label from the slider's raw
  `newValue` inside `sliderChanged(_:)`, ahead of writing to
  `viewModel.settingObserver.value`, rather than waiting for `sync()` to
  run off the round-tripped `viewModel.value`.
  **Rationale**: This gives the caption an immediate, per-tick update
  while dragging instead of a value that lags one `onChange` cycle behind
  the slider's own position.
  **Approved**: pending
- **Decision** (AppKit): Set the slider's horizontal content-hugging
  priority to `1` and the caption label's horizontal
  compression-resistance priority to `.required`.
  **Rationale**: The source comment states this priority is "below the
  row spacer's `defaultLow` so the slider, not the gap, takes the width
  left over after the label and caption" — this makes the slider, rather
  than inter-item spacing or the caption, absorb any extra row width,
  while guaranteeing the caption is never truncated.
  **Approved**: pending
- **Decision**: Guard the setting observer's value assignment with an
  equality check before writing.
  **Rationale**: Avoids redundant writes to the observer (and any
  observer-driven feedback loop) when the slider reports a value that
  hasn't actually changed.
  **Approved**: pending
- **Decision** (AppKit): Force a fatal error from both `init(coder:)` and
  the frame-only `init(frame:)`, leaving `init(viewModel:formatter:)` as
  the only usable initializer.
  **Rationale**: The view has no meaningful default state — it cannot
  render a title, range, or caption without a view model and a
  formatter — so both inherited `NSView` initializers that could
  construct it without those are intentionally disabled rather than left
  to produce a half-configured row.
  **Approved**: pending
- **Decision**: Overwrite the view model's external-change handler
  unconditionally at construction, rather than composing with or
  preserving any handler already registered on that view model.
  **Rationale**: The source's external-change property is a single
  closure/callback slot; giving the row exclusive ownership of it avoids
  ambiguity about ordering multiple observers, at the cost of silently
  dropping any handler registered before construction (see
  **overwrites-view-model-onchange**).
  **Approved**: pending
- **Decision**: Assign the view model's minimum/maximum straight to the
  slider's minimum/maximum with no minimum-less-than-maximum check.
  **Rationale**: Bounds validation is the view model's responsibility, if
  anywhere; adding a second check in the view would duplicate that
  concern and could silently mask a caller bug instead of surfacing it
  (see **does-not-validate-range**).
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`keyboard-navigable` and `screen-reader-support` are `partial` because
source sets no custom focus-ring or accessibility-linkage code at all:
Tab-order and arrow-key behavior come from `NSSlider`/`NSControl`'s
un-verified default AppKit handling, and the slider carries no
`setAccessibilityTitleUIElement(label)` (or equivalent) link to its title
— see Accessibility → Label requirements. The remaining checks rest on
`CaptionedSliderView.swift`'s use of stock `NSSlider`/`ThemedLabel`
instances via `ComposableSettings.makeRow` and `makeRowLabel`/
`makeValueLabel`, the `settingObserver.value != newValue` guard before
every write, and the file's single responsibility (row composition and
value sync, with rendering and formatting delegated elsewhere).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for CaptionedSliderView, covering row layout/priority behavior, live-versus-committed value sync, and one open accessibility question (slider/title label association) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: add named requirements and test vectors for the unvalidated range and the overwritten `onChange` observer; decouple Appearance's font/color values from the theme files that own them; fix the Increase Contrast contradiction, the formatter-escaping claim, and the SwiftUI `onEditingChanged` guidance; drop RFC 2119 misuse and an editorial aside from Edge Cases and Platform Notes; correct the Compliance table and add related sibling-recipe links; note that the example formatters aren't locale-aware. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
