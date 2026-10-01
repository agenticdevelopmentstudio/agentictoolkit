---
id: 0cbe1932-5c7e-4546-829d-0294708d499c
title: Slider View
domain: agentictoolkit://cookbook/ui/settings/rows/slider-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a title label with a slider bound to a
  range view model, syncing value and range from the view model.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/captioned-slider-view
references: []
approved-by: ''
approved-date: ''
---

# Slider View

## Overview

The Slider View is a settings row: a title label and a slider in one
horizontal row, with no trailing caption (contrast with the sibling
captioned slider row
(agentictoolkit://cookbook/ui/settings/rows/captioned-slider-view), which
adds a formatter-derived value label). The row is driven by a range view
model: the component sets the slider's range and value from the view
model at construction, writes the user's slider interactions back into
the view model's value, and re-synchronizes the label text and the
slider's range and value whenever the view model reports an external
change — including the range, which the sibling captioned slider row does
not re-apply after construction.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label and the
  slider in a single horizontal row, and MUST pin that row to the edges
  of the view.
- **sets-slider-range**: Component MUST set the slider's minimum and
  maximum bounds from the view model's minValue and maxValue at
  initialization.
- **slider-hugs-loosely**: Component MUST give the slider a horizontal
  content-hugging priority of `1` — below the row spacer's own low
  default priority — so the slider, not the inter-item spacing, takes the
  width left over after the label.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to the view model's title and the
  slider's value to the view model's value.
- **commits-slider-value**: Component MUST write the slider's new value
  into the view model's value whenever the slider reports a change and
  the new value differs from the view model's current value.
- **skips-redundant-commits**: Component MUST NOT write to the view
  model's value when the slider's new value equals its current value.
- **syncs-on-external-change**: Component MUST re-synchronize the
  label's text and the slider's minimum, maximum, and current value —
  re-reading the view model's title, minValue, maxValue, and value —
  whenever the view model reports a change.
- **exposes-constituent-views**: Component MUST expose the label and the
  slider as public, directly-accessible properties.

Construction requires a view model; every other construction path is
rejected, a platform mechanic rather than a normative requirement here — see rejects-coder-initialization and
rejects-frame-only-initialization under Platform Notes.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes a label and a slider into a row.
- **Padding**: The row layout inserts a flexible spacer between the label
  and the slider, with 8pt spacing between the label and the spacer, and
  0pt between the spacer and the slider, so the spacer's own width is the
  only thing between the label and the slider. The row is pinned directly
  to the component's edges with no additional constant, so the component
  contributes 0pt of its own outer padding beyond that internal 8pt / 0pt
  spacing.
- **Font**: The label resolves to the theme's button text role: 13pt,
  medium weight, proportional system font. The size scales with the
  active theme's size scale, and the label repaints automatically on a
  theme change.
- **Background**: None (transparent) — the label draws no background,
  border, or bezel, and neither the component nor its row container sets
  a background color of its own. The slider uses the platform's default,
  unconfigured rendering.
- **Foreground/Text**: The label resolves to the active theme's
  primary-text role at full strength, recomputed live on a theme change.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in source.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in source; the slider's width is governed entirely by
  the horizontal content-hugging priority set at initialization, with no
  compression-resistance override on either subview.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; slider is at the view model's value with its range set to the view model's minValue/maxValue. |
| Dragging | No custom dragging visual: the slider's default continuous-tracking behavior is left unmodified in source, so it reports a change on every drag tick (not only on release), each tick invoking commits-slider-value/skips-redundant-commits; there is no caption or other view state to update, so the only visible motion is the slider's own native thumb tracking. |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are the platform's default rendering, not custom to this component. |
| Disabled | Not applicable: the enabled state is never set on the slider or the text field in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and label use the platform's default focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults — no
  explicit accessibility-role call appears in source. The slider and the
  label each carry the platform's built-in accessibility role (slider,
  static text) automatically.
- **Label requirements**: The label and the slider are laid out as
  sibling views in the same row, but source links no accessible name from
  the slider to the label text — confirmed by comparison with sibling row
  views in the same directory: the checkbox row, the number field row,
  and the popup menu choice row each link their control to the label, but
  this component does not do so for the slider. Without that link, a
  screen reader announces the slider on its own with no reference to the
  row's title when focus lands on it.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a pointer/
  trackpad-driven control composition (no touch input path in source);
  the 44×44pt minimum is touch guidance, not a pointer-interface
  requirement.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source.
  The label's text color resolves via the theme's primaryText role, whose
  floor against the background is a minimum contrast of 3.0 — below the
  4.5:1 small-text threshold — and the component performs no contrast
  check of its own; settling whether a given theme's resolved pair
  actually meets 4.5:1 needs a theme-level contrast audit of primaryText
  against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| slider-view-001 | arranges-row-layout | Construct the component with any view model | The row's arranged elements are exactly the label, an inserted row-spacer, and the slider, in that order; that row container is the component's only child and is pinned to its edges; no other layout container appears |
| slider-view-002 | sets-slider-range | The view model's minValue = 0, maxValue = 1 | After construction, the slider's minimum is 0 and its maximum is 1 |
| slider-view-003 | slider-hugs-loosely | Construct the component | After construction, the slider's horizontal content-hugging priority is 1 |
| slider-view-004 | initializes-from-view-model | The view model's title = "Volume", value = 42 | After construction, the label reads "Volume" and the slider's value is 42 |
| slider-view-005 | commits-slider-value | The view model's value = 10; set the slider's value to 30 and trigger its change notification | The view model's value is 30 after the call |
| slider-view-006 | skips-redundant-commits | Substitute a counting observer test double whose value setter increments a write counter; set its value to 50, reset the counter to 0, then set the slider's value to 50 (same value) and trigger its change notification | The counting observer's write counter stays at 0 after the call |
| slider-view-007 | syncs-on-external-change | After construction, externally change the view model's title, minValue, maxValue, and value, then trigger the view model's change notification | The label and the slider's minimum, maximum, and value all update to reflect the new view-model state |
| slider-view-008 | exposes-constituent-views | Construct the component, then access its label and slider from outside the type | Both properties are accessible and return the same label/slider instances built during construction |
| slider-view-011 | syncs-on-external-change | Change the value on the backing setting that the view model observes (not by triggering the view model's change notification directly), then await one main-queue turn (the dispatch hop between the setting's storage and the view model's observer) | The label and the slider's minimum, maximum, and value are unchanged immediately after the setting write, and only update to reflect the new state after that main-queue turn elapses |
| slider-view-012 | sets-slider-range | Construct the component with the view model's minValue = 10, maxValue = 0 (an inverted range; a zero-width case such as minValue = maxValue = 5 is equivalent) | The slider's minimum is 10 and its maximum is 0 — assigned unchanged from the view model, with no clamping, swapping, or correction |

## Edge Cases

- Null/empty input: the view model is a non-optional, non-escaping-typed
  constructor parameter, so the type system rules out a missing value at
  the call site — this is a property of the parameter's type, not a
  behavior the component implements, so the component provides, and
  needs, no nil-handling path of its own for its one initializer
  parameter.
- Boundary values — inverted/zero-width range: source performs no
  minValue-less-than-maxValue validation before assigning the slider's
  minimum/maximum from the view model, either at initialization or in the
  change-notification re-sync (see slider-view-012). If the view model's
  minValue is greater than or equal to its maxValue, the component adds
  no guard of its own; the resulting slider behavior is whatever the
  platform's slider control does for an equal-or-inverted range. This is
  an absence rather than an enforced rule: nothing in source validates or
  corrects the view model's bounds.
- Concurrent access: Not applicable — the component and its
  change-notification callback are both confined to the UI thread, so
  the platform's concurrency checker serializes all access; there is no
  code path by which two threads can mutate the view simultaneously.
- Error states: Not applicable — every operation in this component (the
  slider's change notification and the write to the view model's value)
  is a synchronous, non-throwing call; no error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- Overwritten external observer: the view model's change-notification
  callback is a single closure property, and the component's initializer
  unconditionally assigns its own handler to it. See the
  one-observer-per-view-model Design Decision for the resulting contract
  and its rationale.
- Asynchronous re-sync timing: the view model's change notification is
  delivered through an observer on a later turn of the main dispatch
  queue rather than synchronously. A commit made inside the slider's own
  change handler therefore does not trigger this component's re-sync
  back synchronously within the same call; the label/range/value re-sync
  in syncs-on-external-change happens on a later turn of the main
  dispatch queue, not inline with the triggering slider action. This is a
  SHOULD-level implementor note: the range and value re-sync SHOULD be
  expected to lag one dispatch-queue turn behind a commit made by this
  same component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | range view model (double-valued) | — (required) | Supplies the row's title and min/max/current value; receives committed slider changes via its value. The initializer also overwrites this view model's change-notification callback with the component's own re-sync handler (see Edge Cases). |

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in source.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes from the view model's title, a value the
caller provides through the view model, not a literal set directly in
this file; there is nothing for this component to localize itself.

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation or
  transition call; every state change is an instantaneous property
  assignment.
- **Increase Contrast**: Not applicable — source sets no custom color
  anywhere; whatever coloring the row has comes entirely from the
  label's palette-driven text color and the slider's default platform
  rendering, both of which follow system Increase Contrast automatically.
- **Differentiate Without Color**: Not applicable — the current value is
  communicated only through the slider's thumb position; there is no
  caption or other color-coded signal in source to differentiate.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in source; the row always renders once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by the view model and
  reports slider changes back through the view model's value.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store; persistence, if any, is owned by the view model, which
  is not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own subviews
  and its reference to the view model for its own lifetime; it persists
  nothing beyond that.

## Logging

Not applicable: source contains no logging call (no print, log, or
logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Compose an `HStack` with `Text(viewModel.title)` and a
  `Slider(value:in:)` bound to the current value and range. SwiftUI has no
  direct analog to a raw content-hugging priority number; give the
  `Slider` no fixed frame — it already expands to fill the `HStack`'s
  remaining space, mirroring slider-hugs-loosely. Drive the `Slider`'s
  `in:` bounds from `@State`/`@ObservedObject` properties fed by the view
  model, updating them (not just the value) whenever the view model
  publishes a change, to mirror syncs-on-external-change's re-application
  of range as well as value.
- **Compose**: Use a `Row` with a leading `Text(title)` and a `Slider`
  given `Modifier.weight(1f)` (the Compose analog of the low hugging
  priority) whose `valueRange` is bound to the view model's min/max.
  Commit to the backing state/view-model from the `Slider`'s
  `onValueChange` callback with an equality check before writing,
  mirroring skips-redundant-commits, and re-read both the value and the
  `valueRange` whenever the backing view model changes, mirroring
  syncs-on-external-change.
- **React/Web**: A flex row (`display: flex; align-items: center`)
  containing a `<span>` for the title and an `<input type="range" min max
  value>` given `flex: 1` (mirroring slider-hugs-loosely). Commit the
  value upward via a controlled `value`/`onChange` prop pair, comparing
  against the previous value before calling the parent's setter to mirror
  skips-redundant-commits; re-render the input's `min`/`max`/`value`
  attributes together whenever the parent's bound range or value props
  change, to mirror syncs-on-external-change.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SliderView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside
  the `ComposableSettings` namespace, conforming to `SettingsViewProtocol`.
  It composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and a plain `NSSlider()` — into one row
  via `ComposableSettings.makeRow` and `pinToEdges`, with the slider's
  horizontal content-hugging priority set to `1`. It supports construction
  only through the initializer that takes a view model: both `init(coder:)`
  and the frame-only `init(frame:)` trigger a fatal error rather than
  producing an instance (rejects-coder-initialization,
  rejects-frame-only-initialization). There is no UIKit code path in
  source; a UIKit port would replace `NSSlider`/`NSTextField` with
  `UISlider`/`UILabel` and the `target`/`action` pattern with
  `.addTarget(_:action:for: .valueChanged)` — `UIView` has the same
  `init(coder:)`/`init(frame:)` split as `NSView`, so a UIKit port would
  fatal-error on both initializers the way rejects-coder-initialization
  and rejects-frame-only-initialization do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*`: a `TextBlock` for the title in column
  0, and a `Slider Minimum="{x:Bind Min, Mode=OneWay}"
  Maximum="{x:Bind Max, Mode=OneWay}" Value="{x:Bind Value, Mode=TwoWay}"
  HorizontalAlignment="Stretch"` in column 1 (the `*` column is the WinUI
  analog of the `1`-priority hugging — it lets the `Slider` claim the
  width left over after the `Auto`-sized title column). Bind `Minimum`/
  `Maximum` with `Mode=OneWay` from the same view-model properties as
  `Value`, so a change pushed from the view model updates the slider's
  range as well as its position, mirroring syncs-on-external-change (a
  plain `Value`-only `x:Bind` would miss the range re-application this
  component performs that its sibling captioned slider row does not).
  Write the committed value through a property setter that skips the
  assignment (and so skips raising `INotifyPropertyChanged`) when the
  incoming value already equals the current value, mirroring
  skips-redundant-commits.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SliderView.swift` |

## Design Decisions

- Decision: Re-apply the slider's minimum and maximum (in addition to the
  label text and the slider's value) inside the external-change handler,
  not just at initialization — unlike the sibling captioned slider row
  (agentictoolkit://cookbook/ui/settings/rows/captioned-slider-view),
  whose sync leaves the slider's range untouched after construction.
  Rationale: Lets a caller mutate the view model's range after the row is
  built and have the slider reflect the new bounds without recreating the
  view.
  Approved: pending
- Decision: Give the slider a low horizontal content-hugging priority
  (AppKit/UIKit source: set to `1`).
  Rationale: The source comment states this priority is set below the
  row spacer's own low default priority so the slider, not the gap,
  takes the width left over after the label — this makes the slider,
  rather than inter-item spacing, absorb any extra row width.
  Approved: pending
- Decision: Guard the view model's value assignment with an equality
  check before writing.
  Rationale: Avoids redundant writes to the view model (and any
  observer-driven feedback loop) when the slider reports a value that
  hasn't actually changed.
  Approved: pending
- Decision: Force a fatal error from both the coder-based and the
  frame-only initializers (AppKit/UIKit source: `init(coder:)`, the
  frame-only `init(frame:)`), leaving the view-model-taking initializer
  as the only usable one.
  Rationale: The view has no meaningful default state — it cannot render
  a title or range without a view model — so both inherited initializers
  that could construct it without one are intentionally disabled rather
  than left to produce a half-configured row.
  Approved: pending
- Decision: Assign the component's change-notification handler
  unconditionally at construction, without preserving or chaining any
  handler already registered on the same view-model instance —
  constructing a second instance of this component (or any other
  observer) against the same view model silently drops the earlier
  handler.
  Rationale: This component owns its view model's re-sync handler for the
  view's lifetime; supporting more than one simultaneous observer on a
  single view model would need a multicast mechanism the source does not
  implement, so one view per view model is the stated limit rather than
  an unstated side effect.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`keyboard-navigable` and `screen-reader-support` rest on `NSSlider`/`NSTextField`'s
default AppKit accessibility and focus behavior; `screen-reader-support` is
`partial` because source sets no `accessibilityLabel`/`accessibilityTitleUIElement`
linking the slider to the label (see Accessibility, label requirements). The
other rows rest on source composing only stock
`NSView`/`NSControl` instances with no custom drawing, network, or persistence
code of its own.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for SliderView, covering row layout/priority behavior, value-and-range sync on external change, and one open accessibility question (slider/title label association) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: add `related` link to CaptionedSliderView; rename requirement to rejects-coder-initialization and its citations; fix the AppKit/UIKit platform note's wrong claim about UIKit's initializer split; name the row's exact arranged subviews and require a counting settingObserver test double in the affected test vectors; add test vectors for the async re-sync path and the inverted/zero-width range; drop RFC 2119 wording from two purely observational edge cases; move the overwritten-observer edge case into a Design Decision; remap the Compliance table's semantic-markup row to screen-reader-support and add the statuses' source rationale; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
